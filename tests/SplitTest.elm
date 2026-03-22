module SplitTest exposing (suite)

import Expect
import Markdown.Split exposing (splitAtBlankLines)
import Test exposing (..)


suite : Test
suite =
    describe "Markdown.Split.splitAtBlankLines"
        [ basicTests
        , blankLineTests
        , codeFenceTests
        , listTests
        , blockQuoteTests
        , specExampleTest
        ]


basicTests : Test
basicTests =
    describe "basic splitting"
        [ test "single paragraph" <|
            \() ->
                splitAtBlankLines "Hello world"
                    |> Expect.equal
                        [ { text = "Hello world", startLine = 1 } ]
        , test "two paragraphs" <|
            \() ->
                splitAtBlankLines "First\n\nSecond"
                    |> Expect.equal
                        [ { text = "First", startLine = 1 }
                        , { text = "Second", startLine = 3 }
                        ]
        , test "heading and paragraph" <|
            \() ->
                splitAtBlankLines "# Title\n\nSome text"
                    |> Expect.equal
                        [ { text = "# Title", startLine = 1 }
                        , { text = "Some text", startLine = 3 }
                        ]
        , test "multi-line paragraph stays together" <|
            \() ->
                splitAtBlankLines "Line one\nLine two\nLine three"
                    |> Expect.equal
                        [ { text = "Line one\nLine two\nLine three", startLine = 1 } ]
        , test "multiple blank lines between blocks" <|
            \() ->
                splitAtBlankLines "First\n\n\n\nSecond"
                    |> Expect.equal
                        [ { text = "First", startLine = 1 }
                        , { text = "Second", startLine = 5 }
                        ]
        ]


blankLineTests : Test
blankLineTests =
    describe "leading, trailing, and empty"
        [ test "empty document" <|
            \() ->
                splitAtBlankLines ""
                    |> Expect.equal []
        , test "leading blank lines discarded" <|
            \() ->
                splitAtBlankLines "\n\nFirst"
                    |> Expect.equal
                        [ { text = "First", startLine = 3 } ]
        , test "trailing blank lines discarded" <|
            \() ->
                splitAtBlankLines "First\n\n"
                    |> Expect.equal
                        [ { text = "First", startLine = 1 } ]
        ]


codeFenceTests : Test
codeFenceTests =
    describe "fenced code blocks"
        [ test "backtick fence with blank lines inside" <|
            \() ->
                splitAtBlankLines "```\n\ncode\n\n```"
                    |> Expect.equal
                        [ { text = "```\n\ncode\n\n```", startLine = 1 } ]
        , test "tilde fence" <|
            \() ->
                splitAtBlankLines "~~~\ncode\n~~~"
                    |> Expect.equal
                        [ { text = "~~~\ncode\n~~~", startLine = 1 } ]
        , test "fence with language info string" <|
            \() ->
                splitAtBlankLines "```python\nprint('hi')\n```"
                    |> Expect.equal
                        [ { text = "```python\nprint('hi')\n```", startLine = 1 } ]
        , test "fence with up to 3 leading spaces" <|
            \() ->
                splitAtBlankLines "   ```\ncode\n   ```"
                    |> Expect.equal
                        [ { text = "   ```\ncode\n   ```", startLine = 1 } ]
        , test "code fence between paragraphs" <|
            \() ->
                splitAtBlankLines "Before\n\n```\ncode\n```\n\nAfter"
                    |> Expect.equal
                        [ { text = "Before", startLine = 1 }
                        , { text = "```\ncode\n```", startLine = 3 }
                        , { text = "After", startLine = 7 }
                        ]
        ]


listTests : Test
listTests =
    describe "lists"
        [ test "tight list" <|
            \() ->
                splitAtBlankLines "- One\n- Two\n- Three"
                    |> Expect.equal
                        [ { text = "- One\n- Two\n- Three", startLine = 1 } ]
        , test "loose list stays together" <|
            \() ->
                splitAtBlankLines "- One\n\n- Two\n\n- Three"
                    |> Expect.equal
                        [ { text = "- One\n\n- Two\n\n- Three", startLine = 1 } ]
        , test "ordered list" <|
            \() ->
                splitAtBlankLines "1. First\n\n2. Second"
                    |> Expect.equal
                        [ { text = "1. First\n\n2. Second", startLine = 1 } ]
        , test "list followed by paragraph" <|
            \() ->
                splitAtBlankLines "- Item\n\nParagraph"
                    |> Expect.equal
                        [ { text = "- Item", startLine = 1 }
                        , { text = "Paragraph", startLine = 3 }
                        ]
        , test "list item with indented continuation" <|
            \() ->
                splitAtBlankLines "- Item\n\n  Continued"
                    |> Expect.equal
                        [ { text = "- Item\n\n  Continued", startLine = 1 } ]
        , test "star marker" <|
            \() ->
                splitAtBlankLines "* One\n\n* Two"
                    |> Expect.equal
                        [ { text = "* One\n\n* Two", startLine = 1 } ]
        , test "plus marker" <|
            \() ->
                splitAtBlankLines "+ One\n\n+ Two"
                    |> Expect.equal
                        [ { text = "+ One\n\n+ Two", startLine = 1 } ]
        ]


blockQuoteTests : Test
blockQuoteTests =
    describe "block quotes"
        [ test "block quote inside list stays together" <|
            \() ->
                splitAtBlankLines "- Item\n\n  > Quote"
                    |> Expect.equal
                        [ { text = "- Item\n\n  > Quote", startLine = 1 } ]
        , test "block quote at column 0 inside list stays together" <|
            \() ->
                splitAtBlankLines "- Item\n\n> Quote"
                    |> Expect.equal
                        [ { text = "- Item\n\n> Quote", startLine = 1 } ]
        , test "block quotes outside list split at blank line" <|
            \() ->
                splitAtBlankLines "> First\n\n> Second"
                    |> Expect.equal
                        [ { text = "> First", startLine = 1 }
                        , { text = "> Second", startLine = 3 }
                        ]
        ]


specExampleTest : Test
specExampleTest =
    describe "spec example"
        [ test "full example from spec" <|
            \() ->
                [ "# Title"
                , ""
                , "Some paragraph"
                , "with two lines."
                , ""
                , "- Item one"
                , ""
                , "- Item two"
                , ""
                , "```python"
                , ""
                , "def foo():"
                , "    pass"
                , "```"
                ]
                    |> String.join "\n"
                    |> splitAtBlankLines
                    |> Expect.equal
                        [ { text = "# Title", startLine = 1 }
                        , { text = "Some paragraph\nwith two lines.", startLine = 3 }
                        , { text = "- Item one\n\n- Item two", startLine = 6 }
                        , { text = "```python\n\ndef foo():\n    pass\n```", startLine = 10 }
                        ]
        ]
