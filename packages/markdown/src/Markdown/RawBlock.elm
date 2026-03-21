module Markdown.RawBlock
    exposing
        ( RawBlock(..)
        , CodeBlock(..)
        , Fence
        , ListBlock
        , ListType(..)
        , joinCodeLines
        , joinParagraphLines
        , parse
        , parseBlockStructure
        )

{-| Internal block parsing.
Markdown.Block wraps the result with Region metadata.


# Model

@docs RawBlock, CodeBlock, Fence, ListBlock, ListType


# Parsing

@docs parse

-}

import Dict
import Markdown.Config exposing (Options)
import Markdown.Helpers exposing (References, formatStr, ifError, indentLength, indentLine, insideSquareBracketRegex, prepareRefLabel, returnFirstJust, titleRegex)
import Markdown.Inline exposing (Inline)
import Regex exposing (Regex)


-- Model


{-| The block type.

Paragraph and CodeBlock store lines in reverse order during block
building (newest line first). Use joinParagraphLines / joinCodeLines
to get the final text.

-}
type RawBlock b i
    = BlankLine String
    | ThematicBreak
    | Heading String Int (List (Inline i))
    | CodeBlock CodeBlock (List String) -- reversed lines (no trailing \n)
    | Paragraph (List String) (List (Inline i)) -- reversed lines
    | BlockQuote (List (RawBlock b i))
    | List ListBlock (List (List (RawBlock b i)))
    | PlainInlines (List (Inline i))
    | Custom b (List (RawBlock b i))


joinParagraphLines : List String -> String
joinParagraphLines lines =
    List.reverse lines |> String.join "\n"


splitParagraphLines : String -> List String
splitParagraphLines text =
    String.lines text |> List.reverse


joinCodeLines : List String -> String
joinCodeLines codeLines =
    if List.isEmpty codeLines then
        ""

    else
        (List.reverse codeLines |> String.join "\n") ++ "\n"


{-| CodeBlock type.

  - **Indented**
  - **Fenced** | _Is fence open?_ | _Fence_

-}
type CodeBlock
    = Indented
    | Fenced Bool Fence -- isOpen Fence


{-| Code fence model.
-}
type alias Fence =
    { indentLength : Int
    , fenceLength : Int
    , fenceChar : String
    , language : Maybe String
    }


{-| List model.
-}
type alias ListBlock =
    { type_ : ListType
    , indentLength : Int
    , delimiter : String
    , isLoose : Bool
    }


{-| Types of list.

  - **Unordered**
  - **Ordered** | _Start_

-}
type ListType
    = Unordered
    | Ordered Int



-- Parser


{-| Turn a markdown string into a list of raw blocks.
Inline elements within blocks are wrapped in `Inline` records with
placeholder regions.

If `Maybe Options` is `Nothing`, `Config.defaultOptions` will be used.

-}
parse : Maybe Options -> String -> List (RawBlock b i)
parse _ str =
    parseBlockStructure str |> Tuple.second


parseBlockStructure : String -> ( References, List (RawBlock b i) )
parseBlockStructure =
    String.lines
        >> (\a -> incorporateLines a [])
        >> parseReferences Dict.empty


incorporateLines : List String -> List (RawBlock b i) -> List (RawBlock b i)
incorporateLines rawLines ast =
    case rawLines of
        [] ->
            ast

        rawLine :: rawLinesTail ->
            -- To get tail call optimization, use parentheses, not |> or <|.
            -- Technically |> and <| are function calls.
            -- If you use them, they will be in tail position, not the recursive call!
            incorporateLines rawLinesTail
                (incorporateLine rawLine ast)


incorporateLine : String -> List (RawBlock b i) -> List (RawBlock b i)
incorporateLine rawLine ast =
    case ast of
        -- No need to typify the line if Fenced Code
        -- is open, just check for closing fence.
        (CodeBlock (Fenced True fence) codeLines) :: astTail ->
            continueOrCloseCodeFence fence codeLines rawLine
                |> (\a -> (::) a astTail)

        (List model items) :: astTail ->
            if indentLength rawLine >= model.indentLength then
                parseIndentedListLine rawLine model items ast astTail
            else
                -- After a list, check for lists before
                -- indented code.
                -- When both a thematic break and a list item are
                -- possible interpretations of a line, the
                -- thematic break takes precedence.
                checkThematicBreakLine ( rawLine, ast )
                    |> ifError checkListLine
                    |> ifError checkBlankLine
                    |> ifError checkIndentedCode
                    |> ifError checkOpenCodeFenceLine
                    |> ifError checkSetextHeadingLine
                    |> ifError checkATXHeadingLine
                    |> ifError checkBlockQuote
                    |> Result.withDefault (parseTextLine rawLine ast)

        _ ->
            parseRawLine rawLine ast



