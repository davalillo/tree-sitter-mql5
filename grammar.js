const CPP = require("tree-sitter-cpp/grammar")

// Fork extensions over mskelton/tree-sitter-mql5 (which itself adds only
// the MQL5 `input` storage class over tree-sitter-cpp). Extensions here are
// corpus-driven: each rule below corresponds to an MQL5 construct the stock
// grammar parses with ERROR nodes (see the gortex extractor corpus audit).
//   - sinput: MQL5 static-input storage class (same role as `input`).
//   - interface_specifier: MQL5 `interface Name { ... };` declarations.
//     C++ has no `interface` keyword, so the stock grammar mangles these.
//     Modeled exactly like struct_specifier via _class_declaration, so
//     class-body queries (methods, field declarations) apply unchanged.
//   - color_literal / datetime_literal: MQL-native `C'255,0,0'` and
//     `D'2024.01.01 12:00'` literals. C++ has neither; the corpus audit
//     showed they shatter surrounding declarations into ERROR nodes.
//     Added to _expression_not_binary (chained over cpp's own override)
//     so they parse wherever any expression is accepted.
//   - declaration-as-statement: MQL4/5 code habitually writes a variable
//     declaration as the un-braced consequence of if/else (`if (x == 0)
//     double TComi = 0; else …`). Legal C++, but the C grammar excludes
//     $.declaration from _non_case_statement; verified on a real 21k-line
//     EA (37 contained ERROR nodes).
//   - stray semicolons in class bodies: `Ctor(void) {…};` — an empty
//     member declaration is legal C++ but unmatched by the stock
//     field_declaration_list (3 hits in the same EA).
module.exports = grammar(CPP, {
  name: "mql5",
  rules: {
    storage_class_specifier: ($, original) =>
      choice(original, "input", "sinput"),

    interface_specifier: $ => seq(
      'interface',
      $._class_declaration,
    ),

    _type_specifier: ($, original) => choice(
      original,
      $.interface_specifier,
    ),

    color_literal: _ => token(/[cC]'[^']*'/),

    datetime_literal: _ => token(/[dD]'[^']*'/),

    _expression_not_binary: ($, original) => choice(
      original,
      $.color_literal,
      $.datetime_literal,
    ),

    _non_case_statement: ($, original) => choice(
      original,
      $.declaration,
    ),

    _field_declaration_list_item: ($, original) => choice(
      original,
      ';',
    ),
  },
})
