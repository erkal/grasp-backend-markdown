# TODO

## Parser

- [x] Compute source regions for inline nodes
- [ ] Full Obsidian Flavored Markdown support (comments, frontmatter, callouts, strikethrough, highlights, tags)
- [ ] Multi-line footnote definitions (indented continuation)
- [ ] Full emoji dictionary (compare against GitHub's complete set)

## Visualization

- [ ] Hover highlight visual polish (functional after region fix)
- [ ] Click-to-scroll visual polish (functional after region fix)
- [ ] Collapsible AST tree nodes
- [ ] Search/filter in AST panel

## Testing

- [x] Region tracking tests
- [ ] Tests that assert parsed content (not just type labels)
- [ ] Edge case tests (deeply nested structures, malformed input)
- [ ] Roundtrip property tests

## Performance

- [x] Add benchmark suite (`pnpm run bench`)
- [x] Eliminate per-line regex compilation in `indentLine`/`indentLength`
- [x] Add block-parse fast-path for alphabetic lines (skip 8 regex checks)
- [x] Eliminate O(n²) string concat in paragraph/code block building
- [x] Early-exit in `findToken` (O(n) → O(k))
- [ ] Single-pass inline tokenizer (currently 9 separate regex scans per inline parse)
- [ ] Implement SegmentCache for incremental block-level parsing (see [design spec](docs/specs/2026-03-21-segment-cache-design.md))
- [ ] Factor `Markdown.Block.parse` to work per-block with block-relative regions
- [ ] Write `splitMarkdownAtBlankLines` (respecting fences, block quotes, lists)

## Integration

- [ ] Decide how grasp consumes this repo (submodule, symlink, copy, or other)
- [ ] Wire grasp to use extracted parser
- [ ] Remove `packages/markdown/` and `packages/source-location/` from grasp
