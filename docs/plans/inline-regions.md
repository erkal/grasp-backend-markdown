# Inline Region Tracking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compute accurate source regions (row, col) for all inline AST nodes, and populate `ParseResult.wikilinks`.

**Architecture:** Move inline parsing from `RawBlock.parse` to `Block.assignRegions`, where block positions are known. Pass start position to `InlineParser.parse`, which converts match character offsets into absolute (row, col) regions. Carry column offsets through nested blocks (blockquotes, lists) so inline regions are strictly within their parent block regions.

**Tech Stack:** Elm, elm-test

---

## Symlink Constraint

In the grasp repo:
- `grasp/packages/markdown` → symlinks to **this repo's** `packages/markdown` (changes propagate automatically)
- `grasp/packages/source-location` → symlinks to **`grasp-source-location`** (separate repo)

Therefore: **do NOT modify `packages/source-location/`**. The `offsetToPosition` helper goes in `packages/markdown/` so it propagates to grasp via the symlink.

The `Markdown.Block.parse` signature does NOT change — grasp calls it at `MarkdownRendering.elm:36` and `:602`. The only visible change for grasp consumers: `ParseResult.wikilinks` will now be populated (was always `Dict.empty`).

## File Map

- **Modify:** `packages/markdown/src/Markdown/InlineParser.elm` — add `offsetToPosition` helper, accept `Position`, offset-aware `normalMatch`, real regions in `matchToInline`
- **Modify:** `packages/markdown/src/Markdown/RawBlock.elm` — expose `parseBlockStructure` (pipeline without inline parsing)
- **Modify:** `packages/markdown/src/Markdown/Block.elm` — inline parsing in `fromRawBlock`, wikilink collection, column offsets for nested blocks
- **Create:** `tests/InlineRegionTest.elm` — inline region tests
- **No changes:** `packages/source-location/` (separate repo in grasp), `src/Main.elm` (already handles arbitrary regions)

## Key Design Decisions

1. **Why move inline parsing?** Currently `RawBlock.parse` parses inlines before block positions are known. By deferring to `assignRegions` in `Block.parse`, we have the row + column offset when calling the inline parser.

2. **How offsets become regions.** The inline parser's `Match.start`/`Match.end` are character offsets in the trimmed rawText. A new `offsetToPosition` helper converts these to `(row, col)` by counting newlines, then shifts by the block's start position.

3. **normalMatch carries scope-relative offsets.** Currently `normalMatch` sets `start = 0, end = 0`. Text gap nodes need real offsets. These are scope-relative (not absolute), matching the structured matches in the same scope.

4. **Nested offset resolution via `scopeOffsetToPos`.** `prepareChildMatch` adjusts child offsets to be parent-text-relative. In `matchToInline`, each nesting level creates a new `childScopeOffsetToPos` that adds the parent's `textStart`: `childScopeOffsetToPos offset = parentScopeOffsetToPos (match.textStart + offset)`. This recursively converts relative offsets to absolute positions.

5. **Column offsets for nested blocks.** Blockquotes strip `> ` (variable width), lists strip `indentLength` chars. We pass `colOffset` through `assignRegions` recursion. For blockquotes, compute prefix width from the source line. For lists, use `indentLength`.

6. **`textAsParagraph` flag preserved.** The current `parseInline` uses `textAsParagraph` to decide between `Paragraph` and `PlainInlines` (tight lists). This flag is threaded through `assignRegions`/`fromRawBlock` — `True` at top level, `isLoose` for list items.

7. **Multi-line blocks.** `offsetToPosition` handles newlines in rawText. Each newline increments the row. Column resets to 1 for continuation lines (not perfect for variable-prefix edge cases, but covers standard markdown).

---

### Task 1: Add `offsetToPosition` helper and offset-aware `normalMatch`

**Files:**
- Modify: `packages/markdown/src/Markdown/InlineParser.elm`

Note: `offsetToPosition` lives in `InlineParser.elm`, NOT in `packages/source-location/`, because `source-location` is a separate repo symlinked into grasp independently.

- [ ] **Step 1: Add `offsetToPosition` helper**

