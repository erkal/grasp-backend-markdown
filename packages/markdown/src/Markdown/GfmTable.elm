module Markdown.GfmTable exposing
    ( Alignment(..)
    , GfmTable
    , tryParse
    )

{-| GFM pipe table parsing.
-}


type alias GfmTable =
    { headerColumns : List ( Alignment, String )
    , bodyRows : List (List String)
    }


type Alignment
    = AlignLeft
    | AlignCenter
    | AlignRight
    | AlignDefault


tryParse : String -> Maybe GfmTable
tryParse rawText =
    if not (String.contains "|" rawText) then
        Nothing

    else
        let
            lines : List String
            lines =
                rawText
                    |> String.lines
                    |> List.filter (\l -> String.trim l /= "")
        in
        case lines of
            headerLine :: separatorLine :: bodyLines ->
                separatorLine
                    |> parseSeparator
                    |> Maybe.andThen
                        (\alignments ->
                            let
                                headerCells : List String
                                headerCells =
                                    parseCells headerLine

                                columnCount : Int
                                columnCount =
                                    List.length alignments
                            in
                            if List.length headerCells == columnCount then
                                Just
                                    { headerColumns = List.map2 Tuple.pair alignments headerCells
                                    , bodyRows =
                                        bodyLines
                                            |> List.map (parseCells >> normalizeRowLength columnCount)
                                    }

                            else
                                Nothing
                        )

            _ ->
                Nothing



-- INTERNALS


parseSeparator : String -> Maybe (List Alignment)
parseSeparator line =
    let
        cells : List String
        cells =
            parseCells line
    in
    if not (List.isEmpty cells) && (cells |> List.all isValidSeparatorCell) then
        Just (cells |> List.map parseCellAlignment)

    else
        Nothing


parseCells : String -> List String
parseCells line =
    line
        |> String.trim
        |> stripLeadingTrailingPipes
        |> splitOnUnescapedPipes
        |> List.map String.trim


isValidSeparatorCell : String -> Bool
isValidSeparatorCell cell =
    let
        trimmed : String
        trimmed =
            String.trim cell

        inner : String
        inner =
            trimmed |> stripPrefix ":" |> stripSuffix ":"
    in
    not (String.isEmpty inner)
        && (inner |> String.all (\c -> c == '-'))


parseCellAlignment : String -> Alignment
parseCellAlignment cell =
    let
        trimmed : String
        trimmed =
            String.trim cell
    in
    if String.startsWith ":" trimmed && String.endsWith ":" trimmed then
        AlignCenter

    else if String.endsWith ":" trimmed then
        AlignRight

    else if String.startsWith ":" trimmed then
        AlignLeft

    else
        AlignDefault


stripLeadingTrailingPipes : String -> String
stripLeadingTrailingPipes s =
    s |> stripPrefix "|" |> stripSuffix "|"


stripPrefix : String -> String -> String
stripPrefix prefix str =
    if String.startsWith prefix str then
        String.dropLeft (String.length prefix) str

    else
        str


stripSuffix : String -> String -> String
stripSuffix suffix str =
    if String.endsWith suffix str then
        String.dropRight (String.length suffix) str

    else
        str


splitOnUnescapedPipes : String -> List String
splitOnUnescapedPipes s =
    s
        |> String.toList
        |> splitOnUnescapedPipesHelp [] []
        |> List.reverse


splitOnUnescapedPipesHelp : List String -> List Char -> List Char -> List String
splitOnUnescapedPipesHelp cells currentCell chars =
    case chars of
        [] ->
            (currentCell |> List.reverse |> String.fromList) :: cells

        '\\' :: '|' :: rest ->
            splitOnUnescapedPipesHelp cells ('|' :: currentCell) rest

        '|' :: rest ->
            let
                finishedCell : String
                finishedCell =
                    currentCell |> List.reverse |> String.fromList
            in
            splitOnUnescapedPipesHelp (finishedCell :: cells) [] rest

        c :: rest ->
            splitOnUnescapedPipesHelp cells (c :: currentCell) rest


normalizeRowLength : Int -> List String -> List String
normalizeRowLength targetLength row =
    let
        missing : Int
        missing =
            targetLength - List.length row
    in
    if missing > 0 then
        row ++ List.repeat missing ""

    else
        row |> List.take targetLength
