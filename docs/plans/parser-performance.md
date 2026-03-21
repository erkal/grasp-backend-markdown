# Parser Performance Optimization Plan

> **For agentic workers:** Execute tasks sequentially. For each task: implement the fix, run `pnpm run bench` and `pnpm test`, commit with the benchmark result in the commit message.

**Goal:** Squeeze maximum performance out of the markdown parser before implementing SegmentCache.

**Architecture:** Targeted fixes across the parser pipeline — eliminate unnecessary regex calls, reduce allocations, merge passes. Each task is independent and benchmarked separately.

**Tech Stack:** Elm 0.19.1, elm-test, `pnpm run bench` (Node-based, `--optimize`, 5 warmup + 20 measured iterations)

**Baseline (Node, `--optimize`, median after warmup):**
```
1x  (735 lines)     2.8 ms
5x  (3.7K lines)    10.4 ms
50x (37K lines)     118 ms
```

---

## Tier 1 — High impact, easy

### Task 1: Fast-path guard for `formatStr`

`formatStr` runs 4 regex replacements (escapes, entities, decimals, hexadecimals) on every plain-text segment, even when the text contains no `\` or `&`.

**Files:**
- Modify: `packages/markdown/src/Markdown/Helpers.elm:123-128`

- [x] **Step 1: Add String.contains guard before the 4 regex passes**

```elm
formatStr : String -> String
formatStr str =
    if not (String.contains "\\" str || String.contains "&" str) then
        str

    else
        replaceEscapable str
            |> Entity.replaceEntities
            |> Entity.replaceDecimals
            |> Entity.replaceHexadecimals