-- Default parsing precedence


parseRawLine : String -> List (RawBlock b i) -> List (RawBlock b i)
parseRawLine rawLine ast =
    if startsWithAlpha rawLine then
        -- No block syntax starts with a letter. Skip all regex checks.
        parseTextLine rawLine ast

    else
        checkBlankLine ( rawLine, ast )
            |> ifError checkIndentedCode
            |> ifError checkOpenCodeFenceLine
            |> ifError checkSetextHeadingLine
            |> ifError checkATXHeadingLine
            |> ifError checkBlockQuote
            |> ifError checkThematicBreakLine
            |> ifError checkListLine
            |> Result.withDefault (parseTextLine rawLine ast)


startsWithAlpha : String -> Bool
startsWithAlpha str =
    case String.uncons str of
        Just ( c, _ ) ->
            Char.isAlpha c

        Nothing ->
            False



-- BlankLine


checkBlankLine : ( String, List (RawBlock b i) ) -> Result ( String, List (RawBlock b i) ) (List (RawBlock b i))
checkBlankLine ( rawLine, ast ) =
    if String.isEmpty (String.trim rawLine) then
        Result.Ok (parseBlankLine ast rawLine)

    else
        Result.Err ( rawLine, ast )


isBlankLine : String -> Bool
isBlankLine str =
    String.isEmpty (String.trim str)


parseBlankLine : List (RawBlock b i) -> String -> List (RawBlock b i)
parseBlankLine ast blankStr =
    case ast of
        (CodeBlock (Fenced True fence) codeLines) :: astTail ->
            CodeBlock (Fenced True fence) ("" :: codeLines)
                |> (\a -> (::) a astTail)

        (List model items) :: astTail ->
            List model (addBlankLineToListBlock blankStr items)
                :: astTail

        _ ->
            BlankLine blankStr :: ast


addBlankLineToListBlock : String -> List (List (RawBlock b i)) -> List (List (RawBlock b i))
addBlankLineToListBlock blankStr asts =
    case asts of
        [] ->
            [ [ BlankLine blankStr ] ]

        ast :: astsTail ->
            parseBlankLine ast blankStr
                :: astsTail



-- ATX Heading


checkATXHeadingLine : ( String, List (RawBlock b i) ) -> Result ( String, List (RawBlock b i) ) (List (RawBlock b i))
checkATXHeadingLine ( rawLine, ast ) =
    Regex.findAtMost 1 atxHeadingLineRegex rawLine
        |> List.head
        |> Maybe.andThen extractATXHeadingRM
        |> Maybe.map (\a -> (::) a ast)
        |> Result.fromMaybe ( rawLine, ast )


atxHeadingLineRegex : Regex
atxHeadingLineRegex =
    Regex.fromString
        ("^ {0,3}(#{1,6})"
            ++ "(?:[ \\t]+[ \\t#]+$|[ \\t]+|$)"
            ++ "(.*?)(?:\\s+[ \\t#]*)?$"
        )
        |> Maybe.withDefault Regex.never


extractATXHeadingRM : Regex.Match -> Maybe (RawBlock b i)
extractATXHeadingRM match =
    case match.submatches of
        (Just lvl) :: maybeHeading :: _ ->
            Heading (Maybe.withDefault "" maybeHeading) (String.length lvl) []
                |> Just

        _ ->
            Nothing



-- Setext Heading


checkSetextHeadingLine : ( String, List (RawBlock b i) ) -> Result ( String, List (RawBlock b i) ) (List (RawBlock b i))
checkSetextHeadingLine ( rawLine, ast ) =
    Regex.findAtMost 1 setextHeadingLineRegex rawLine
        |> List.head
        |> Maybe.andThen extractSetextHeadingRM
        |> Maybe.andThen (parseSetextHeadingLine rawLine ast)
        |> Result.fromMaybe ( rawLine, ast )


setextHeadingLineRegex : Regex
setextHeadingLineRegex =
    Regex.fromString "^ {0,3}(=+|-+)[ \\t]*$"
        |> Maybe.withDefault Regex.never