Add this private helper to `packages/markdown/src/Markdown/InlineParser.elm`. Also update the import to include `Position`:

```elm
import SourceLocation exposing (Position, Region, placeholderRegion)
```

```elm
{-| Convert a character offset within `text` to an absolute Position.
`base` is the source position of the first character in `text`.
For continuation lines (after newlines in `text`), column resets to 1.
-}
offsetToPosition : Position -> String -> Int -> Position
offsetToPosition base text offset =
    let
        before =
            String.left offset text

        newlineCount =
            before
                |> String.toList
                |> List.filter (\c -> c == '\n')
                |> List.length
    in
    if newlineCount == 0 then
        { row = base.row, col = base.col + offset }

    else
        let
            lastNewlineIndex =
                before
                    |> String.indexes "\n"
                    |> List.reverse
                    |> List.head
                    |> Maybe.withDefault 0

            colAfterNewline =
                offset - lastNewlineIndex - 1
        in
        { row = base.row + newlineCount, col = 1 + colAfterNewline }
```

- [ ] **Step 2: Change `normalMatch` to accept start and end offsets**

These are scope-relative offsets (matching the convention of structured matches from `prepareChildMatch`):

```elm
-- Old:
normalMatch : String -> Match
normalMatch text =
    Match
        { type_ = NormalType
        , start = 0
        , end = 0
        , textStart = 0
        , textEnd = 0
        , text = formatStr text
        , matches = []
        }

-- New:
normalMatch : Int -> Int -> String -> Match
normalMatch start end text =
    Match
        { type_ = NormalType
        , start = start
        , end = end
        , textStart = start
        , textEnd = end
        , text = formatStr text
        , matches = []
        }
```

- [ ] **Step 3: Update `parseTextMatches` to pass scope-relative offsets to `normalMatch`**

No `baseOffset` parameter is needed — all offsets remain scope-relative. The only change is passing correct start/end to `normalMatch`:

```elm
parseTextMatches : String -> List Match -> List Match -> List Match
parseTextMatches rawText parsedMatches matches =
    case matches of
        [] ->
            case parsedMatches of
                [] ->
                    if String.isEmpty rawText then
                        []

                    else
                        [ normalMatch 0 (String.length rawText) rawText ]

                (Match matchModel) :: _ ->
                    if matchModel.start > 0 then
                        normalMatch 0 matchModel.start (String.left matchModel.start rawText)
                            :: parsedMatches

                    else
                        parsedMatches

        match :: matchesTail ->
            parseTextMatches rawText
                (parseTextMatch rawText match parsedMatches)
                matchesTail
```

- [ ] **Step 4: Update `parseTextMatch` to pass scope-relative offsets**

```elm
parseTextMatch : String -> Match -> List Match -> List Match
parseTextMatch rawText (Match matchModel) parsedMatches =
    let
        updtMatch : Match
        updtMatch =
            Match
                { matchModel
                    | matches =
                        parseTextMatches matchModel.text [] matchModel.matches
                }
    in
    case parsedMatches of
        [] ->
            let
                finalStr =
                    String.dropLeft matchModel.end rawText
            in
            if String.isEmpty finalStr then
                [ updtMatch ]

            else
                [ updtMatch
                , normalMatch matchModel.end (String.length rawText) finalStr
                ]

        (Match matchHead) :: _ ->
            if matchHead.type_ == NormalType then
                updtMatch :: parsedMatches

            else if matchModel.end == matchHead.start then
                updtMatch :: parsedMatches

            else if matchModel.end < matchHead.start then
                updtMatch
                    :: normalMatch matchModel.end matchHead.start (String.slice matchModel.end matchHead.start rawText)
                    :: parsedMatches

            else
                parsedMatches
```

- [ ] **Step 5: Run tests to verify everything compiles and passes**

Run: `cd ../grasp-backend-markdown-inline-regions && pnpm run test`
Expected: all existing tests pass (no behavior change, just internal offsets stored).

- [ ] **Step 6: Commit**

```bash
git add packages/markdown/src/Markdown/InlineParser.elm
git commit -m "feat: add offsetToPosition and offset-aware normalMatch"
```