```

- [x] **Step 2: Run tests**

Run: `pnpm test`

- [x] **Step 3: Run benchmark, record result**

Run: `pnpm run bench`

- [x] **Step 4: Commit with benchmark result**

```
perf: fast-path guard in formatStr — skip 4 regexes when no \ or &
```

---

### Task 2: Replace regex with Char tests in `charFringeRank`

`charFringeRank` converts a `Char` to a `String`, then calls two regexes (`spaceRegex`, `punctuationRegex`) on that 1-character string. Called twice per `*` or `_` token.

**Files:**
- Modify: `packages/markdown/src/Markdown/InlineParser.elm:536-569`

- [x] **Step 1: Replace charFringeRank with direct Char tests**

The `spaceRegex` matches `\s` (whitespace). The `punctuationRegex` matches `[!-#%-*,-/:;?@[-]_{}-]` (ASCII punctuation). Replace with:

```elm
charFringeRank : Char -> Int
charFringeRank char =
    if isWhitespace char then
        0

    else if isPunctuation char then
        1

    else
        2


isWhitespace : Char -> Bool
isWhitespace c =
    c == ' ' || c == '\t' || c == '\n' || c == '\u{000B}' || c == '\u{000C}' || c == '\r'


isPunctuation : Char -> Bool
isPunctuation c =
    let
        code =
            Char.toCode c
    in
    -- ASCII punctuation ranges: !-# (33-35), %-* (37-42), ,-/ (44-47),
    -- : and ; (58-59), ? and @ (63-64), [-] (91-93), _ (95), { (123), } (125)
    (code >= 33 && code <= 35)
        || (code >= 37 && code <= 42)
        || (code >= 44 && code <= 47)
        || (code >= 58 && code <= 59)
        || (code >= 63 && code <= 64)
        || (code >= 91 && code <= 93)
        || code == 95
        || code == 123
        || code == 125
```

Remove `containSpace`, `spaceRegex`, `containPunctuation`, `punctuationRegex` if they become unused.

- [x] **Step 2: Run tests**
- [x] **Step 3: Run benchmark, record result**
- [x] **Step 4: Commit with benchmark result**

---

### Task 3: Replace `checkBlankLine` regex with `String.trim`

`checkBlankLine` uses `Regex.findAtMost 1 blankLineRegex rawLine` where `blankLineRegex = "^\\s*$"`. Called on every non-alpha line.

**Files:**
- Modify: `packages/markdown/src/Markdown/RawBlock.elm:224-229`

- [x] **Step 1: Replace regex with String.trim check**

```elm
checkBlankLine : ( String, List (RawBlock b i) ) -> Result ( String, List (RawBlock b i) ) (List (RawBlock b i))
checkBlankLine ( rawLine, ast ) =
    if String.isEmpty (String.trim rawLine) then
        Result.Ok (parseBlankLine ast rawLine)

    else
        Result.Err ( rawLine, ast )
```

Also update `parseBlankLine` to accept a `String` instead of `Regex.Match`:

```elm
parseBlankLine : List (RawBlock b i) -> String -> List (RawBlock b i)
parseBlankLine ast blankStr =
    ...
```

This affects `addBlankLineToListBlock` too — it currently passes a `Regex.Match`. Update to pass the raw string. The `.match` field of the regex match was just the blank line text.

Also update `calcListIndentLength` (line ~737) which calls `Regex.contains blankLineRegex rawLine` — replace with `String.isEmpty (String.trim rawLine)`.

- [x] **Step 2: Run tests**
- [x] **Step 3: Run benchmark, record result**
- [x] **Step 4: Commit with benchmark result**

---

### Task 4: Replace emoji regex with `String.contains ":"` in `hasExtendedSyntax`

The last check in `hasExtendedSyntax` is `Regex.contains emojiRegex str`. This runs a full regex scan on every inline text segment that has no other extended syntax.

**Files:**
- Modify: `packages/markdown/src/Markdown/InlineExtensions.elm:205`

- [x] **Step 1: Replace the regex check with String.contains**

```elm
hasExtendedSyntax str =
    String.contains "~~" str
        || String.contains "http" str
        || String.contains "[^" str
        || String.contains "==" str
        || String.contains "@" str
        || String.contains "$" str
        || String.contains ":" str
```

This accepts slight false positives (colons without emoji syntax), which is fine — the downstream `expandSegment` handles no-match gracefully.

- [x] **Step 2: Run tests**
- [x] **Step 3: Run benchmark, record result**
- [x] **Step 4: Commit with benchmark result**

---

## Tier 2 — Medium impact, targeted

### Task 5: Skip `parseReferencesHelp` regex for non-reference paragraphs

`parseReferencesHelp` joins all paragraph lines and runs `refRegex` on every paragraph. Most paragraphs aren't reference definitions.

**Files:**
- Modify: `packages/markdown/src/Markdown/RawBlock.elm:904-927`

- [x] **Step 1: Guard on first line starting with `[`**

The reversed list stores the last source line at the head. Reference definitions start with `[` at the beginning of the paragraph (which is the LAST element in the reversed list). Check this before joining:

```elm
Paragraph lines _ ->
    let
        -- Reference definitions start with [ on the first source line
        -- (which is the last element in reversed list)
        mightBeRef =
            case List.Extra.last lines of
                Just firstLine ->
                    String.startsWith "[" (String.trimLeft firstLine)

                Nothing ->
                    False
    in
    if not mightBeRef then
        ( refs, block :: parsedAST )

    else
        -- existing join + parseReference logic
        ...
```

Note: `List.Extra.last` is O(n) on the reversed list. For short paragraphs (1-5 lines) this is fine. For a faster check, you could store the first line separately, but that changes the type.

- [x] **Step 2: Run tests**
- [x] **Step 3: Run benchmark, record result**
- [x] **Step 4: Commit with benchmark result**

---

### Task 6: Eliminate double `String.lines` — share source line array

`parseBlockStructure` calls `String.lines` to split the document. Then `Block.parse` calls `String.split "\n" |> Array.fromList` on the same string. The document is split into lines twice.

**Files:**
- Modify: `packages/markdown/src/Markdown/RawBlock.elm` — return the lines from `parseBlockStructure`
- Modify: `packages/markdown/src/Markdown/Block.elm:123-135` — accept lines instead of recomputing

- [x] **Step 1: Change `parseBlockStructure` to also return the source lines**

```elm
parseBlockStructure : String -> ( References, List (RawBlock b i), Array String )
parseBlockStructure str =
    let
        lines =
            String.lines str

        sourceLines =
            Array.fromList lines
    in
    lines
        |> (\a -> incorporateLines a [])
        |> parseReferences Dict.empty
        |> (\( refs, blocks ) -> ( refs, blocks, sourceLines ))
```

Update the exposed API accordingly (add `Array` import, update the `exposing` list if needed).

- [x] **Step 2: Update `Block.parse` to use the shared array**

```elm
parse maybeOptions str =
    let
        options =
            Maybe.withDefault defaultOptions maybeOptions

        ( refs, rawBlocks, sourceLines ) =
            RawBlock.parseBlockStructure str

        ( blocks, _ ) =
            assignRegions options refs sourceLines True 1 0 rawBlocks
        ...
```

Remove the duplicate `str |> String.split "\n" |> Array.fromList`.

- [x] **Step 3: Run tests**
- [x] **Step 4: Run benchmark, record result**
- [x] **Step 5: Commit with benchmark result**

---

### Task 7: Combine `collectBlockIds` and `collectWikilinks` into one traversal

Both functions walk the entire block tree independently with `List.concatMap`.

**Files:**
- Modify: `packages/markdown/src/Markdown/Block.elm:140-150, 439-528`

- [x] **Step 1: Create a combined collection function**

```elm
collectBlockIdsAndWikilinks :
    List (Block b i)
    -> ( List ( String, Region ), List ( Region, WikilinkData ) )
collectBlockIdsAndWikilinks blocks =
    blocks
        |> List.foldl
            (\block ( ids, wls ) ->
                let
                    ( newIds, newWls ) =
                        collectFromBlock block
                in
                ( newIds ++ ids, newWls ++ wls )
            )
            ( [], [] )
```

Inline the logic from `collectBlockIds` and `collectWikilinks` into `collectFromBlock`, walking children once.

- [x] **Step 2: Update `parse` to use the combined function**

```elm
( blockIds, wikilinks ) =
    let
        ( idPairs, wlPairs ) =
            collectBlockIdsAndWikilinks blocks
    in
    ( Dict.fromList idPairs, Dict.fromList wlPairs )
```

- [x] **Step 3: Run tests**
- [x] **Step 4: Run benchmark, record result**
- [x] **Step 5: Commit with benchmark result**

---

### Task 8: Replace `String.words >> List.Extra.last` in `extractBlockId`

`lastWord` allocates the full word list just to get the last word.

**Files:**
- Modify: `packages/markdown/src/Markdown/Block.elm:495-499`

- [x] **Step 1: Scan backward to find last word**

```elm
lastWord : String -> Maybe String
lastWord str =
    let
        trimmed =
            String.trimRight str

        len =
            String.length trimmed
    in
    if len == 0 then
        Nothing

    else
        let
            spaceIdx =
                lastIndexOf ' ' (len - 1) trimmed
        in
        Just (String.dropLeft (spaceIdx + 1) trimmed)


lastIndexOf : Char -> Int -> String -> Int
lastIndexOf char idx str =
    if idx < 0 then
        -1

    else if String.slice idx (idx + 1) str == String.fromChar char then
        idx

    else
        lastIndexOf char (idx - 1) str
```

Note: `extractBlockId` already calls `String.trimRight` before `lastWord`. Avoid double-trimming.

- [x] **Step 2: Run tests**
- [x] **Step 3: Run benchmark, record result**
- [x] **Step 4: Commit with benchmark result**

---

### ~~Task 9: Remove redundant `List.sortBy` in `organizeMatches`~~ SKIP

**Do not implement.** Matches from different TTM passes (code, html, wikilink, link, emphasis, linebreak) are interleaved in accumulation order, NOT positional order. The sort is required for correctness. V8's TimSort is O(n) on nearly-sorted input, so the cost is low.

---

## Tier 3 — Lower impact / more effort

### Task 10: Replace `GfmTable.splitOnUnescapedPipes` `String.toList` with index scan

`String.toList` allocates a `List Char` of the entire table row.

**Files:**
- Modify: `packages/markdown/src/Markdown/GfmTable.elm:153-179`

- [x] **Step 1: Rewrite using `String.indexes` and `String.slice`**

Find pipe positions with `String.indexes "|"`, filter out escaped ones (preceded by `\`), then `String.slice` between them. This avoids the `List Char` allocation entirely.

- [x] **Step 2: Run tests**
- [x] **Step 3: Run benchmark, record result**
- [x] **Step 4: Commit with benchmark result**

---

### Task 11: `Heading` line count — avoid `String.lines` allocation

`rawBlockLineCount` for `Heading` calls `String.lines rawText |> List.length`.

**Files:**
- Modify: `packages/markdown/src/Markdown/Block.elm:353-371`

- [x] **Step 1: Count newlines instead of splitting**

```elm
RawBlock.Heading rawText _ _ ->
    let
        newlineCount =
            String.indexes "\n" rawText |> List.length
    in
    if newlineCount > 0 then
        newlineCount + 2  -- multi-line setext: text lines + underline

    else
        1
```

- [x] **Step 2: Run tests**
- [x] **Step 3: Run benchmark, record result**
- [x] **Step 4: Commit with benchmark result**

---

### Task 12: `calcListIndentLength` — remove redundant blank line regex

`calcListIndentLength` calls `Regex.contains blankLineRegex rawLine` even though the same check was done earlier.

**Files:**
- Modify: `packages/markdown/src/Markdown/RawBlock.elm:722-752`

- [x] **Step 1: Replace with String.trim check**

```elm
|| String.isEmpty (String.trim rawLine)
```

(This may already be fixed if Task 3 removed `blankLineRegex` entirely. If so, this task is a no-op.)

- [x] **Step 2: Run tests**
- [x] **Step 3: Run benchmark, record result**
- [x] **Step 4: Commit with benchmark result**

---

## After all tasks

Run the final benchmark and compare against the baseline:

```
Baseline:        1x = 3.2 ms,  5x = 11.5 ms,  50x = 125.5 ms
After all fixes: 1x = 2.9 ms,  5x = 10.0 ms,  50x = 108.2 ms  (−14%)
```

All tasks complete. Task 9 skipped (sort required for correctness). Task 12 was a no-op (blankLineRegex already removed in Task 3).
