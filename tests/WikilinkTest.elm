module WikilinkTest exposing (suite)

import Expect
import Markdown.Wikilink as Wikilink exposing (Fragment(..), WikilinkData)
import Test exposing (..)


suite : Test
suite =
    describe "Wikilink Parsing"
        [ describe "parseContent"
            [ test "basic wikilink" <|
                \() ->
                    Wikilink.parseContent False "basics"
                        |> .target
                        |> Expect.equal "basics"
            , test "wikilink with display text" <|
                \() ->
                    let
                        result : WikilinkData
                        result =
                            Wikilink.parseContent False "basics|See the basics"
                    in
                    Expect.all
                        [ \r -> r.target |> Expect.equal "basics"
                        , \r -> r.display |> Expect.equal (Just "See the basics")
                        ]
                        result
            , test "wikilink with heading fragment" <|
                \() ->
                    Wikilink.parseContent False "basics#Heading 2"
                        |> .fragment
                        |> Expect.equal (Just (HeadingFragment [ "Heading 2" ]))
            , test "wikilink with block fragment" <|
                \() ->
                    Wikilink.parseContent False "basics#^my-block"
                        |> .fragment
                        |> Expect.equal (Just (BlockFragment "my-block"))
            , test "embed wikilink" <|
                \() ->
                    Wikilink.parseContent True "photo.jpg"
                        |> .isEmbed
                        |> Expect.equal True
            , test "heading search" <|
                \() ->
                    Wikilink.parseContent False "##Heading"
                        |> .fragment
                        |> Expect.equal (Just (HeadingSearch "Heading"))
            , test "block search" <|
                \() ->
                    Wikilink.parseContent False "^^my-block"
                        |> .fragment
                        |> Expect.equal (Just (BlockSearch "my-block"))
            , test "PDF page fragment" <|
                \() ->
                    Wikilink.parseContent False "doc.pdf#page=5"
                        |> .fragment
                        |> Expect.equal (Just (PdfPage 5))
            , test "PDF height fragment" <|
                \() ->
                    Wikilink.parseContent False "doc.pdf#height=400"
                        |> .fragment
                        |> Expect.equal (Just (PdfHeight 400))
            ]
        , describe "Embed type checks"
            [ test "image embed" <|
                \() ->
                    Wikilink.isImageEmbed "photo.jpg"
                        |> Expect.equal True
            , test "video embed" <|
                \() ->
                    Wikilink.isVideoEmbed "video.mp4"
                        |> Expect.equal True
            , test "audio embed" <|
                \() ->
                    Wikilink.isAudioEmbed "song.mp3"
                        |> Expect.equal True
            , test "PDF embed" <|
                \() ->
                    Wikilink.isPdfEmbed "document.pdf"
                        |> Expect.equal True
            , test "non-embed" <|
                \() ->
                    Wikilink.isImageEmbed "file.md"
                        |> Expect.equal False
            ]
        , describe "defaultDisplay"
            [ test "strips path" <|
                \() ->
                    Wikilink.defaultDisplay
                        { target = "path/to/file.md"
                        , fragment = Nothing
                        , display = Nothing
                        , isEmbed = False
                        }
                        |> Expect.equal "file"
            ]
        ]
