module RegionTest exposing (suite)

import Expect
import Markdown
import Markdown.Block exposing (Block(..), BlockContent(..))
import SourceLocation exposing (Region)
import Test exposing (..)


suite : Test
suite =
    describe "Region Tracking"
        [ test "single heading has region starting at row 1" <|
            \() ->
                "# Hello"
                    |> parseBlocks
                    |> List.head
                    |> Maybe.map blockRegion
                    |> Maybe.map .start
                    |> Maybe.map .row
                    |> Expect.equal (Just 1)
        , test "second block starts after first" <|
            \() ->
                "# Hello\n\nParagraph"
                    |> parseBlocks
                    |> List.filterMap
                        (\(Block { content, region }) ->
                            case content of
                                Paragraph _ _ ->
                                    Just region.start.row

                                _ ->
                                    Nothing
                        )
                    |> Expect.equal [ 3 ]
        , test "regions are 1-based" <|
            \() ->
                "Hello"
                    |> parseBlocks
                    |> List.head
                    |> Maybe.map blockRegion
                    |> Maybe.map (\r -> r.start.row >= 1 && r.start.col >= 1)
                    |> Expect.equal (Just True)
        , test "multi-line block has end row > start row" <|
            \() ->
                "> line 1\n> line 2\n> line 3"
                    |> parseBlocks
                    |> List.head
                    |> Maybe.map blockRegion
                    |> Maybe.map (\r -> r.end.row > r.start.row)
                    |> Expect.equal (Just True)
        ]



-- HELPERS


parseBlocks : String -> List (Block () ())
parseBlocks str =
    (Markdown.parse Nothing str).blocks


blockRegion : Block () () -> Region
blockRegion (Block { region }) =
    region
