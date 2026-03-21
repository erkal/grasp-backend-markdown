module InlineRegionTest exposing (suite)

import Dict
import Expect
import Markdown
import Markdown.Block exposing (Block(..), BlockContent(..), ListType(..))
import Markdown.Inline exposing (Inline(..), InlineContent(..))
import SourceLocation exposing (Region)
import Test exposing (..)


suite : Test
suite =
    describe "Inline Region Tracking"
        [ describe "Inline regions in parsed AST"
            [ test "single text in paragraph has correct region" <|
                \() ->
                    "Hello"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ { start = { row = 1, col = 1 }, end = { row = 1, col = 6 } } ]
            , test "bold text has correct region" <|
                \() ->
                    "**bold**"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ { start = { row = 1, col = 1 }, end = { row = 1, col = 9 } } ]
            , test "text before and after bold" <|
                \() ->
                    "Hello **bold** end"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ { start = { row = 1, col = 1 }, end = { row = 1, col = 7 } }
                            , { start = { row = 1, col = 7 }, end = { row = 1, col = 15 } }
                            , { start = { row = 1, col = 15 }, end = { row = 1, col = 19 } }
                            ]
            , test "wikilink has correct region" <|
                \() ->
                    "see [[basics]]"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ { start = { row = 1, col = 1 }, end = { row = 1, col = 5 } }
                            , { start = { row = 1, col = 5 }, end = { row = 1, col = 15 } }
                            ]
            , test "inline code has correct region" <|
                \() ->
                    "use `code` here"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ { start = { row = 1, col = 1 }, end = { row = 1, col = 5 } }
                            , { start = { row = 1, col = 5 }, end = { row = 1, col = 11 } }
                            , { start = { row = 1, col = 11 }, end = { row = 1, col = 16 } }
                            ]
            , test "heading inlines have correct region" <|
                \() ->
                    "# Hello **world**"
                        |> parseFirstHeadingInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ { start = { row = 1, col = 3 }, end = { row = 1, col = 9 } }
                            , { start = { row = 1, col = 9 }, end = { row = 1, col = 18 } }
                            ]
            , test "inline in blockquote has correct column" <|
                \() ->
                    "> Hello"
                        |> parseBlockQuoteInlines
                        |> List.map inlineRegion
                        |> List.map .start
                        |> List.map .col
                        |> List.all (\col -> col > 1)
                        |> Expect.equal True
            , test "inline in list item has correct column" <|
                \() ->
                    "- Hello"
                        |> parseListItemInlines
                        |> List.map inlineRegion
                        |> List.map .start
                        |> List.map .col
                        |> List.all (\col -> col > 1)
                        |> Expect.equal True
            , test "paragraph on second line has correct row" <|
                \() ->
                    "# Title\n\nHello"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> List.map .start
                        |> List.map .row
                        |> Expect.equal [ 3 ]
            , test "multi-line paragraph inlines span rows correctly" <|
                \() ->
                    "first line\nsecond **bold** here"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ { start = { row = 1, col = 1 }, end = { row = 2, col = 8 } }
                            , { start = { row = 2, col = 8 }, end = { row = 2, col = 16 } }
                            , { start = { row = 2, col = 16 }, end = { row = 2, col = 21 } }
                            ]
            ]
        , describe "Wikilink collection"
            [ test "wikilinks dict is populated" <|
                \() ->
                    "See [[basics]] and [[other]]"
                        |> Markdown.parse Nothing
                        |> .wikilinks
                        |> Dict.size
                        |> Expect.equal 2
            , test "wikilink target is correct in dict" <|
                \() ->
                    "See [[basics]]"
                        |> Markdown.parse Nothing
                        |> .wikilinks
                        |> Dict.values
                        |> List.map .target
                        |> Expect.equal [ "basics" ]
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


parseFirstHeadingInlines : String -> List (Inline ())
parseFirstHeadingInlines str =
    (Markdown.parse Nothing str).blocks
        |> List.filterMap
            (\(Block { content }) ->
                case content of
                    Heading _ _ inlines ->
                        Just inlines

                    _ ->
                        Nothing
            )
        |> List.head
        |> Maybe.withDefault []


parseBlockQuoteInlines : String -> List (Inline ())
parseBlockQuoteInlines str =
    (Markdown.parse Nothing str).blocks
        |> List.filterMap
            (\(Block { content }) ->
                case content of
                    BlockQuote blocks ->
                        blocks
                            |> List.filterMap
                                (\(Block inner) ->
                                    case inner.content of
                                        Paragraph _ inlines ->
                                            Just inlines

                                        _ ->
                                            Nothing
                                )
                            |> List.head

                    _ ->
                        Nothing
            )
        |> List.head
        |> Maybe.withDefault []


parseListItemInlines : String -> List (Inline ())
parseListItemInlines str =
    (Markdown.parse Nothing str).blocks
        |> List.filterMap
            (\(Block { content }) ->
                case content of
                    Markdown.Block.List _ items ->
                        items
                            |> List.head
                            |> Maybe.andThen
                                (List.filterMap
                                    (\(Block inner) ->
                                        case inner.content of
                                            Paragraph _ inlines ->
                                                Just inlines

                                            _ ->
                                                Nothing
                                    )
                                    >> List.head
                                )

                    _ ->
                        Nothing
            )
        |> List.head
        |> Maybe.withDefault []


inlineRegion : Inline () -> Region
inlineRegion (Inline { region }) =
    region
