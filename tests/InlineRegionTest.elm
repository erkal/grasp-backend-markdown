module InlineRegionTest exposing (suite)

import Dict
import Expect
import Markdown
import Markdown.Block exposing (Block(..), BlockContent(..), ListType(..))
import Markdown.Inline exposing (Inline(..), InlineContent(..))
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
                            [ ( ( 1, 1 ), ( 1, 6 ) ) ]
            , test "bold text has correct region" <|
                \() ->
                    "**bold**"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ ( ( 1, 1 ), ( 1, 9 ) ) ]
            , test "text before and after bold" <|
                \() ->
                    "Hello **bold** end"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ ( ( 1, 1 ), ( 1, 7 ) )
                            , ( ( 1, 7 ), ( 1, 15 ) )
                            , ( ( 1, 15 ), ( 1, 19 ) )
                            ]
            , test "wikilink has correct region" <|
                \() ->
                    "see [[basics]]"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ ( ( 1, 1 ), ( 1, 5 ) )
                            , ( ( 1, 5 ), ( 1, 15 ) )
                            ]
            , test "inline code has correct region" <|
                \() ->
                    "use `code` here"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ ( ( 1, 1 ), ( 1, 5 ) )
                            , ( ( 1, 5 ), ( 1, 11 ) )
                            , ( ( 1, 11 ), ( 1, 16 ) )
                            ]
            , test "heading inlines have correct region" <|
                \() ->
                    "# Hello **world**"
                        |> parseFirstHeadingInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ ( ( 1, 3 ), ( 1, 9 ) )
                            , ( ( 1, 9 ), ( 1, 18 ) )
                            ]
            , test "inline in blockquote has correct column" <|
                \() ->
                    "> Hello"
                        |> parseBlockQuoteInlines
                        |> List.map inlineRegion
                        |> List.map (\( ( _, col ), _ ) -> col)
                        |> List.all (\col -> col > 1)
                        |> Expect.equal True
            , test "inline in list item has correct column" <|
                \() ->
                    "- Hello"
                        |> parseListItemInlines
                        |> List.map inlineRegion
                        |> List.map (\( ( _, col ), _ ) -> col)
                        |> List.all (\col -> col > 1)
                        |> Expect.equal True
            , test "paragraph on second line has correct row" <|
                \() ->
                    "# Title\n\nHello"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> List.map (\( ( row, _ ), _ ) -> row)
                        |> Expect.equal [ 3 ]
            , test "multi-line paragraph inlines span rows correctly" <|
                \() ->
                    "first line\nsecond **bold** here"
                        |> parseFirstParagraphInlines
                        |> List.map inlineRegion
                        |> Expect.equal
                            [ ( ( 1, 1 ), ( 2, 8 ) )
                            , ( ( 2, 8 ), ( 2, 16 ) )
                            , ( ( 2, 16 ), ( 2, 21 ) )
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


inlineRegion (Inline { region }) =
    region
