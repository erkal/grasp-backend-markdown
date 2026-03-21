module Markdown.InlineExtensions exposing
    ( TextSegment(..)
    , hasExtendedSyntax
    , parse
    )

{-| Extended inline text parsing for GFM-style extensions.

Handles strikethrough, highlights, auto-linked URLs, emails,
emoji shortcodes, footnote references, and inline math.

-}

import Dict
import Markdown.EmojiDict exposing (emojiDict)
import Regex exposing (Regex)


type TextSegment
    = PlainText String
    | StrikethroughText String
    | AutoLinkedUrl String
    | AutoLinkedEmail String
    | HighlightText String
    | Emoji String
    | FootnoteRef String
    | InlineMathText String



-- PARSING


parse : String -> List TextSegment
parse str =
    [ PlainText str ]
        |> expandSegment displayMathRegex InlineMathText
        |> expandSegment inlineMathRegex InlineMathText
        |> expandSegment strikethroughRegex StrikethroughText
        |> expandSegment highlightRegex HighlightText
        |> expandSegment autoLinkRegex AutoLinkedUrl
        |> expandSegment emailRegex AutoLinkedEmail
        |> expandSegment emojiRegex resolveEmoji
        |> expandSegment footnoteRefRegex FootnoteRef



-- REGEXES


strikethroughRegex : Regex
strikethroughRegex =
    Regex.fromString "~~(.+?)~~"
        |> Maybe.withDefault Regex.never


autoLinkRegex : Regex
autoLinkRegex =
    Regex.fromString "https?://[^\\s<>]*[^\\s<>.,;:!?\\)\\]\"']"
        |> Maybe.withDefault Regex.never


emailRegex : Regex
emailRegex =
    Regex.fromString "[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}"
        |> Maybe.withDefault Regex.never


highlightRegex : Regex
highlightRegex =
    Regex.fromString "==(.+?)=="
        |> Maybe.withDefault Regex.never


emojiRegex : Regex
emojiRegex =
    Regex.fromString ":([a-z0-9_+\\-]+):"
        |> Maybe.withDefault Regex.never


footnoteRefRegex : Regex
footnoteRefRegex =
    Regex.fromString "\\[\\^([^\\]]+)\\]"
        |> Maybe.withDefault Regex.never


{- Matches $$...$$ within inline text. Runs before inlineMathRegex to prevent
   $$x$$ from being split into two single-$ matches. Produces InlineMathText
   (not display math) because display-mode rendering is handled at block level
   by DisplayMath.tryParse.
-}
displayMathRegex : Regex
displayMathRegex =
    Regex.fromString "\\$\\$(.+?)\\$\\$"
        |> Maybe.withDefault Regex.never


inlineMathRegex : Regex
inlineMathRegex =
    Regex.fromString "\\$([^\\$\\s][^\\$]*?[^\\$\\s]|[^\\$\\s])\\$"
        |> Maybe.withDefault Regex.never



-- HELPERS


type SplitPart
    = MatchedText String
    | UnmatchedText String


resolveEmoji : String -> TextSegment
resolveEmoji code =
    case Dict.get code emojiDict of
        Just unicode ->
            Emoji unicode

        Nothing ->
            PlainText (":" ++ code ++ ":")


expandSegment : Regex -> (String -> TextSegment) -> List TextSegment -> List TextSegment
expandSegment regex toSegment segments =
    segments
        |> List.concatMap
            (\segment ->
                case segment of
                    PlainText str ->
                        splitByRegex regex str
                            |> List.map
                                (\part ->
                                    case part of
                                        MatchedText inner ->
                                            toSegment inner

                                        UnmatchedText t ->
                                            PlainText t
                                )

                    other ->
                        [ other ]
            )


splitByRegex : Regex -> String -> List SplitPart
splitByRegex regex str =
    let
        buildParts : Int -> List Regex.Match -> List SplitPart
        buildParts pos matches =
            case matches of
                [] ->
                    let
                        remaining : String
                        remaining =
                            String.dropLeft pos str
                    in
                    if String.isEmpty remaining then
                        []

                    else
                        [ UnmatchedText remaining ]

                m :: rest ->
                    let
                        before : String
                        before =
                            String.slice pos m.index str

                        inner : String
                        inner =
                            m.submatches
                                |> List.head
                                |> Maybe.andThen identity
                                |> Maybe.withDefault m.match
                    in
                    (if String.isEmpty before then
                        []

                     else
                        [ UnmatchedText before ]
                    )
                        ++ MatchedText inner
                        :: buildParts (m.index + String.length m.match) rest
    in
    case Regex.find regex str of
        [] ->
            [ UnmatchedText str ]

        matches ->
            buildParts 0 matches


{-| Check whether a string contains any extended inline syntax
that needs processing. Use this as a fast-path to avoid unnecessary work.
-}
hasExtendedSyntax : String -> Bool
hasExtendedSyntax str =
    String.contains "~~" str
        || String.contains "http" str
        || String.contains "[^" str
        || String.contains "==" str
        || String.contains "@" str
        || String.contains "$" str
        || String.contains ":" str