extractSetextHeadingRM : Regex.Match -> Maybe ( Int, String )
extractSetextHeadingRM match =
    case match.submatches of
        (Just delimiter) :: _ ->
            if String.startsWith "=" delimiter then
                Just ( 1, delimiter )
            else
                Just ( 2, delimiter )

        _ ->
            Nothing


parseSetextHeadingLine : String -> List (RawBlock b i) -> ( Int, String ) -> Maybe (List (RawBlock b i))
parseSetextHeadingLine rawLine ast ( lvl, delimiter ) =
    case ast of
        -- Only occurs after a paragraph
        (Paragraph lines _) :: astTail ->
            Heading (joinParagraphLines lines) lvl []
                :: astTail
                |> Just

        _ ->
            Nothing



-- Thematic Break


checkThematicBreakLine : ( String, List (RawBlock b i) ) -> Result ( String, List (RawBlock b i) ) (List (RawBlock b i))
checkThematicBreakLine ( rawLine, ast ) =
    Regex.findAtMost 1 thematicBreakLineRegex rawLine
        |> List.head
        |> Maybe.map (\_ -> ThematicBreak :: ast)
        |> Result.fromMaybe ( rawLine, ast )


thematicBreakLineRegex : Regex
thematicBreakLineRegex =
    Regex.fromString
        ("^ {0,3}(?:"
            ++ "(?:\\*[ \\t]*){3,}"
            ++ "|(?:_[ \\t]*){3,}"
            ++ "|(?:-[ \\t]*){3,})[ \\t]*$"
        )
        |> Maybe.withDefault Regex.never



-- Block Quote


checkBlockQuote : ( String, List (RawBlock b i) ) -> Result ( String, List (RawBlock b i) ) (List (RawBlock b i))
checkBlockQuote ( rawLine, ast ) =
    Regex.findAtMost 1 blockQuoteLineRegex rawLine
        |> List.head
        |> Maybe.map
            (.submatches
                >> List.head
                >> Maybe.withDefault Nothing
                >> Maybe.withDefault ""
            )
        |> Maybe.map (parseBlockQuoteLine ast)
        |> Result.fromMaybe ( rawLine, ast )


blockQuoteLineRegex : Regex
blockQuoteLineRegex =
    Regex.fromString "^ {0,3}(?:>[ ]?)(.*)$"
        |> Maybe.withDefault Regex.never


parseBlockQuoteLine : List (RawBlock b i) -> String -> List (RawBlock b i)
parseBlockQuoteLine ast rawLine =
    case ast of
        (BlockQuote bqAST) :: astTail ->
            incorporateLine rawLine bqAST
                |> BlockQuote
                |> (\a -> (::) a astTail)

        _ ->
            incorporateLine rawLine []
                |> BlockQuote
                |> (\a -> (::) a ast)



-- Indented Code


checkIndentedCode : ( String, List (RawBlock b i) ) -> Result ( String, List (RawBlock b i) ) (List (RawBlock b i))
checkIndentedCode ( rawLine, ast ) =
    Regex.findAtMost 1 indentedCodeLineRegex rawLine
        |> List.head
        |> Maybe.map (.submatches >> List.head)
        |> Maybe.withDefault Nothing
        |> Maybe.withDefault Nothing
        |> Maybe.map (parseIndentedCodeLine ast)
        |> Result.fromMaybe ( rawLine, ast )


indentedCodeLineRegex : Regex
indentedCodeLineRegex =
    Regex.fromString "^(?: {4,4}| {0,3}\\t)(.*)$"
        |> Maybe.withDefault Regex.never


parseIndentedCodeLine : List (RawBlock b i) -> String -> List (RawBlock b i)
parseIndentedCodeLine ast codeLine =
    case ast of
        -- Continue indented code block
        (CodeBlock Indented codeLines) :: astTail ->
            CodeBlock Indented (codeLine :: codeLines)
                |> (\a -> (::) a astTail)

        -- Possible blankline inside a indented code block
        (BlankLine blankStr) :: astTail ->
            [ blankStr ]
                |> blocksAfterBlankLines astTail
                |> resumeIndentedCodeBlock codeLine
                |> Maybe.withDefault
                    (CodeBlock Indented [ codeLine ]
                        |> (\a -> (::) a ast)
                    )

        -- Continue paragraph or New indented code block
        _ ->
            maybeContinueParagraph codeLine ast
                |> Maybe.withDefault
                    (CodeBlock Indented [ codeLine ]
                        |> (\a -> (::) a ast)
                    )



