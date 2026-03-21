# grasp-backend-markdown

Markdown parser backend for Grasp. Pure Elm parser with CodeMirror 6 AST visualization.

## What This Is

A standalone parser that knows markdown. It lives in its own repository, runs entirely in
the browser (no backend process), and knows nothing about Grasp's graph, addressing, chat,
or UI systems.

The parser produces a typed AST with source regions on both block and inline nodes.
Block IDs and wikilinks are extracted at parse time.

## Build Commands

```bash
pnpm install                    # Install dependencies
pnpm run buildnonoptimized      # Build CM6 bundle + Elm (no optimization)
pnpm run build                  # Build CM6 bundle + Elm (optimized)
pnpm run dev                    # Dev server with hot reload
pnpm run test                   # Run elm-test suite
```

## Project Structure

- `packages/markdown/src/` — The parser (Markdown.elm entry point, ~8000 lines across 16 files)
- `packages/source-location/src/` — Region and Position types
- `src/Main.elm` — AST visualization app (CM6 editor + tree view)
- `tests/` — elm-test suite (block parsing, inline parsing, block IDs, wikilinks, regions)
- `test-project/` — Example markdown files for the visualizer
- `codemirror-bundle.js` — CM6 setup with semantic decoration pipeline
- `codemirror-element.js` — Custom HTML element wrapping CM6
- `server.js` — Express dev server (port 8015, serves test-project/ files)

## Parser API

```elm
Markdown.parse : Maybe Options -> String -> ParseResult () ()

type alias ParseResult b i =
    { blocks : List (Block b i)
    , blockIds : Dict String Region
    , wikilinks : Dict ComparableRegion WikilinkData
    }

type Block b i = Block { content : BlockContent b i, region : Region }
type Inline i = Inline { content : InlineContent i, region : Region }
```

## Design Specs

- [SegmentCache](docs/specs/2026-03-21-segment-cache-design.md) — Content-addressed
  incremental block-level parsing. Symlinked from the grasp repo (canonical location:
  `../grasp/docs/specs/`).

## Conventions

Same as the main grasp repo. See the grasp CLAUDE.md for Elm style, git workflow, etc.
