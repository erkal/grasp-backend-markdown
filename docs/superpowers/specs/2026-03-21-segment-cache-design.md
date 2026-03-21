# SegmentCache — Content-Addressed Incremental Computation Over Document Segments

## Problem

Parsing a full document on every keystroke is wasteful. Most edits touch one block.
The parser re-parses 99 unchanged blocks to get to the 1 that changed.

We want to cache per-block results and only reprocess blocks whose content changed.

This applies to any tool that processes a document block-by-block: parsers, formatters,
linters, spell checkers. The mechanism should be reusable across languages and tools.

## Core Idea

**Content-addressed caching.** The cache key is the block's text content. Same text, same
result. No change tracking, no range mapping, no invalidation logic.

On each document edit:

1. **Split** the document into segments at stable boundaries (blank lines, etc.)
2. **Extract context** — global information that affects all segments (e.g., reference
   definitions for markdown, import block for Elm)
3. **Look up** each segment's text in the previous results. Cache hit → reuse. Miss → process.
4. **Assemble** the full result from cached + fresh segment results.

If the context changed since the last step, all segments miss (full reprocess). Context
changes are rare in practice (editing a reference definition, changing imports), so this
is almost always the fast path.

## Design

### Types

```elm
type alias Config ctx result =
    { split : String -> List { text : String, startLine : Int }
    , context : String -> ctx
    , process : ctx -> String -> result
    }

type Cache ctx result
    = Cache
        { ctx : Maybe ctx
        , blocks : List { text : String, startLine : Int, result : result }
        }
```

- `Config` is provided by the consumer. Three pure functions, each independently testable.
- `Cache` is opaque. The consumer cannot manipulate internals.
- `ctx` must support Elm's `==` operator — no functions, no `Json.Decode.Value`.
  Data types (`String`, `Dict`, `List`, records, custom types) are all fine.

### API

```elm
empty : Cache ctx result

step : Config ctx result -> String -> Cache ctx result -> Cache ctx result

toList : Cache ctx result -> List { text : String, startLine : Int, result : result }
```

Five exports total: `Config`, `Cache`, `empty`, `step`, `toList`.

### Algorithm (`step`)

```elm
step config document (Cache old) =
    let
        segments =
            config.split document

        newCtx =
            config.context document

        reusable =
            if Just newCtx == old.ctx then
                old.blocks
                    |> List.map (\b -> ( b.text, b.result ))
                    |> Dict.fromList
            else
                Dict.empty
    in
    Cache
        { ctx = Just newCtx
        , blocks =
            segments
                |> List.map
                    (\seg ->
                        { text = seg.text
                        , startLine = seg.startLine
                        , result =
                            reusable
                                |> Dict.get seg.text
                                |> Maybe.withDefault (config.process newCtx seg.text)
                        }
                    )
        }
```

~15 lines of logic.

## Structural Guarantees

These properties hold by construction, not by discipline:

**No stale cache hits.** The cache key is text content. Changed text = automatic miss.
No invalidation logic that could be forgotten or applied incorrectly.

**No stale cross-block results.** Context change empties the reusable dict entirely.
Binary decision: full dict or empty dict. No partial invalidation to get wrong.

**No stale positions.** `split` recomputes segment positions from the document on every
step. No accumulated deltas. No mapped positions. No drift.

**No position-dependent caching.** `process` receives `ctx` and `String` — no `startLine`.
The result is guaranteed position-independent. The type signature makes it impossible to
accidentally embed absolute positions in cached results.

**No cache growth.** The reusable dict is rebuilt from old blocks each step. Old entries
not present in the new segment list are dropped. The cache holds exactly one `text` +
`result` per current block — equivalent to holding the current document's full parse
result, which any parser would hold anyway.

**Undo correctness.** Content-addressed: same text → same result, regardless of edit
history. Undo restores text → cache hit.

**Pure and deterministic.** Same document + same old state → same new state. Always.

## What the Consumer Provides

### `split : String -> List { text : String, startLine : Int }`

Segments the document at stable boundaries. Language-specific. `startLine` is 1-based
(first line of the document is line 1).

**Separator handling:** Blank-line separators are excluded from segment `text`. They sit
between segments. Each segment's `startLine` accounts for preceding separators. Example
for a document with blocks at lines 1-3, 5-8, 10-12:

```
split doc =
    [ { text = "line1\nline2\nline3", startLine = 1 }
    , { text = "line5\nline6\nline7\nline8", startLine = 5 }
    , { text = "line10\nline11\nline12", startLine = 10 }
    ]
```

The `split` function only needs to identify where blocks start and end. It does not need
to parse block content. Separator lines (blank lines between blocks) are not part of any
segment's text.

| Language | Strategy |
|----------|----------|
| Markdown | Blank lines, respecting fenced code blocks, block quotes, and list items (these can contain internal blank lines) |
| Elm | Blank lines where next non-blank line starts at column 0, respecting multi-line strings and comments |
| Python | Blank lines at indentation level 0 |
| Generic | Any blank line |

Must be cheap — much cheaper than full parsing. It's a line scan with minimal state
(e.g., "am I inside a fenced code block?").

Must be consistent with the parser: if `split` says "this is one block," the parser must
produce a correct AST when given that block's text in isolation. If the parser would
interpret the text differently in context (e.g., a setext heading requires a preceding
paragraph), the `split` function must keep those lines together in one segment.

### `context : String -> ctx`