---

### Task 2: Position-aware `matchToInline`, updated `parse` signature, deferred inline parsing, and Block integration

This is the core task. It must be done atomically because changing `InlineParser.parse`'s signature, removing `RawBlock.parseInlines`, and updating `Block.parse` all depend on each other. Committing intermediate non-compiling states is avoided.

**Files:**
- Modify: `packages/markdown/src/Markdown/InlineParser.elm`
- Modify: `packages/markdown/src/Markdown/RawBlock.elm`
- Modify: `packages/markdown/src/Markdown/Block.elm`
- Create: `tests/InlineRegionTest.elm`

#### Part A: Write the tests

- [ ] **Step 1: Create `tests/InlineRegionTest.elm` with inline region tests**

```elm
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
```

- [ ] **Step 2: Run tests to verify they fail (regions will be 0:0 → 0:0)**

Run: `cd ../grasp-backend-markdown-inline-regions && pnpm run test`
Expected: new tests fail, existing tests still pass.

#### Part B: Update InlineParser

- [ ] **Step 3: Change `matchToInline` to compute real regions**

Replace `matchToInline` and `matchesToInlines` in `InlineParser.elm`. The key design: each nesting level passes a `scopeOffsetToPos` function that maps scope-relative offsets to absolute Positions. For children, the function is composed: `childOffset -> parentScopeOffsetToPos (match.textStart + childOffset)`.

```elm
matchesToInlines : (Int -> Position) -> List Match -> List (Inline customInline)
matchesToInlines scopeOffsetToPos matches =
    List.map (matchToInline scopeOffsetToPos) matches


matchToInline : (Int -> Position) -> Match -> Inline customInline
matchToInline scopeOffsetToPos (Match match) =
    let
        region : Region
        region =
            { start = scopeOffsetToPos match.start
            , end = scopeOffsetToPos match.end
            }

        childScopeOffsetToPos : Int -> Position
        childScopeOffsetToPos childOffset =
            scopeOffsetToPos (match.textStart + childOffset)

        childInlines : List (Inline customInline)
        childInlines =
            matchesToInlines childScopeOffsetToPos match.matches
    in
    case match.type_ of
        NormalType ->
            Inline { content = Text match.text, region = region }

        HardLineBreakType ->
            Inline { content = HardLineBreak, region = region }

        CodeType ->
            Inline { content = CodeInline match.text, region = region }

        AutolinkType ( text, url ) ->
            Inline
                { content =
                    Link url
                        Nothing
                        [ Inline { content = Text text, region = region } ]
                , region = region
                }

        LinkType ( url, maybeTitle ) ->
            Inline { content = Link url maybeTitle childInlines, region = region }

        ImageType ( url, maybeTitle ) ->
            Inline { content = Image url maybeTitle childInlines, region = region }

        HtmlType model ->
            Inline { content = HtmlInline model.tag model.attributes childInlines, region = region }

        EmphasisType length ->
            Inline { content = Emphasis length childInlines, region = region }

        WikilinkType data ->
            Inline { content = Wikilink data, region = region }
```

- [ ] **Step 4: Update `parse` to accept a `Position` and build the scope offset resolver**

```elm
parse : Options -> References -> Position -> String -> List (Inline i)
parse options refs startPosition rawText =
    let
        trimmedText =
            String.trim rawText

        trimLeftCount =
            String.length rawText - String.length (String.trimLeft rawText)

        trimmedStartPos =
            if trimLeftCount == 0 then
                startPosition

            else
                offsetToPosition startPosition rawText trimLeftCount

        scopeOffsetToPos : Int -> Position
        scopeOffsetToPos charOffset =
            offsetToPosition trimmedStartPos trimmedText charOffset
    in
    trimmedText
        |> initParser options refs
        |> tokenize
        |> tokensToMatches
        |> organizeParserMatches
        |> parseText
        |> .matches
        |> matchesToInlines scopeOffsetToPos
```

Note: `offsetToPosition` is the helper added in Task 1, defined in this same file. No external import needed.

Keep `wrapInline` — it's still used by `walk` for transformations (not initial parsing).

