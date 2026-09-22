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

## Pending acknowledgments (tasks in odd/tasks/community-hardening.md)

- T4 MQL builtin catalogs + generated highlight queries —
  m0n99/tree-sitter-mql5 — https://github.com/m0n99/tree-sitter-mql5
- T5 modern base migration —
  hydralynxtrading-a11y/tree-sitter-mql5, m0n99/tree-sitter-mql5,
  MichalBPL/tree-sitter-mql5 (https://github.com/MichalBPL/tree-sitter-mql5)
- T6 napi-rs Node binding —
  khayashi4337/tree-sitter-mql5 — https://github.com/khayashi4337/tree-sitter-mql5
