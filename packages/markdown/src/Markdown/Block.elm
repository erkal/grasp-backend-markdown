module Markdown.Block
    exposing
        ( Block(..)
        , BlockContent(..)
        , CodeBlock(..)
        , Fence
        , ListBlock
        , ListType(..)
        , ParseResult
        , parse
        , query
        , queryInlines
        , walk
        , walkInlines
        )

{-| Block types with source regions, and helpers.


# Model

@docs Block, BlockContent, CodeBlock, Fence, ListBlock, ListType


# Parsing

@docs ParseResult, parse


# Helpers

@docs walk, walkInlines, query, queryInlines

-}

import Array exposing (Array)
import Dict exposing (Dict)
import List.Extra
import Markdown.Config exposing (Options, defaultOptions)
import Markdown.Helpers exposing (References)
import Markdown.Inline exposing (Inline(..), InlineContent(..))
import Markdown.InlineParser as InlineParser
import Markdown.RawBlock as RawBlock
import Markdown.Wikilink exposing (WikilinkData)
import Regex exposing (Regex)


type alias Region =
    ( ( Int, Int ), ( Int, Int ) )


-- TYPES


{-| A block element with its source region.
-}
type Block b i
    = Block
        { content : BlockContent b i
        , region : Region
        }


{-| The block content type.
-}
type BlockContent b i
    = BlankLine String
    | ThematicBreak
    | Heading String Int (List (Inline i))
    | CodeBlock CodeBlock String
    | Paragraph String (List (Inline i))
    | BlockQuote (List (Block b i))
    | List ListBlock (List (List (Block b i)))
    | PlainInlines (List (Inline i))
    | Custom b (List (Block b i))


{-| CodeBlock type.
-}
type CodeBlock
    = Indented
    | Fenced Bool Fence


{-| Code fence model.
-}
type alias Fence =
    RawBlock.Fence


{-| List model.
-}
type alias ListBlock =
    { type_ : ListType
    , indentLength : Int
    , delimiter : String
    , isLoose : Bool
    }


{-| Types of list.
-}
type ListType
    = Unordered
    | Ordered Int


{-| Result of parsing a markdown string.
-}
type alias ParseResult b i =
    { blocks : List (Block b i)
    , blockIds : Dict String Region
    , wikilinks : Dict Region WikilinkData
    }



-- PARSING


{-| Parse a markdown string.
-}
parse : Maybe Options -> String -> ParseResult b i
parse maybeOptions str =
    let
        options : Options
        options =
            Maybe.withDefault defaultOptions maybeOptions

        ( refs, rawBlocks, sourceLines ) =
            RawBlock.parseBlockStructure str

        ( blocks, _ ) =
            assignRegions options refs sourceLines True 1 0 rawBlocks

        blockIds : Dict String Region
        blockIds =
            blocks |> List.concatMap collectBlockIds |> Dict.fromList
    in
    { blocks = blocks
    , blockIds = blockIds
    , wikilinks =
            blocks
                |> List.concatMap collectWikilinks
                |> Dict.fromList
    }


{-| Walk raw blocks and assign regions based on line counting.
Returns the wrapped blocks and the next available row.
-}
assignRegions : Options -> References -> Array String -> Bool -> Int -> Int -> List (RawBlock.RawBlock b i) -> ( List (Block b i), Int )
assignRegions options refs sourceLines textAsParagraph startRow colOffset rawBlocks =
    rawBlocks
        |> List.foldl
            (\rawBlock ( acc, row ) ->
                let
                    ( block, nextRow ) =
                        fromRawBlock options refs sourceLines textAsParagraph row colOffset rawBlock
                in
                ( block :: acc, nextRow )
            )
            ( [], startRow )
        |> Tuple.mapFirst List.reverse


