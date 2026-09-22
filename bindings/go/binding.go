// Package tree_sitter_mql5 exposes the tree-sitter grammar for MQL5 to Go
// consumers (gortex).
//
// The parser C sources live in ../../src: tree-sitter-cpp 0.23 plus the MQL5
// extension rules. The external scanner (../../src/scanner.c, C-only) is
// compiled alongside parser.c via cgo below; it recognizes the C++ raw
// string literal tokens the grammar declares as externals, which MQL5 code
// never legitimately produces.
package tree_sitter_mql5

// #cgo CFLAGS: -I${SRCDIR}/../../src -std=c11 -fPIC
// #include "../../src/parser.c"
// #include "../../src/scanner.c"
import "C"

import "unsafe"

// Language returns the tree-sitter Language for MQL5.
func Language() unsafe.Pointer {
	return unsafe.Pointer(C.tree_sitter_mql5())
}
