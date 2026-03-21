module Markdown.Helpers
    exposing
        ( Attribute
        , References
        , cleanWhitespaces
        , formatStr
        , ifError
        , indentLength
        , indentLine
        , insideSquareBracketRegex
        , isEven
        , prepareRefLabel
        , returnFirstJust
        , titleRegex
        , whiteSpaceChars
        )

import Dict exposing (Dict)
import Markdown.Entity as Entity
import Regex exposing (Regex)


type alias References =
    Dict String ( String, Maybe String )



-- Label ( Url, Maybe Title )


type alias Attribute =
    ( String, Maybe String )


insideSquareBracketRegex : String
insideSquareBracketRegex =
    "[^\\[\\]\\\\]*(?:\\\\.[^\\[\\]\\\\]*)*"


titleRegex : String
titleRegex =
    "(?:["
        ++ whiteSpaceChars
        ++ "]+"
        ++ "(?:'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'|"
        ++ "\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\"|"
        ++ "\\(([^\\)\\\\]*(?:\\\\.[^\\)\\\\]*)*)\\)))?"


whiteSpaceChars : String
whiteSpaceChars =
    " \\t\\f\\v\\r\\n"


prepareRefLabel : String -> String
prepareRefLabel =
    cleanWhitespaces
        >> String.toLower


cleanWhitespaces : String -> String
cleanWhitespaces =
    String.trim
        >> Regex.replace whitespacesRegex (\_ -> " ")


whitespacesRegex : Regex
whitespacesRegex =
    Regex.fromString ("[" ++ whiteSpaceChars ++ "]+")
        |> Maybe.withDefault Regex.never


indentLength : String -> Int
indentLength str =
    indentLengthAt 0 0 str


indentLengthAt : Int -> Int -> String -> Int
indentLengthAt pos col str =
    case String.slice pos (pos + 1) str of
        " " ->
            indentLengthAt (pos + 1) (col + 1) str

        "\t" ->
            indentLengthAt (pos + 1) (col + 4) str

        _ ->
            col


indentLine : Int -> String -> String
indentLine n str =
    let
        expanded : String
        expanded =
            if String.contains "\t" str then
                String.replace "\t" "    " str

            else
                str
    in
    stripLeadingSpaces n 0 expanded


stripLeadingSpaces : Int -> Int -> String -> String
stripLeadingSpaces maxStrip pos str =
    if pos < maxStrip && String.slice pos (pos + 1) str == " " then
        stripLeadingSpaces maxStrip (pos + 1) str

    else if pos == 0 then
        str

    else
        String.dropLeft pos str


escapableRegex : Regex
escapableRegex =
    Regex.fromString "(\\\\+)([!\"#$%&\\'()*+,./:;<=>?@[\\\\\\]^_`{|}~-])"
        |> Maybe.withDefault Regex.never


formatStr : String -> String
formatStr str =
    if not (String.contains "\\" str || String.contains "&" str) then
        str

    else
        replaceEscapable str
            |> Entity.replaceEntities
            |> Entity.replaceDecimals
            |> Entity.replaceHexadecimals


replaceEscapable : String -> String
replaceEscapable =
    Regex.replace
        escapableRegex
        (\regexMatch ->
            case regexMatch.submatches of
                (Just backslashes) :: (Just escapedStr) :: _ ->
                    String.repeat
                        (String.length backslashes // 2)
                        "\\"
                        ++ escapedStr

                _ ->
                    regexMatch.match
        )


returnFirstJust : List (Maybe a) -> Maybe a
returnFirstJust maybes =
    let
        process : Maybe a -> Maybe a -> Maybe a
        process a maybeFound =
            case maybeFound of
                Just found ->
                    Just found

                Nothing ->
                    a
    in
    List.foldl process Nothing maybes


ifError : (x -> Result x a) -> Result x a -> Result x a
ifError function result =
    case result of
        Result.Ok _ ->
            result

        Result.Err err ->
            function err


isEven : Int -> Bool
isEven int =
    modBy 2 int == 0
