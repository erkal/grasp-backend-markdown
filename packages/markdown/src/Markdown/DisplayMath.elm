module Markdown.DisplayMath exposing (tryParse)

{-| Display math block detection.

Detects paragraphs whose entire content is wrapped in `$$...$$`
and extracts the TeX source.
-}


tryParse : String -> Maybe String
tryParse rawText =
    let
        trimmed : String
        trimmed =
            String.trim rawText
    in
    if String.startsWith "$$" trimmed && String.endsWith "$$" trimmed && String.length trimmed > 4 then
        let
            content : String
            content =
                trimmed |> String.dropLeft 2 |> String.dropRight 2 |> String.trim
        in
        if String.isEmpty content then
            Nothing

        else
            Just content

    else
        Nothing