#### Part C: Split RawBlock.parse

- [ ] **Step 5: Expose `parseBlockStructure` in RawBlock.elm**

Add to `packages/markdown/src/Markdown/RawBlock.elm`:

```elm
parseBlockStructure : String -> ( References, List (RawBlock b i) )
parseBlockStructure =
    String.lines
        >> (\a -> incorporateLines a [])
        >> parseReferences Dict.empty
```

Add `parseBlockStructure` to the module exposing list. Note: no `Maybe Options` parameter — the block structure pipeline doesn't use options.

Remove `parseInlines` and `parseInline` functions. Remove the `InlineParser` import and `Markdown.Config` import (no longer needed since `defaultOptions` was only used by `parseInline`). Update the existing `parse` to delegate:

```elm
parse : Maybe Options -> String -> List (RawBlock b i)
parse _ str =
    parseBlockStructure str |> Tuple.second
```

#### Part D: Wire it all together in Block.elm

- [ ] **Step 6: Update `Block.parse` to use `parseBlockStructure` and parse inlines in `assignRegions`**

Add these imports to `Block.elm`:

```elm
import Markdown.Config exposing (Options, defaultOptions)
import Markdown.Helpers exposing (References)
import Regex exposing (Regex)
```

Update `parse`:

```elm
parse : Maybe Options -> String -> ParseResult b i
parse maybeOptions str =
    let
        options : Options
        options =
            Maybe.withDefault defaultOptions maybeOptions

        ( refs, rawBlocks ) =
            RawBlock.parseBlockStructure str

        ( blocks, _ ) =
            assignRegions options refs str True 1 0 rawBlocks

        blockIds : Dict String Region
        blockIds =
            blocks |> List.concatMap collectBlockIds |> Dict.fromList
    in
    { blocks = blocks
    , blockIds = blockIds
    , wikilinks = Dict.empty -- populated in Task 3
    }
```

- [ ] **Step 7: Update `assignRegions` with new parameters**

Add `options`, `refs`, `source`, `textAsParagraph`, and `colOffset` parameters:

```elm
assignRegions : Options -> References -> String -> Bool -> Int -> Int -> List (RawBlock.RawBlock b i) -> ( List (Block b i), Int )
assignRegions options refs source textAsParagraph startRow colOffset rawBlocks =
    rawBlocks
        |> List.foldl
            (\rawBlock ( acc, row ) ->
                let
                    ( block, nextRow ) =
                        fromRawBlock options refs source textAsParagraph row colOffset rawBlock
                in
                ( block :: acc, nextRow )
            )
            ( [], startRow )
        |> Tuple.mapFirst List.reverse
```

- [ ] **Step 8: Update `fromRawBlock` to parse inlines with position context**

