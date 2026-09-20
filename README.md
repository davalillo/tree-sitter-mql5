# tree-sitter-mql5 (gortex fork)

Fork of [mskelton/tree-sitter-mql5](https://github.com/mskelton/tree-sitter-mql5)
(ISC) maintained for [Gortex](https://github.com/davalillo/gortex). This fork
adds Go bindings and a small set of corpus-driven grammar extensions over the
upstream grammar (which is tree-sitter-cpp plus the MQL5 `input` storage
class):

- `sinput` storage class (MQL5 static input)
- `interface_specifier` for MQL5 `interface` declarations
- `color_literal` (`C'255,0,0'`) and `datetime_literal` (`D'2024.01.01'`) —
  MQL-native literals absent from C++

## Go usage

```go
import "github.com/davalillo/tree-sitter-mql5/bindings/go"

lang := sitter.NewLanguage(tree_sitter_mql5.Language())
```

Note: the upstream external scanner (`src/scanner.cc`, C++ raw string
literals) is intentionally not compiled — MQL5 has no raw string literals.
`bindings/go/scanner_stub.c` satisfies the scanner symbols the generated
parser references, keeping the Go build C-only.

## Regenerating the parser

```
npm install --allow-scripts   # tree-sitter-cli, tree-sitter-cpp (git deps)
tree-sitter generate          # requires tree-sitter-cli 0.20.x-era DSL
tree-sitter test
```

The `tree-sitter-cpp` submodule (pinned) and a matching `tree-sitter-c`
(circa July 2023, defines `_expression`) must be resolvable as
`node_modules/tree-sitter-cpp` / `node_modules/tree-sitter-c`.

Macro-expansion-only constructs (declarations that are only valid after
`#define` expansion) intentionally remain ERROR nodes — same boundary the
companion mql-language-server enforces with its macro layer.
