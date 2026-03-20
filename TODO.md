# TODO

## Parser

- [ ] Compute source regions for inline nodes
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

## Integration

- [ ] Decide how grasp consumes this repo (submodule, symlink, copy, or other)
- [ ] Wire grasp to use extracted parser
- [ ] Remove `packages/markdown/` and `packages/source-location/` from grasp