fromRawBlock : Options -> References -> Array String -> Bool -> Int -> Int -> RawBlock.RawBlock b i -> ( Block b i, Int )
fromRawBlock options refs sourceLines textAsParagraph row colOffset rawBlock =
    let
        lineCount : Int
        lineCount =
            rawBlockLineCount rawBlock

        -- Exclusive end: end.row is the row AFTER the block.
        -- This ensures single-line blocks produce non-zero-width ranges.
        region : Region
        region =
            ( ( row, 1 ), ( row + lineCount, 1 ) )

        parseInlinesAt : Int -> String -> List (Inline i)
        parseInlinesAt startCol rawText =
            InlineParser.parse options refs ( row, startCol ) rawText
    in
    case rawBlock of
        RawBlock.Heading rawText lvl _ ->
            let
                headingContentCol =
                    1 + colOffset + headingPrefixLength sourceLines row
            in
            ( Block { content = Heading rawText lvl (parseInlinesAt headingContentCol rawText), region = region }
            , row + lineCount
            )

        RawBlock.Paragraph lines _ ->
            let
                rawText =
                    RawBlock.joinParagraphLines lines

                inlines =
                    parseInlinesAt (1 + colOffset) rawText
            in
            if not textAsParagraph then
                ( Block { content = PlainInlines inlines, region = region }, row + lineCount )

            else
                case inlines of
                    [ Inline { content } ] ->
                        case content of
                            HtmlInline _ _ _ ->
                                ( Block { content = PlainInlines inlines, region = region }, row + lineCount )

                            _ ->
                                ( Block { content = Paragraph rawText inlines, region = region }, row + lineCount )

                    _ ->
                        ( Block { content = Paragraph rawText inlines, region = region }, row + lineCount )

        RawBlock.BlockQuote childBlocks ->
            let
                bqColOffset =
                    colOffset + blockQuotePrefixWidth sourceLines row

                ( wrappedChildren, _ ) =
                    assignRegions options refs sourceLines True row bqColOffset childBlocks
            in
            ( Block { content = BlockQuote wrappedChildren, region = region }
            , row + lineCount
            )

        RawBlock.List listBlock items ->
            let
                listColOffset =
                    colOffset + listBlock.indentLength

                ( wrappedItems, _ ) =
                    items
                        |> List.foldl
                            (\itemBlocks ( itemsAcc, itemRow ) ->
                                let
                                    ( wrappedItemBlocks, nextItemRow ) =
                                        assignRegions options refs sourceLines listBlock.isLoose itemRow listColOffset itemBlocks
                                in
                                ( wrappedItemBlocks :: itemsAcc, nextItemRow )
                            )
                            ( [], row )
                        |> Tuple.mapFirst List.reverse
            in
            ( Block { content = List (fromRawListBlock listBlock) wrappedItems, region = region }
            , row + lineCount
            )

        RawBlock.Custom customBlock childBlocks ->
            let
                ( wrappedChildren, _ ) =
                    assignRegions options refs sourceLines True row colOffset childBlocks
            in
            ( Block { content = Custom customBlock wrappedChildren, region = region }
            , row + lineCount
            )

        RawBlock.PlainInlines _ ->
            ( Block { content = PlainInlines [], region = region }
            , row + lineCount
            )

        _ ->
            ( Block { content = fromRawBlockContent rawBlock, region = region }
            , row + lineCount
            )


fromRawBlockContent : RawBlock.RawBlock b i -> BlockContent b i
fromRawBlockContent rawBlock =
    case rawBlock of
        RawBlock.BlankLine str ->
            BlankLine str

        RawBlock.ThematicBreak ->
            ThematicBreak

        RawBlock.Heading rawText level inlines ->
            Heading rawText level inlines

        RawBlock.CodeBlock codeBlock codeLines ->
            CodeBlock (fromRawCodeBlock codeBlock) (RawBlock.joinCodeLines codeLines)

        RawBlock.Paragraph lines inlines ->
            Paragraph (RawBlock.joinParagraphLines lines) inlines

        RawBlock.PlainInlines inlines ->
            PlainInlines inlines

        -- Recursive variants handled in fromRawBlock; these are unreachable
        -- but Elm requires exhaustive patterns. Sentinel text for debugging.
        RawBlock.BlockQuote _ ->
            BlankLine "[BUG: BlockQuote reached fromRawBlockContent]"

        RawBlock.List _ _ ->
            BlankLine "[BUG: List reached fromRawBlockContent]"

        RawBlock.Custom _ _ ->
            BlankLine "[BUG: Custom reached fromRawBlockContent]"