```elm
fromRawBlock : Options -> References -> String -> Bool -> Int -> Int -> RawBlock.RawBlock b i -> ( Block b i, Int )
fromRawBlock options refs source textAsParagraph row colOffset rawBlock =
    let
        lineCount : Int
        lineCount =
            rawBlockLineCount rawBlock

        region : Region
        region =
            { start = { row = row, col = 1 }
            , end = { row = row + lineCount, col = 1 }
            }

        parseInlinesAt : Int -> String -> List (Inline i)
        parseInlinesAt startCol rawText =
            InlineParser.parse options refs { row = row, col = startCol } rawText
    in
    case rawBlock of
        RawBlock.Heading rawText lvl _ ->
            let
                headingContentCol =
                    1 + colOffset + headingPrefixLength source row
            in
            ( Block { content = Heading rawText lvl (parseInlinesAt headingContentCol rawText), region = region }
            , row + lineCount
            )

        RawBlock.Paragraph rawText _ ->
            let
                inlines =
                    parseInlinesAt (1 + colOffset) rawText
            in
            if not textAsParagraph then
                ( Block { content = PlainInlines inlines, region = region }, row + lineCount )

            else
                case inlines of
                    [ Inline { content } ] ->
                        case content of
                            HtmlInline _ _ _ ->
                                ( Block { content = PlainInlines inlines, region = region }, row + lineCount )

                            _ ->
                                ( Block { content = Paragraph rawText inlines, region = region }, row + lineCount )

                    _ ->
                        ( Block { content = Paragraph rawText inlines, region = region }, row + lineCount )

        RawBlock.BlockQuote childBlocks ->
            let
                bqColOffset =
                    colOffset + blockQuotePrefixWidth source row

                ( wrappedChildren, _ ) =
                    assignRegions options refs source True row bqColOffset childBlocks
            in
            ( Block { content = BlockQuote wrappedChildren, region = region }
            , row + lineCount
            )

        RawBlock.List listBlock items ->
            let
                listColOffset =
                    colOffset + listBlock.indentLength

                ( wrappedItems, _ ) =
                    items
                        |> List.foldl
                            (\itemBlocks ( itemsAcc, itemRow ) ->
                                let
                                    ( wrappedItemBlocks, nextItemRow ) =
                                        assignRegions options refs source listBlock.isLoose itemRow listColOffset itemBlocks
                                in
                                ( wrappedItemBlocks :: itemsAcc, nextItemRow )
                            )
                            ( [], row )
                        |> Tuple.mapFirst List.reverse
            in
            ( Block { content = List (fromRawListBlock listBlock) wrappedItems, region = region }
            , row + lineCount
            )

        RawBlock.Custom customBlock childBlocks ->
            let
                ( wrappedChildren, _ ) =
                    assignRegions options refs source True row colOffset childBlocks
            in
            ( Block { content = Custom customBlock wrappedChildren, region = region }
            , row + lineCount
            )

        RawBlock.PlainInlines _ ->
            -- PlainInlines without raw text shouldn't occur after removing parseInline from RawBlock.
            -- This variant was only created by the old parseInline; with the new flow,
            -- all paragraphs arrive as RawBlock.Paragraph and are converted above.
            ( Block { content = PlainInlines [], region = region }
            , row + lineCount
            )

        _ ->
            ( Block { content = fromRawBlockContent rawBlock, region = region }
            , row + lineCount
            )
```

- [ ] **Step 9: Add prefix width helpers**

```elm
{-| Compute the ATX heading prefix length (e.g., "# " = 2, "## " = 3).
For setext headings (no `#` prefix), returns 0.
-}
headingPrefixLength : String -> Int -> Int
headingPrefixLength source row =
    let
        sourceLine =
            getSourceLine source row
    in
    case Regex.findAtMost 1 headingPrefixRegex sourceLine of
        match :: _ ->
            String.length match.match

        [] ->
            -- Setext heading or fallback: no prefix
            0


headingPrefixRegex : Regex
headingPrefixRegex =
    Regex.fromString "^ {0,3}#{1,6}[ \\t]+"
        |> Maybe.withDefault Regex.never


{-| Compute the blockquote prefix width for a given source line.
-}
blockQuotePrefixWidth : String -> Int -> Int
blockQuotePrefixWidth source row =
    let
        sourceLine =
            getSourceLine source row
    in
    case Regex.findAtMost 1 blockQuotePrefixRegex sourceLine of
        match :: _ ->
            String.length match.match

        [] ->
            2


blockQuotePrefixRegex : Regex
blockQuotePrefixRegex =
    Regex.fromString "^ {0,3}>[ ]?"
        |> Maybe.withDefault Regex.never


{-| Get a 1-based source line from the original source string.
-}
getSourceLine : String -> Int -> String
getSourceLine source row =
    source
        |> String.split "\n"
        |> List.drop (row - 1)
        |> List.head
        |> Maybe.withDefault ""
