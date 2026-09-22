# tree-sitter-mql5

> **Independently maintained since 2026.** This project began as a fork of
> [mskelton/tree-sitter-mql5](https://github.com/mskelton/tree-sitter-mql5) (ISC),
> which extends [tree-sitter-cpp](https://github.com/tree-sitter/tree-sitter-cpp)
> with the MQL5 `input` storage class. Full git history is preserved. The
> upstream has been dormant since 2023 (bot-only commits), so this repository
> is the canonical home going forward; upstream is consulted only if it shows
> human activity. Grammar-inspiration credits: see ACKNOWLEDGMENTS.md (in
> progress) and the extension list below.

Fork of [mskelton/tree-sitter-mql5](https://github.com/mskelton/tree-sitter-mql5)
(ISC) maintained for [Gortex](https://github.com/davalillo/gortex). This fork
adds Go bindings and a small set of corpus-driven grammar extensions over the
upstream grammar (which is tree-sitter-cpp plus the MQL5 `input` storage
class):

- `sinput` storage class (MQL5 static input)
- `interface_specifier` for MQL5 `interface` declarations
- `color_literal` (`C'255,0,0'`) and `datetime_literal` (`D'2024.01.01'`) —
  MQL-native literals absent from C++
- MQL primitive types: `string`, `datetime`, `color`, `uchar`, `ushort`,
  `uint`, `ulong` redefined as `primitive_type` (upstream parses them as
  `type_identifier`, indistinguishable from user classes)
- `input_group` (`input group "Name"`) — its absence degraded every following
  declaration into ERROR nodes in real-code audits
- Parenthesized assignment `(a = b)` — resolved: the base migration to
  tree-sitter-cpp v0.23.4 (CLI 0.25, ABI 15) brings the upstream fix; it now
  parses as a clean `assignment_expression` (corpus tripwire: "parenthesized
  assignment parses")

The grammar targets MQL4, MQL5 and MQH (`.mq4`, `.mq5`, `.mqh`).

## Generated builtin queries

`queries/highlights.scm` contains two generated blocks (between explicit
`; BEGIN/END BUILTIN …` markers) that highlight MQL5 builtin constants
(`INIT_SUCCEEDED`, `MODE_EMA`, …) and functions (`Print`, `iRSI`, …) as
`@constant.builtin` / `@function.builtin`. They are regenerated from the
vendored catalogs in `queries/mql5-{constants,functions}.json` (provenance:
[queries/CATALOGS.md](queries/CATALOGS.md)):

```
npm run build:highlights   # run twice; the second run must be a no-op
```

The catalogs are vendored from [m0n99/tree-sitter-mql5](https://github.com/m0n99/tree-sitter-mql5)
(ISC) and are regenerable; their contents ultimately derive from the official
mql5.com documentation. Do not edit the generated blocks by hand.

## Go usage

```go
import "github.com/davalillo/tree-sitter-mql5/bindings/go"

lang := sitter.NewLanguage(tree_sitter_mql5.Language())
```

Note: the external scanner is C-only (`src/scanner.c`, from the tree-sitter-cpp
v0.23.4 base, symbols renamed `tree_sitter_mql5_*`) and is compiled by every
binding (Node, Rust, Go) — no C++ toolchain and no scanner stub are involved.

## Regenerating the parser

```
npm install --allow-scripts   # tree-sitter-cli, tree-sitter-cpp (git deps)
tree-sitter generate          # requires tree-sitter-cli 0.25.x (ABI 15)
tree-sitter test
```

The pinned `tree-sitter-cpp` submodule (v0.23.4) and a matching
`tree-sitter-c` (v0.23.x, required by cpp 0.23.4's grammar.js) must be
resolvable as `node_modules/tree-sitter-cpp` / `node_modules/tree-sitter-c`
(symlinks; the submodule alone is enough for `tree-sitter-cpp`).

Macro-expansion-only constructs (declarations that are only valid after
`#define` expansion) intentionally remain ERROR nodes — same boundary the
companion mql-language-server enforces with its macro layer.