headingPrefixLength : Array String -> Int -> Int
headingPrefixLength sourceLines row =
    case Regex.findAtMost 1 headingPrefixRegex (getSourceLine sourceLines row) of
        match :: _ ->
            String.length match.match

        [] ->
            0


headingPrefixRegex : Regex
headingPrefixRegex =
    Regex.fromString "^ {0,3}#{1,6}[ \\t]+"
        |> Maybe.withDefault Regex.never


blockQuotePrefixWidth : Array String -> Int -> Int
blockQuotePrefixWidth sourceLines row =
    case Regex.findAtMost 1 blockQuotePrefixRegex (getSourceLine sourceLines row) of
        match :: _ ->
            String.length match.match

        [] ->
            2


blockQuotePrefixRegex : Regex
blockQuotePrefixRegex =
    Regex.fromString "^ {0,3}>[ ]?"
        |> Maybe.withDefault Regex.never


getSourceLine : Array String -> Int -> String
getSourceLine sourceLines row =
    Array.get (row - 1) sourceLines
        |> Maybe.withDefault ""


rawBlockLineCount : RawBlock.RawBlock b i -> Int
rawBlockLineCount rawBlock =
    case rawBlock of
        RawBlock.BlankLine _ ->
            1

        RawBlock.ThematicBreak ->
            1

        RawBlock.Heading rawText _ _ ->
            let
                textLines : Int
                textLines =
                    rawText |> String.lines |> List.length
            in
            if textLines > 1 then
                -- Multi-line raw text means setext heading (text + underline)
                textLines + 1

            else
                -- Single-line: could be ATX or single-line setext.
                -- Single-line setext is indistinguishable from ATX without
                -- parser metadata, so we accept a possible off-by-one for
                -- single-line setext headings.
                1

        RawBlock.CodeBlock codeBlock codeLines ->
            let
                numCodeLines : Int
                numCodeLines =
                    List.length codeLines
            in
            case codeBlock of
                RawBlock.Fenced isOpen _ ->
                    if isOpen then
                        numCodeLines + 1

                    else
                        numCodeLines + 2

                RawBlock.Indented ->
                    max 1 numCodeLines

        RawBlock.Paragraph lines _ ->
            List.length lines

        RawBlock.BlockQuote blocks ->
            blocks |> List.map rawBlockLineCount |> List.sum

        RawBlock.List _ items ->
            items |> List.map (List.map rawBlockLineCount >> List.sum) |> List.sum

        RawBlock.PlainInlines _ ->
            1

        RawBlock.Custom _ blocks ->
            blocks |> List.map rawBlockLineCount |> List.sum


fromRawCodeBlock : RawBlock.CodeBlock -> CodeBlock
fromRawCodeBlock rawCb =
    case rawCb of
        RawBlock.Indented ->
            Indented

        RawBlock.Fenced isOpen fence ->
            Fenced isOpen fence


fromRawListBlock : RawBlock.ListBlock -> ListBlock
fromRawListBlock raw =
    { type_ = fromRawListType raw.type_
    , indentLength = raw.indentLength
    , delimiter = raw.delimiter
    , isLoose = raw.isLoose
    }


fromRawListType : RawBlock.ListType -> ListType
fromRawListType raw =
    case raw of
        RawBlock.Unordered ->
            Unordered

        RawBlock.Ordered start ->
            Ordered start



-- BLOCK ID EXTRACTION


collectBlockIds : Block b i -> List ( String, Region )
collectBlockIds (Block blockRec) =
    let
        selfId : List ( String, Region )
        selfId =
            case blockRec.content of
                Paragraph rawText _ ->
                    extractBlockId rawText
                        |> Maybe.map (\id_ -> [ ( id_, blockRec.region ) ])
                        |> Maybe.withDefault []

                Heading rawText _ _ ->
                    extractBlockId rawText
                        |> Maybe.map (\id_ -> [ ( id_, blockRec.region ) ])
                        |> Maybe.withDefault []

                _ ->
                    []

        childIds : List ( String, Region )
        childIds =
            case blockRec.content of
                BlockQuote blocks ->
                    blocks |> List.concatMap collectBlockIds

                List _ items ->
                    items |> List.concatMap (List.concatMap collectBlockIds)

                Custom _ blocks ->
                    blocks |> List.concatMap collectBlockIds

                _ ->
                    []
    in
    selfId ++ childIds


