# TODO

## Parser

- [ ] Full Obsidian Flavored Markdown support (comments, frontmatter, callouts, strikethrough, highlights, tags)
- [ ] Multi-line footnote definitions (indented continuation)
- [ ] Full emoji dictionary (compare against GitHub's complete set)

## Visualization

- [ ] Hover on AST node highlights source region in editor (wired, needs visual polish)
- [ ] Click AST node scrolls editor to source location (wired, needs visual polish)
- [ ] Collapsible AST tree nodes
- [ ] Search/filter in AST panel

## Testing

- [x] Block parser tests
- [x] Inline parser tests
- [x] Block ID extraction tests
- [x] Wikilink parsing tests
- [x] Region tracking tests
- [ ] Edge case tests (deeply nested structures, malformed input)
- [ ] Roundtrip property tests

## Integration

- [ ] Decide how grasp consumes this repo (submodule, symlink, copy, or other)
- [ ] Wire grasp to use extracted parser
- [ ] Remove `packages/markdown/` and `packages/source-location/` from grasp
