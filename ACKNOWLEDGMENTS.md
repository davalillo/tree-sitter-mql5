# Acknowledgments

This grammar stands on the shoulders of the tree-sitter and MQL communities.
Attribution per contribution, with the exact source of each idea.

## Foundation

- **mskelton/tree-sitter-mql5** — https://github.com/mskelton/tree-sitter-mql5
  Base of this project (ISC): tree-sitter-cpp extension with the MQL5 `input`
  storage class. Full git history preserved here; PRs #14 and #15 (merged)
  returned the `input_group` rule and MQL4 packaging to upstream.

## Grammar contributions (inspiration → rule)

- **export_specifier** (`void f() export { }`)
  Inspiration: hydralynxtrading-a11y/tree-sitter-mql5 —
  https://github.com/hydralynxtrading-a11y/tree-sitter-mql5 (grammar.js, 2026-09-18)

- **input_group optional trailing semicolon**
  Inspiration: hydralynxtrading-a11y/tree-sitter-mql5 —
  https://github.com/hydralynxtrading-a11y/tree-sitter-mql5 (grammar.js, 2026-09-18)

- **MISSING-node counting in the regression harness**
  Inspiration: hydralynxtrading-a11y/tree-sitter-mql5 —
  https://github.com/hydralynxtrading-a11y/tree-sitter-mql5 (sweep.ps1 treats
  ERROR and MISSING alike, 2026-09-18)

- **UTF-16LE handling in the regression harness**
  Inspiration: hydralynxtrading-a11y/tree-sitter-mql5 —
  https://github.com/hydralynxtrading-a11y/tree-sitter-mql5 (sweep.ps1 encoding
  detection, 2026-09-18)

- **MQL builtin catalogs + generated highlight queries** (T4)
  Inspiration: m0n99/tree-sitter-mql5 —
  https://github.com/m0n99/tree-sitter-mql5 (build-highlights.js generator
  technique + vendored catalogs queries/mql5/{mql5_constants,mql5_functions}.json,
  ISC, main branch 2026-01; catalog data ultimately derived from the official
  mql5.com documentation). Taken: the catalogs verbatim (see
  queries/CATALOGS.md) and the marker-based block regeneration idea; our
  scripts/build-highlights.js is a local no-network port that emits `#match?`
  alternations because tree-sitter CLI 0.20.8 ignores `#any-of?`.

- **modern base migration to tree-sitter-cpp v0.23.4 + CLI 0.25 (T5)**
  Inspirations:
  hydralynxtrading-a11y/tree-sitter-mql5 —
  https://github.com/hydralynxtrading-a11y/tree-sitter-mql5 (tree-sitter-cpp
  0.23 + CLI 0.26, scanner.c C-only, 2026-09-18); m0n99/tree-sitter-mql5 —
  https://github.com/m0n99/tree-sitter-mql5 (submodule bump + C-only scanner,
  2026-01); MichalBPL/tree-sitter-mql5 —
  https://github.com/MichalBPL/tree-sitter-mql5 (tree-sitter-cpp ^0.23.4 +
  CLI ^0.25, 2026-03)

## Pending acknowledgments (tasks in odd/tasks/community-hardening.md)

- T6 napi-rs Node binding —
  khayashi4337/tree-sitter-mql5 — https://github.com/khayashi4337/tree-sitter-mql5