extractBlockId : String -> Maybe String
extractBlockId rawText =
    let
        trimmed : String
        trimmed =
            String.trimRight rawText
    in
    case lastWord trimmed of
        Just word ->
            if String.startsWith "^" word && isValidBlockId (String.dropLeft 1 word) then
                Just (String.dropLeft 1 word)

            else
                Nothing

        Nothing ->
            Nothing


lastWord : String -> Maybe String
lastWord str =
    str
        |> String.words
        |> List.Extra.last


isValidBlockId : String -> Bool
isValidBlockId str =
    not (String.isEmpty str)
        && String.all isBlockIdChar str


isBlockIdChar : Char -> Bool
isBlockIdChar c =
    Char.isDigit c
        || Char.isLower c
        || Char.isUpper c
        || c == '-'



collectWikilinks : Block b i -> List ( Region, WikilinkData )
collectWikilinks block =
    queryInlines
        (\(Inline { content, region }) ->
            case content of
                Wikilink data ->
                    [ ( region, data ) ]

                _ ->
                    []
        )
        block



-- HELPERS


{-| Apply a function to every block within a block recursively.
-}
walk : (Block b i -> Block b i) -> Block b i -> Block b i
walk function (Block blockRec) =
    let
        walked : Block b i
        walked =
            case blockRec.content of
                BlockQuote blocks ->
                    Block { blockRec | content = BlockQuote (blocks |> List.map (walk function)) }

                List listBlock items ->
                    Block { blockRec | content = List listBlock (items |> List.map (List.map (walk function))) }

                Custom customBlock blocks ->
                    Block { blockRec | content = Custom customBlock (blocks |> List.map (walk function)) }

                _ ->
                    Block blockRec
    in
    function walked


{-| Apply a function to every block's inline recursively.
-}
walkInlines : (Inline i -> Inline i) -> Block b i -> Block b i
walkInlines function block =
    walk (walkInlinesHelp function) block


walkInlinesHelp : (Inline i -> Inline i) -> Block b i -> Block b i
walkInlinesHelp function (Block blockRec) =
    case blockRec.content of
        Paragraph rawText inlines ->
            Block { blockRec | content = Paragraph rawText (inlines |> List.map (InlineParser.walk function)) }

        Heading rawText level inlines ->
            Block { blockRec | content = Heading rawText level (inlines |> List.map (InlineParser.walk function)) }

        PlainInlines inlines ->
            Block { blockRec | content = PlainInlines (inlines |> List.map (InlineParser.walk function)) }

        _ ->
            Block blockRec


{-| Walks a block and applies a function for every block,
appending the results.
-}
query : (Block b i -> List a) -> Block b i -> List a
query function ((Block blockRec) as block) =
    case blockRec.content of
        BlockQuote blocks ->
            blocks
                |> List.concatMap (query function)
                |> (++) (function block)

        List _ items ->
            items
                |> List.concatMap (List.concatMap (query function))
                |> (++) (function block)

        Custom _ blocks ->
            blocks
                |> List.concatMap (query function)
                |> (++) (function block)

        _ ->
            function block


{-| Walks a block and applies a function for every inline,
appending the results.
-}
queryInlines : (Inline i -> List a) -> Block b i -> List a
queryInlines function block =
    query (queryInlinesHelp function) block


queryInlinesHelp : (Inline i -> List a) -> Block b i -> List a
queryInlinesHelp function (Block blockRec) =
    case blockRec.content of
        Paragraph _ inlines ->
            inlines |> List.concatMap (InlineParser.query function)

        Heading _ _ inlines ->
            inlines |> List.concatMap (InlineParser.query function)

        PlainInlines inlines ->
            inlines |> List.concatMap (InlineParser.query function)

        _ ->
            []
