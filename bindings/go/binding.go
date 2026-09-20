// Package tree_sitter_mql5 exposes the tree-sitter grammar for MQL5 to Go
// consumers (gortex).
//
// The parser C sources live in ../../src: upstream mskelton/tree-sitter-mql5,
// which is tree-sitter-cpp plus one grammar rule (the MQL5 `input` storage
// class). The upstream external scanner (src/scanner.cc, C++) is deliberately
// not compiled: it only recognizes C++ raw string literals, a construct MQL5
// does not have, so scanner_stub.c in this directory satisfies the external
// scanner symbols parser.c references while keeping the build C-only.
package tree_sitter_mql5

// #cgo CFLAGS: -I${SRCDIR}/../../src -std=c11 -fPIC
// #include "../../src/parser.c"
import "C"

import "unsafe"

// Language returns the tree-sitter Language for MQL5.
func Language() unsafe.Pointer {
	return unsafe.Pointer(C.tree_sitter_mql5())
}
