module BlockParserTest exposing (suite)

import Dict
import Expect
import Markdown
import Markdown.Block as Block exposing (Block(..), BlockContent(..), ListType(..))
import Markdown.Inline exposing (Inline(..), InlineContent(..))
import Test exposing (..)


suite : Test
suite =
    describe "Block Parser"
        [ describe "Headings"
            [ test "ATX heading level 1" <|
                \() ->
                    "# Hello"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "Heading 1" ]
            , test "ATX heading level 3" <|
                \() ->
                    "### Hello"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "Heading 3" ]
            , test "setext heading level 1" <|
                \() ->
                    "Hello\n====="
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "Heading 1" ]
            , test "setext heading level 2" <|
                \() ->
                    "Hello\n-----"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "Heading 2" ]
            ]
        , describe "Paragraphs"
            [ test "single paragraph" <|
                \() ->
                    "Hello world"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "Paragraph" ]
            , test "two paragraphs separated by blank line" <|
                \() ->
                    "First\n\nSecond"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "Paragraph", "BlankLine", "Paragraph" ]
            ]
        , describe "Code blocks"
            [ test "fenced code block" <|
                \() ->
                    "```\ncode here\n```"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "CodeBlock" ]
            , test "indented code block" <|
                \() ->
                    "    indented code"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "CodeBlock" ]
            ]
        , describe "Block quotes"
            [ test "simple blockquote" <|
                \() ->
                    "> quoted text"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "BlockQuote" ]
            ]
        , describe "Lists"
            [ test "unordered list" <|
                \() ->
                    "- item 1\n- item 2\n- item 3"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "UnorderedList" ]
            , test "ordered list" <|
                \() ->
                    "1. item 1\n2. item 2"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "OrderedList" ]
            ]
        , describe "Thematic break"
            [ test "horizontal rule" <|
                \() ->
                    "---"
                        |> parseBlocks
                        |> List.map blockLabel
                        |> Expect.equal [ "ThematicBreak" ]
            ]
        ]



-- HELPERS


parseBlocks : String -> List (Block () ())
parseBlocks str =
    (Markdown.parse Nothing str).blocks


blockLabel : Block () () -> String
blockLabel (Block { content }) =
    case content of
        BlankLine _ ->
            "BlankLine"

        ThematicBreak ->
            "ThematicBreak"

        Heading _ level _ ->
            "Heading " ++ String.fromInt level

        CodeBlock _ _ ->
            "CodeBlock"

        Paragraph _ _ ->
            "Paragraph"

        BlockQuote _ ->
            "BlockQuote"

        List listBlock _ ->
            case listBlock.type_ of
                Unordered ->
                    "UnorderedList"

                Ordered _ ->
                    "OrderedList"

        PlainInlines _ ->
            "PlainInlines"

        Block.Custom _ _ ->
            "Custom"
