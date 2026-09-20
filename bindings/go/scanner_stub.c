// Stub external scanner for the MQL5 tree-sitter grammar.
//
// parser.c references the five external-scanner symbols declared in
// tree_sitter/parser.h. Upstream (mskelton/tree-sitter-mql5) ships them in
// src/scanner.cc — C++ code inherited from tree-sitter-cpp that recognizes
// C++ raw string literals (R"delim(...)delim"). MQL5 has no raw string
// literals, so the scanner can never legitimately match: this C stub
// satisfies the symbols while keeping the Go build free of a C++
// toolchain. With a scan() that always returns false, the parser falls
// back to its non-scanner alternatives and any R"(...)" input produces
// ERROR nodes — the correct outcome for a non-MQL5 construct.
#include <tree_sitter/parser.h>

void *tree_sitter_mql5_external_scanner_create(void) { return 0; }

void tree_sitter_mql5_external_scanner_destroy(void *payload) {
  (void)payload;
}

bool tree_sitter_mql5_external_scanner_scan(void *payload, TSLexer *lexer,
                                            const bool *valid_symbols) {
  (void)payload;
  (void)lexer;
  (void)valid_symbols;
  return false;
}

unsigned tree_sitter_mql5_external_scanner_serialize(void *payload,
                                                     char *buffer) {
  (void)payload;
  (void)buffer;
  return 0;
}

void tree_sitter_mql5_external_scanner_deserialize(void *payload,
                                                   const char *buffer,
                                                   unsigned length) {
  (void)payload;
  (void)buffer;
  (void)length;
}
