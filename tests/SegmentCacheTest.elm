module SegmentCacheTest exposing (suite)

import Expect
import SegmentCache exposing (Cache, Config)
import Test exposing (..)


suite : Test
suite =
    let
        config : Config Int
        config =
            { split = splitAtPipe
            , process = String.length
            }

        splitAtPipe : String -> List { text : String, startLine : Int }
        splitAtPipe str =
            str
                |> String.split "|"
                |> List.indexedMap
                    (\i text -> { text = text, startLine = i + 1 })
    in
    describe "SegmentCache"
        [ test "empty cache, all segments are processed" <|
            \() ->
                SegmentCache.empty
                    |> SegmentCache.step config "aa|bbb|c"
                    |> SegmentCache.toList
                    |> List.map .result
                    |> Expect.equal [ 2, 3, 1 ]
        , test "unchanged document produces structurally equal cache" <|
            \() ->
                let
                    cache : Cache Int
                    cache =
                        SegmentCache.empty
                            |> SegmentCache.step config "aa|bbb|c"
                in
                cache
                    |> SegmentCache.step config "aa|bbb|c"
                    |> Expect.equal cache
        , test "one segment changed, others reused" <|
            \() ->
                SegmentCache.empty
                    |> SegmentCache.step config "aa|bbb|c"
                    |> SegmentCache.step config "aa|XXXX|c"
                    |> SegmentCache.toList
                    |> List.map .result
                    |> Expect.equal [ 2, 4, 1 ]
        , test "segment added" <|
            \() ->
                SegmentCache.empty
                    |> SegmentCache.step config "aa|bbb"
                    |> SegmentCache.step config "aa|bbb|c"
                    |> SegmentCache.toList
                    |> List.map .result
                    |> Expect.equal [ 2, 3, 1 ]
        , test "segment removed" <|
            \() ->
                SegmentCache.empty
                    |> SegmentCache.step config "aa|bbb|c"
                    |> SegmentCache.step config "aa|c"
                    |> SegmentCache.toList
                    |> List.map .result
                    |> Expect.equal [ 2, 1 ]
        , test "duplicate segment texts both get correct results" <|
            \() ->
                SegmentCache.empty
                    |> SegmentCache.step config "aa|aa|bbb"
                    |> SegmentCache.toList
                    |> List.map .result
                    |> Expect.equal [ 2, 2, 3 ]
        , test "startLine is always fresh from split" <|
            \() ->
                SegmentCache.empty
                    |> SegmentCache.step config "aa|bbb|c"
                    |> SegmentCache.step config "aa|XXXX|c"
                    |> SegmentCache.toList
                    |> List.map .startLine
                    |> Expect.equal [ 1, 2, 3 ]
        ]