```

- [ ] **Step 10: Run all tests**

Run: `cd ../grasp-backend-markdown-inline-regions && pnpm run test`
Expected: All inline region tests pass. Existing tests pass. If any expected values are off by 1, adjust test expectations based on actual offsets (verify by hand).

- [ ] **Step 11: Build the project**

Run: `cd ../grasp-backend-markdown-inline-regions && pnpm run buildnonoptimized`
Expected: successful build.

- [ ] **Step 12: Commit**

```bash
git add packages/markdown/src/Markdown/InlineParser.elm packages/markdown/src/Markdown/RawBlock.elm packages/markdown/src/Markdown/Block.elm tests/InlineRegionTest.elm
git commit -m "feat: compute inline source regions in assignRegions"
```

---

### Task 3: Populate `ParseResult.wikilinks`

**Files:**
- Modify: `packages/markdown/src/Markdown/Block.elm`
- Test: `tests/InlineRegionTest.elm`

- [ ] **Step 1: Write failing test**

Add to `tests/InlineRegionTest.elm`:

```elm
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ../grasp-backend-markdown-inline-regions && pnpm run test`
Expected: fails because `wikilinks` is `Dict.empty`.

- [ ] **Step 3: Implement `collectWikilinks`**

In `Block.elm`, update the `SourceLocation` import to include `toComparableRegion`:

```elm
import SourceLocation exposing (ComparableRegion, Region, toComparableRegion)
```

Add:

```elm
collectWikilinks : Block b i -> List ( ComparableRegion, WikilinkData )
collectWikilinks block =
    queryInlines
        (\(Inline { content, region }) ->
            case content of
                Wikilink data ->
                    [ ( toComparableRegion region, data ) ]

                _ ->
                    []
        )
        block
```

- [ ] **Step 4: Wire it into `parse`**

Replace `wikilinks = Dict.empty` with:

```elm
wikilinks =
    blocks
        |> List.concatMap collectWikilinks
        |> Dict.fromList
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ../grasp-backend-markdown-inline-regions && pnpm run test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add packages/markdown/src/Markdown/Block.elm tests/InlineRegionTest.elm
git commit -m "feat: populate ParseResult.wikilinks from inline regions"
```

---

### Task 4: Cleanup and docs

**Files:**
- Modify: `packages/markdown/src/Markdown/RawBlock.elm` (cleanup)
- Modify: `packages/markdown/src/Markdown/InlineParser.elm` (cleanup)
- Modify: `CLAUDE.md`
- Modify: `TODO.md`

- [ ] **Step 1: Clean up unused code in InlineParser.elm**

Check if `wrapInline` is still used. It should be kept if `walk` uses it (for inline transformations that create new nodes). If walk uses `Inline { content = ..., region = ... }` directly, `wrapInline` can be removed.

- [ ] **Step 2: Verify the build**

Run: `cd ../grasp-backend-markdown-inline-regions && pnpm run buildnonoptimized`
Expected: successful build with no Elm compiler warnings about unused code.

- [ ] **Step 3: Update CLAUDE.md**

Change:
```
The parser produces a typed AST with source regions on block nodes (inline regions
are not yet computed).
```
To:
```
The parser produces a typed AST with source regions on both block and inline nodes.
Block IDs and wikilinks are extracted at parse time.
```

Remove the note about wikilinks not being aggregated.

- [ ] **Step 4: Run the dev server and verify visualization**

Run: `cd ../grasp-backend-markdown-inline-regions && pnpm run dev`

Open http://localhost:8015 in a browser. Load the `wikilinks.md` test file. Verify:
- Inline nodes show non-zero regions in the AST panel
- Hovering over inline nodes highlights the correct source text
- Clicking inline nodes scrolls to the correct position

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs: update CLAUDE.md for inline region tracking, clean up unused code"
```

---

## Implementation Notes

- **`wrapInline` still exists** for use in `walk` transformations (not initial parsing). Transformation-created nodes get `placeholderRegion` — acceptable since transformations don't have source positions.
- **Setext headings:** `headingPrefixLength` returns 0 for setext headings (no `#` on the first line). Content starts at col 1.
- **End positions are exclusive:** An inline at `"Hello"` (5 chars) starting at col 1 has region `{row: 1, col: 1} → {row: 1, col: 6}`. Consistent with block regions.
- **`parseBlockStructure` has no `Options` parameter** because the block structure pipeline (`String.lines >> incorporateLines >> parseReferences`) doesn't depend on options. Options are only needed for inline parsing.
- **`textAsParagraph` flag** is `True` at the top level and for blockquote/custom children, and `isLoose` for list items. This preserves tight-list behavior where paragraphs become `PlainInlines`.