-- Return the blocks after blanklines
-- and the blanklines content in between


blocksAfterBlankLines : List (RawBlock b i) -> List String -> ( List (RawBlock b i), List String )
blocksAfterBlankLines ast blankLines =
    case ast of
        (BlankLine blankStr) :: astTail ->
            blocksAfterBlankLines astTail
                (blankStr :: blankLines)

        _ ->
            ( ast, blankLines )


resumeIndentedCodeBlock : String -> ( List (RawBlock b i), List String ) -> Maybe (List (RawBlock b i))
resumeIndentedCodeBlock codeLine ( remainBlocks, blankLines ) =
    case remainBlocks of
        (CodeBlock Indented codeLines) :: remainBlocksTail ->
            let
                -- blankLines arrives oldest-first from blocksAfterBlankLines; reverse for our reversed-list representation
                blankCodeLines : List String
                blankCodeLines =
                    blankLines
                        |> List.map (\bl -> indentLine 4 bl)
                        |> List.reverse
            in
            CodeBlock Indented (codeLine :: blankCodeLines ++ codeLines)
                |> (\a -> (::) a remainBlocksTail)
                |> Just

        _ ->
            Nothing



-- Fenced Code


checkOpenCodeFenceLine : ( String, List (RawBlock b i) ) -> Result ( String, List (RawBlock b i) ) (List (RawBlock b i))
checkOpenCodeFenceLine ( rawLine, ast ) =
    Regex.findAtMost 1 openCodeFenceLineRegex rawLine
        |> List.head
        |> Maybe.andThen extractOpenCodeFenceRM
        |> Maybe.map (\f -> CodeBlock f [])
        |> Maybe.map (\a -> (::) a ast)
        |> Result.fromMaybe ( rawLine, ast )


openCodeFenceLineRegex : Regex
openCodeFenceLineRegex =
    Regex.fromString "^( {0,3})(`{3,}(?!.*`)|~{3,}(?!.*~))(.*)$"
        |> Maybe.withDefault Regex.never


extractOpenCodeFenceRM : Regex.Match -> Maybe CodeBlock
extractOpenCodeFenceRM match =
    case match.submatches of
        maybeIndent :: (Just fence) :: maybeLanguage :: _ ->
            Fenced True
                { indentLength =
                    Maybe.map String.length maybeIndent
                        |> Maybe.withDefault 0
                , fenceLength = String.length fence
                , fenceChar = String.left 1 fence
                , language =
                    Maybe.map String.words maybeLanguage
                        |> Maybe.withDefault []
                        |> List.head
                        |> Maybe.andThen
                            (\lang ->
                                if lang == "" then
                                    Nothing
                                else
                                    Just lang
                            )
                        |> Maybe.map formatStr
                }
                |> Just

        _ ->
            Nothing


continueOrCloseCodeFence : Fence -> List String -> String -> RawBlock b i
continueOrCloseCodeFence fence previousCodeLines rawLine =
    if isCloseFenceLine fence rawLine then
        CodeBlock (Fenced False fence) previousCodeLines

    else
        CodeBlock (Fenced True fence) (indentLine fence.indentLength rawLine :: previousCodeLines)


isCloseFenceLine : Fence -> String -> Bool
isCloseFenceLine fence =
    Regex.findAtMost 1 closeCodeFenceLineRegex
        >> List.head
        >> Maybe.map (isCloseFenceLineHelp fence)
        >> Maybe.withDefault False


closeCodeFenceLineRegex : Regex
closeCodeFenceLineRegex =
    Regex.fromString "^ {0,3}(`{3,}|~{3,})\\s*$"
        |> Maybe.withDefault Regex.never


isCloseFenceLineHelp : Fence -> Regex.Match -> Bool
isCloseFenceLineHelp fence match =
    case match.submatches of
        (Just fenceStr) :: _ ->
            String.length fenceStr
                >= fence.fenceLength
                && String.left 1 fenceStr
                == fence.fenceChar

        _ ->
            False



-- List


