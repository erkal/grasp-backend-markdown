module Markdown.Split exposing (splitAtBlankLines)


-- API


splitAtBlankLines : String -> List { text : String, startLine : Int }
splitAtBlankLines document =
    document
        |> String.lines
        |> walk initialState
        |> .segments
        |> List.reverse



-- INTERNALS


type alias State =
    { inCodeFence : Bool
    , listIndent : Maybe Int
    , accLines : List String
    , segmentStart : Int
    , lineNum : Int
    , segments : List { text : String, startLine : Int }
    }


initialState : State
initialState =
    { inCodeFence = False
    , listIndent = Nothing
    , accLines = []
    , segmentStart = 1
    , lineNum = 1
    , segments = []
    }


walk : State -> List String -> State
walk state remaining =
    case remaining of
        [] ->
            emit state

        line :: rest ->
            let
                next : State
                next =
                    if state.inCodeFence then
                        { state | inCodeFence = not (isCodeFence line) }
                            |> accumulateLine line

                    else if isCodeFence line then
                        { state | inCodeFence = True }
                            |> accumulateLine line

                    else if isBlankLine line then
                        if isBoundary state.listIndent rest then
                            emit state
                                |> (\s -> { s | listIndent = Nothing })

                        else
                            state
                                |> accumulateLine line

                    else
                        state
                            |> accumulateLine line
                            |> updateListIndent line
            in
            walk { next | lineNum = state.lineNum + 1 } rest


accumulateLine : String -> State -> State
accumulateLine line state =
    { state
        | accLines = line :: state.accLines
        , segmentStart =
            if List.isEmpty state.accLines then
                state.lineNum

            else
                state.segmentStart
    }


updateListIndent : String -> State -> State
updateListIndent line state =
    case listMarker line of
        Just indent ->
            { state | listIndent = Just indent }

        Nothing ->
            state


emit : State -> State
emit state =
    if List.isEmpty state.accLines then
        state

    else
        { state
            | segments =
                { text =
                    state.accLines
                        |> List.reverse
                        |> String.join "\n"
                , startLine = state.segmentStart
                }
                    :: state.segments
            , accLines = []
        }



-- LINE CLASSIFICATION


isBlankLine : String -> Bool
isBlankLine line =
    String.trim line == ""


isCodeFence : String -> Bool
isCodeFence line =
    let
        trimmed : String
        trimmed =
            String.trimLeft line

        leadingSpaces : Int
        leadingSpaces =
            String.length line - String.length trimmed
    in
    leadingSpaces
        <= 3
        && (String.startsWith "```" trimmed
                || String.startsWith "~~~" trimmed
           )


listMarker : String -> Maybe Int
listMarker line =
    let
        spaces : Int
        spaces =
            String.length line - String.length (String.trimLeft line)

        rest : String
        rest =
            String.trimLeft line
    in
    if
        String.startsWith "- " rest
            || String.startsWith "* " rest
            || String.startsWith "+ " rest
    then
        Just (spaces + 2)

    else
        orderedListMarker spaces (String.toList rest)


orderedListMarker : Int -> List Char -> Maybe Int
orderedListMarker leadingSpaces chars =
    let
        digitCount : Int
        digitCount =
            countLeadingDigits chars
    in
    if digitCount > 0 then
        case List.drop digitCount chars of
            '.' :: ' ' :: _ ->
                Just (leadingSpaces + digitCount + 2)

            _ ->
                Nothing

    else
        Nothing


countLeadingDigits : List Char -> Int
countLeadingDigits chars =
    case chars of
        c :: rest ->
            if Char.isDigit c then
                1 + countLeadingDigits rest

            else
                0

        [] ->
            0



-- BOUNDARY DETECTION


isBoundary : Maybe Int -> List String -> Bool
isBoundary listIndent rest =
    case listIndent of
        Nothing ->
            True

        Just indent ->
            case nextNonBlankLine rest of
                Nothing ->
                    True

                Just nextLine ->
                    (listMarker nextLine == Nothing)
                        && (indentLevel nextLine < indent)
                        && not (String.startsWith ">" (String.trimLeft nextLine))


nextNonBlankLine : List String -> Maybe String
nextNonBlankLine lines =
    case lines of
        [] ->
            Nothing

        line :: rest ->
            if isBlankLine line then
                nextNonBlankLine rest

            else
                Just line


indentLevel : String -> Int
indentLevel line =
    String.length line - String.length (String.trimLeft line)
