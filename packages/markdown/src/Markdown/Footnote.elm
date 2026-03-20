module Markdown.Footnote exposing
    ( FootnoteDefinition
    , extract
    )

{-| Footnote extraction from raw markdown text.
-}

import Regex exposing (Regex)


type alias FootnoteDefinition =
    { id : String
    , content : String
    }


{-| Extract footnote definitions from raw markdown,
returning the cleaned text and the list of definitions.
-}
extract : String -> ( String, List FootnoteDefinition )
extract str =
    str
        |> String.lines
        |> List.foldr processLine ( [], [] )
        |> Tuple.mapFirst (String.join "\n")


processLine :
    String
    -> ( List String, List FootnoteDefinition )
    -> ( List String, List FootnoteDefinition )
processLine line ( keptLines, defs ) =
    case Regex.find footnoteDefRegex line of
        [ match ] ->
            case match.submatches of
                (Just fnId) :: (Just content) :: _ ->
                    ( keptLines, { id = fnId, content = content } :: defs )

                _ ->
                    ( line :: keptLines, defs )

        _ ->
            ( line :: keptLines, defs )


footnoteDefRegex : Regex
footnoteDefRegex =
    Regex.fromString "^\\[\\^([^\\]]+)\\]:\\s*(.+)$"
        |> Maybe.withDefault Regex.never