parseIndentedListLine : String -> ListBlock -> List (List (RawBlock b i)) -> List (RawBlock b i) -> List (RawBlock b i) -> List (RawBlock b i)
parseIndentedListLine rawLine model items ast astTail =
    case items of
        [] ->
            indentLine model.indentLength rawLine
                |> (\a -> incorporateLine a [])
                |> (\a -> (::) a [])
                |> List model
                |> (\a -> (::) a astTail)

        item :: itemsTail ->
            let
                indentedRawLine : String
                indentedRawLine =
                    indentLine model.indentLength rawLine

                updateList : ListBlock -> List (RawBlock b i)
                updateList model_ =
                    incorporateLine indentedRawLine item
                        |> (\a -> (::) a itemsTail)
                        |> List model_
                        |> (\a -> (::) a astTail)
            in
            case item of
                -- A list item can begin with at most
                -- one blank line without begin loose.
                (BlankLine _) :: [] ->
                    updateList model

                (BlankLine _) :: itemTail ->
                    if
                        List.all
                            (\block ->
                                case block of
                                    BlankLine _ ->
                                        True

                                    _ ->
                                        False
                            )
                            itemTail
                    then
                        parseRawLine rawLine ast
                    else
                        updateList { model | isLoose = True }

                (List model_ items_) :: itemTail ->
                    if
                        indentLength indentedRawLine
                            >= model_.indentLength
                    then
                        updateList model
                    else if isBlankLineLast items_ then
                        updateList { model | isLoose = True }
                    else
                        updateList model

                _ ->
                    updateList model


checkListLine : ( String, List (RawBlock b i) ) -> Result ( String, List (RawBlock b i) ) (List (RawBlock b i))
checkListLine ( rawLine, ast ) =
    checkOrderedListLine rawLine
        |> ifError checkUnorderedListLine
        |> Result.map calcListIndentLength
        |> Result.map (parseListLine rawLine ast)
        |> Result.mapError (\e -> ( e, ast ))



-- Ordered list


checkOrderedListLine : String -> Result String ( ListBlock, String, String )
checkOrderedListLine rawLine =
    Regex.findAtMost 1 orderedListLineRegex rawLine
        |> List.head
        |> Maybe.andThen extractOrderedListRM
        |> Result.fromMaybe rawLine


orderedListLineRegex : Regex
orderedListLineRegex =
    Regex.fromString "^( *(\\d{1,9})([.)])( {0,4}))(?:[ \\t](.*))?$"
        |> Maybe.withDefault Regex.never


extractOrderedListRM : Regex.Match -> Maybe ( ListBlock, String, String )
extractOrderedListRM match =
    case match.submatches of
        (Just indentString) :: (Just start) :: (Just delimiter) :: maybeIndentSpace :: maybeRawLine :: _ ->
            ( { type_ =
                    String.toInt start
                        |> Maybe.map Ordered
                        |> Maybe.withDefault Unordered
              , indentLength = String.length indentString + 1
              , delimiter = delimiter
              , isLoose = False
              }
            , Maybe.withDefault "" maybeIndentSpace
            , Maybe.withDefault "" maybeRawLine
            )
                |> Just

        _ ->
            Nothing



-- Unordered list


checkUnorderedListLine : String -> Result String ( ListBlock, String, String )
checkUnorderedListLine rawLine =
    Regex.findAtMost 1 unorderedListLineRegex rawLine
        |> List.head
        |> Maybe.andThen extractUnorderedListRM
        |> Result.fromMaybe rawLine


unorderedListLineRegex : Regex
unorderedListLineRegex =
    Regex.fromString "^( *([\\*\\-\\+])( {0,4}))(?:[ \\t](.*))?$"
        |> Maybe.withDefault Regex.never


extractUnorderedListRM : Regex.Match -> Maybe ( ListBlock, String, String )
extractUnorderedListRM match =
    case match.submatches of
        (Just indentString) :: (Just delimiter) :: maybeIndentSpace :: maybeRawLine :: [] ->
            ( { type_ = Unordered
              , indentLength = String.length indentString + 1
              , delimiter = delimiter
              , isLoose = False
              }
            , Maybe.withDefault "" maybeIndentSpace
            , Maybe.withDefault "" maybeRawLine
            )
                |> Just

        _ ->
            Nothing


