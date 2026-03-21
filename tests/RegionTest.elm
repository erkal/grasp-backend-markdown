module RegionTest exposing (suite)

import Expect
import Markdown
import Markdown.Block exposing (Block(..), BlockContent(..))
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
                    |> Maybe.map (\( ( startRow, _ ), _ ) -> startRow)
                    |> Expect.equal (Just 1)
        , test "second block starts after first" <|
            \() ->
                "# Hello\n\nParagraph"
                    |> parseBlocks
                    |> List.filterMap
                        (\(Block { content, region }) ->
                            case content of
                                Paragraph _ _ ->
                                    let
                                        ( ( startRow, _ ), _ ) =
                                            region
                                    in
                                    Just startRow

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
                    |> Maybe.map (\( ( startRow, startCol ), _ ) -> startRow >= 1 && startCol >= 1)
                    |> Expect.equal (Just True)
        , test "multi-line block has end row > start row" <|
            \() ->
                "> line 1\n> line 2\n> line 3"
                    |> parseBlocks
                    |> List.head
                    |> Maybe.map blockRegion
                    |> Maybe.map (\( ( startRow, _ ), ( endRow, _ ) ) -> endRow > startRow)
                    |> Expect.equal (Just True)
        ]



-- HELPERS


parseBlocks : String -> List (Block () ())
parseBlocks str =
    (Markdown.parse Nothing str).blocks


blockRegion (Block { region }) =
    region