Extracts global information that affects processing of all segments. The context is
compared for equality between steps. If it changed, all segments are reprocessed.

| Language | Context | Changes rarely? |
|----------|---------|-----------------|
| Markdown | Reference definitions (`[label]: url`) | Yes |
| Elm | Import block text | Yes |
| Generic linter | Config/rules | Almost never |
| Formatter | `()` (no cross-block deps) | Never |

For tools with no cross-block dependencies, use `context = \_ -> ()`. The `()` context
always compares equal, so the cache always works.

### `process : ctx -> String -> result`

The actual work. Receives global context and one segment's text. Returns the result with
**block-relative** regions (starting at line 1, column 1).

Must be a pure function: same inputs → same output. (Enforced by Elm's type system.)

## What the Consumer Does After

### Region offsetting

Cached results have block-relative regions. Absolute regions are computed at read time:

```
absoluteLine = block.startLine + relativeLine - 1
```

When a block shifts (because a block above changed size), only its `startLine` changes.
The cached AST is untouched. One integer update per shifted block.

### Assembly

Combining per-block results into a document-level result. Language-specific.

```elm
-- Markdown: concatenate block ASTs, merge dicts
assembleParseResult : List { startLine : Int, result : BlockResult } -> ParseResult
assembleParseResult blocks =
    { blocks = blocks |> List.concatMap (\b -> offsetRegions b.startLine b.result.blocks)
    , blockIds = blocks |> List.concatMap (.result >> .blockIds) |> Dict.fromList
    , wikilinks = blocks |> List.concatMap (.result >> .wikilinks) |> Dict.fromList
    }

-- Elm format: join formatted texts
assembleFormatted : List { startLine : Int, result : String } -> String
assembleFormatted blocks =
    blocks |> List.map .result |> String.join "\n\n"
```

### Delta computation (optional)

Compare old and new `toList` outputs to determine what changed:

```elm
computeDelta :
    List { text : String, startLine : Int, result : result }
    -> List { text : String, startLine : Int, result : result }
    -> { modified : List Int, shifted : List Int }
computeDelta oldBlocks newBlocks =
    -- Compare by text content and startLine
    ...
```

This is outside the core. The consumer computes it when downstream needs structured
change information (e.g., Grasp graph updates).

## Concrete Instantiations

### Markdown parsing

```elm
markdownConfig : Config References BlockParseResult
markdownConfig =
    { split = splitMarkdownAtBlankLines
    , context = extractReferenceDefinitions
    , process = \refs text -> parseBlockWithRefs refs text
    }

-- BlockParseResult holds blocks, blockIds, and wikilinks for one segment.
-- Assembly merges these into the document-level ParseResult.
```

**Migration note:** The current `Markdown.Block.parse` takes the full document and
produces absolute regions (the `assignRegions` phase threads a running line counter).
To use SegmentCache, the parser must be callable per-block, producing block-relative
regions (starting at line 1). This requires factoring `assignRegions` so it can operate
on a single block's raw-block list with a starting row of 1.

### Elm formatting

```elm
elmFormatConfig : Config () String
elmFormatConfig =
    { split = splitElmDeclarations
    , context = \_ -> ()
    , process = \() text -> formatSingleDeclaration text
    }
```

### Elm linting

```elm
lintConfig : Config String (List Diagnostic)
lintConfig =
    { split = splitElmDeclarations
    , context = extractImportBlock
    , process = \imports text -> lintDeclaration imports text
    }
```

## Performance Characteristics

| Operation | Cost | Frequency |
|-----------|------|-----------|
| `split` (line scan) | O(n) in document chars | Every keystroke |
| `context` (reference scan) | O(n) in document chars | Every keystroke |
| `Dict.fromList` (build reusable) | O(b log b) where b = block count | Every keystroke |
| `Dict.get` per block | O(log b × k) where k = block text length | Every keystroke × b |
| `process` (actual parsing) | Depends on parser | Only for cache misses (typically 1) |

For a 10,000-line document with 100 blocks of typical size (~500 chars): steps 1-4
total ~1-2ms. For documents with very large blocks (5KB+), the Dict string-key
comparisons take proportionally longer. If this becomes a bottleneck, the key could be
changed to a content hash — but this is an optimization, not a design change.

The savings from skipping 99 block parses: 10-100ms+ depending on parser.

## What This Does Not Handle

- **CM6 integration.** This is pure Elm. CM6 sends document text as it already does.
  Block ranges for CM6 decorations are computed from `toList` output by the consumer.
- **Format-dirty tracking.** "Which blocks has the user edited since last format?" is a
  separate concern, tracked by the consumer or CM6.
- **Async processing.** `process` is synchronous. For external tools (elm-format via CLI),
  the consumer wraps the async call.
- **Block identity / stable IDs.** Content is identity. If downstream needs stable IDs
  across structural changes (split/merge), the consumer assigns them.

## Relationship to CM6

SegmentCache is independent of CodeMirror. CM6's role in the broader system:

- **Sends document text on edit** — already does this via `value-changed` event.
- **Receives block ranges from Elm** — for decorations, navigation, format-dirty tracking.
  Computed from `SegmentCache.toList` output.
- **Owns format-dirty state** — tracks which block ranges have been edited since last
  format-clear. Separate from SegmentCache.

The original question was "how to use CM6 for partial parsing." The answer: you don't
need CM6 for the caching part. CM6 does what it already does (sends text). The caching
is a pure Elm concern, 40 lines, no dependencies.