calcListIndentLength : ( ListBlock, String, String ) -> ( ListBlock, String )
calcListIndentLength ( listBlock, indentSpace, rawLine ) =
    let
        indentSpaceLength : Int
        indentSpaceLength =
            String.length indentSpace

        isIndentedCode : Bool
        isIndentedCode =
            indentSpaceLength >= 4

        indentLength : Int
        indentLength =
            if
                isIndentedCode
                    || isBlankLine rawLine
            then
                listBlock.indentLength - indentSpaceLength
            else
                listBlock.indentLength

        updtRawLine : String
        updtRawLine =
            if isIndentedCode then
                indentSpace ++ rawLine
            else
                rawLine
    in
    ( { listBlock | indentLength = indentLength }
    , updtRawLine
    )


parseListLine : String -> List (RawBlock b i) -> ( ListBlock, String ) -> List (RawBlock b i)
parseListLine rawLine ast ( listBlock, listRawLine ) =
    let
        parsedRawLine : List (RawBlock b i)
        parsedRawLine =
            incorporateLine listRawLine []

        newList : List (RawBlock b i)
        newList =
            List listBlock [ parsedRawLine ] :: ast
    in
    case ast of
        (List model items) :: astTail ->
            if listBlock.delimiter == model.delimiter then
                parsedRawLine
                    :: items
                    |> List
                        { model
                            | indentLength =
                                listBlock.indentLength
                            , isLoose =
                                model.isLoose
                                    || isBlankLineLast items
                        }
                    |> (\a -> (::) a astTail)
            else
                newList

        (Paragraph lines inlines) :: astTail ->
            case parsedRawLine of
                (BlankLine _) :: [] ->
                    -- Empty list item cannot interrupt a paragraph.
                    addToParagraph lines rawLine
                        :: astTail

                _ ->
                    case listBlock.type_ of
                        -- Ordered list with start 1 can interrupt.
                        Ordered 1 ->
                            newList

                        Ordered int ->
                            addToParagraph lines rawLine
                                :: astTail

                        _ ->
                            newList

        _ ->
            newList


isBlankLineLast : List (List (RawBlock b i)) -> Bool
isBlankLineLast items =
    case items of
        [] ->
            False

        item :: itemsTail ->
            case item of
                -- Ignore if it's an empty list item (example 242)
                (BlankLine _) :: [] ->
                    False

                (BlankLine _) :: _ ->
                    True

                (List _ items_) :: _ ->
                    isBlankLineLast items_

                _ ->
                    False



-- Paragraph


parseTextLine : String -> List (RawBlock b i) -> List (RawBlock b i)
parseTextLine rawLine ast =
    maybeContinueParagraph rawLine ast
        |> Maybe.withDefault
            (Paragraph [ formatParagraphLine rawLine ] [] :: ast)


addToParagraph : List String -> String -> RawBlock b i
addToParagraph paragraphLines rawLine =
    Paragraph
        (formatParagraphLine rawLine :: paragraphLines)
        []


formatParagraphLine : String -> String
formatParagraphLine rawParagraph =
    if String.right 2 rawParagraph == "  " then
        String.trim rawParagraph ++ "  "
    else
        String.trim rawParagraph


maybeContinueParagraph : String -> List (RawBlock b i) -> Maybe (List (RawBlock b i))
maybeContinueParagraph rawLine ast =
    case ast of
        (Paragraph paragraphLines _) :: astTail ->
            addToParagraph paragraphLines rawLine
                :: astTail
                |> Just

        (BlockQuote bqAST) :: astTail ->
            maybeContinueParagraph rawLine bqAST
                |> Maybe.map
                    (\updtBqAST ->
                        BlockQuote updtBqAST :: astTail
                    )

        (List model items) :: astTail ->
            case items of
                itemAST :: itemASTTail ->
                    maybeContinueParagraph rawLine itemAST
                        |> Maybe.map
                            ((\a -> (::) a itemASTTail)
                                >> List model
                                >> (\a -> (::) a astTail)
                            )

                _ ->
                    Nothing

        _ ->
            Nothing



-- References


type alias LinkMatch =
    { matchLength : Int
    , inside : String
    , url : String
    , maybeTitle : Maybe String
    }


parseReferences : References -> List (RawBlock b i) -> ( References, List (RawBlock b i) )
parseReferences refs =
    List.foldl parseReferencesHelp ( refs, [] )


