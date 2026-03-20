module BlockIdTest exposing (suite)

import Dict
import Expect
import Markdown
import Test exposing (..)


suite : Test
suite =
    describe "Block ID Extraction"
        [ test "extracts block ID from paragraph" <|
            \() ->
                "Some text ^my-id"
                    |> parseBlockIds
                    |> Dict.keys
                    |> Expect.equal [ "my-id" ]
        , test "extracts multiple block IDs" <|
            \() ->
                "First paragraph ^id-one\n\nSecond paragraph ^id-two"
                    |> parseBlockIds
                    |> Dict.keys
                    |> List.sort
                    |> Expect.equal [ "id-one", "id-two" ]
        , test "no block IDs returns empty dict" <|
            \() ->
                "Just a paragraph"
                    |> parseBlockIds
                    |> Dict.isEmpty
                    |> Expect.equal True
        , test "block ID has valid region" <|
            \() ->
                "Some text ^my-id"
                    |> parseBlockIds
                    |> Dict.get "my-id"
                    |> Maybe.map (\r -> r.start.row >= 1)
                    |> Expect.equal (Just True)
        ]



-- HELPERS


parseBlockIds : String -> Dict.Dict String { start : { row : Int, col : Int }, end : { row : Int, col : Int } }
parseBlockIds str =
    (Markdown.parse Nothing str).blockIds
