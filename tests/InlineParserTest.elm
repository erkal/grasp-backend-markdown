module InlineParserTest exposing (suite)

import Expect
import Markdown
import Markdown.Block exposing (Block(..), BlockContent(..))
import Markdown.Inline as Inline exposing (Inline(..), InlineContent(..))
import Test exposing (..)


suite : Test
suite =
    describe "Inline Parser"
        [ describe "Emphasis"
            [ test "bold text" <|
                \() ->
                    "**bold**"
                        |> parseFirstParagraphInlines
                        |> List.map inlineLabel
                        |> Expect.equal [ "Emphasis 2" ]
            , test "italic text" <|
                \() ->
                    "*italic*"
                        |> parseFirstParagraphInlines
                        |> List.map inlineLabel
                        |> Expect.equal [ "Emphasis 1" ]
            ]
        , describe "Code inline"
            [ test "inline code" <|
                \() ->
                    "`code`"
                        |> parseFirstParagraphInlines
                        |> List.map inlineLabel
                        |> Expect.equal [ "CodeInline" ]
            ]
        , describe "Links"
            [ test "link with title" <|
                \() ->
                    "[text](url)"
                        |> parseFirstParagraphInlines
                        |> List.map inlineLabel
                        |> Expect.equal [ "Link" ]
            ]
        , describe "Images"
            [ test "image" <|
                \() ->
                    "![alt](src.jpg)"
                        |> parseFirstParagraphInlines
                        |> List.map inlineLabel
                        |> Expect.equal [ "Image" ]
            ]
        , describe "Mixed content"
            [ test "text with bold and code" <|
                \() ->
                    "Hello **world** and `code`"
                        |> parseFirstParagraphInlines
                        |> List.map inlineLabel
                        |> Expect.equal [ "Text", "Emphasis 2", "Text", "CodeInline" ]
            ]
        ]



-- HELPERS


parseFirstParagraphInlines : String -> List (Inline ())
parseFirstParagraphInlines str =
    (Markdown.parse Nothing str).blocks
        |> List.filterMap
            (\(Block { content }) ->
                case content of
                    Paragraph _ inlines ->
                        Just inlines

                    _ ->
                        Nothing
            )
        |> List.head
        |> Maybe.withDefault []


inlineLabel : Inline () -> String
inlineLabel (Inline { content }) =
    case content of
        Text _ ->
            "Text"

        HardLineBreak ->
            "HardLineBreak"

        CodeInline _ ->
            "CodeInline"

        Link _ _ _ ->
            "Link"

        Image _ _ _ ->
            "Image"

        HtmlInline _ _ _ ->
            "HtmlInline"

        Emphasis len _ ->
            "Emphasis " ++ String.fromInt len

        Inline.Custom _ _ ->
            "Custom"

        Wikilink _ ->
            "Wikilink"