parseReferencesHelp : RawBlock b i -> ( References, List (RawBlock b i) ) -> ( References, List (RawBlock b i) )
parseReferencesHelp block ( refs, parsedAST ) =
    case block of
        Paragraph lines _ ->
            let
                rawText =
                    joinParagraphLines lines

                ( paragraphRefs, maybeUpdtText ) =
                    parseReference Dict.empty rawText

                updtRefs =
                    Dict.union paragraphRefs refs
            in
            case maybeUpdtText of
                Just updtText ->
                    ( updtRefs
                    , Paragraph (splitParagraphLines updtText) []
                        :: parsedAST
                    )

                Nothing ->
                    ( updtRefs, parsedAST )

        List model items ->
            let
                ( updtRefs, updtItems ) =
                    List.foldl
                        (\item ( refs__, parsedItems ) ->
                            parseReferences refs__ item
                                |> Tuple.mapSecond
                                    (\a -> (::) a parsedItems)
                        )
                        ( refs, [] )
                        items
            in
            ( updtRefs
            , List model updtItems
                :: parsedAST
            )

        BlockQuote blocks ->
            parseReferences refs blocks
                |> Tuple.mapSecond BlockQuote
                |> Tuple.mapSecond (\a -> (::) a parsedAST)

        Custom customBlock blocks ->
            parseReferences refs blocks
                |> Tuple.mapSecond (Custom customBlock)
                |> Tuple.mapSecond (\a -> (::) a parsedAST)

        _ ->
            ( refs, block :: parsedAST )


parseReference : References -> String -> ( References, Maybe String )
parseReference refs rawText =
    case maybeLinkMatch rawText of
        Just linkMatch ->
            let
                maybeStrippedText =
                    dropRefString rawText linkMatch

                updtRefs =
                    insertLinkMatch refs linkMatch
            in
            case maybeStrippedText of
                Just strippedText ->
                    parseReference updtRefs strippedText

                Nothing ->
                    ( updtRefs, Nothing )

        Nothing ->
            ( refs, Just rawText )


extractUrlTitleRegex : Regex.Match -> Maybe LinkMatch
extractUrlTitleRegex regexMatch =
    case regexMatch.submatches of
        (Just rawText) :: maybeRawUrlAngleBrackets :: maybeRawUrlWithoutBrackets :: maybeTitleSingleQuotes :: maybeTitleDoubleQuotes :: maybeTitleParenthesis :: _ ->
            let
                maybeRawUrl : Maybe String
                maybeRawUrl =
                    returnFirstJust
                        [ maybeRawUrlAngleBrackets
                        , maybeRawUrlWithoutBrackets
                        ]

                toReturn : String -> LinkMatch
                toReturn rawUrl =
                    { matchLength = String.length regexMatch.match
                    , inside = rawText
                    , url = rawUrl
                    , maybeTitle =
                        returnFirstJust
                            [ maybeTitleSingleQuotes
                            , maybeTitleDoubleQuotes
                            , maybeTitleParenthesis
                            ]
                    }
            in
            maybeRawUrl
                |> Maybe.map toReturn

        _ ->
            Nothing


hrefRegex : String
hrefRegex =
    "\\s*(?:<([^<>\\s]*)>|([^\\s]*))"


refRegex : Regex
refRegex =
    Regex.fromString
        ("^\\s*\\[("
            ++ insideSquareBracketRegex
            ++ ")\\]:"
            ++ hrefRegex
            ++ titleRegex
            ++ "\\s*(?![^\\n])"
        )
        |> Maybe.withDefault Regex.never


insertLinkMatch : References -> LinkMatch -> References
insertLinkMatch refs linkMatch =
    if Dict.member linkMatch.inside refs then
        refs
    else
        Dict.insert
            linkMatch.inside
            ( linkMatch.url, linkMatch.maybeTitle )
            refs


dropRefString : String -> LinkMatch -> Maybe String
dropRefString rawText inlineMatch =
    let
        strippedText =
            String.dropLeft inlineMatch.matchLength rawText
    in
    if isBlankLine strippedText then
        Nothing
    else
        Just strippedText


maybeLinkMatch : String -> Maybe LinkMatch
maybeLinkMatch rawText =
    Regex.findAtMost 1 refRegex rawText
        |> List.head
        |> Maybe.andThen extractUrlTitleRegex
        |> Maybe.map
            (\linkMatch ->
                { linkMatch
                    | inside =
                        prepareRefLabel linkMatch.inside
                }
            )
        |> Maybe.andThen
            (\linkMatch ->
                if linkMatch.url == "" || linkMatch.inside == "" then
                    Nothing
                else
                    Just linkMatch
            )



-- Parse Inlines





