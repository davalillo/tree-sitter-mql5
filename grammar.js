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
//   - stray semicolons in class bodies: `Ctor(void) {…};` — an empty
//     member declaration is legal C++ but unmatched by the stock
//     field_declaration_list (3 hits in the same EA).
//   - MQL primitive types: `string`, `datetime`, `color`, `uchar`, `ushort`,
//     `uint`, `ulong`. The stock C token list has none of them, so they
//     parsed as type_identifier, indistinguishable from user-defined
//     classes/typedefs downstream. Redefined as a superset of the tree-sitter-c
//     0.20.3 token list.
//   - input_group: `input group "Name"` (MQL5 build >= 1861, also accepted
//     by the unified MQL4 compiler). The stock grammar has no rule for it:
//     one occurrence degrades every following declaration into ERROR nodes
//     (24 of 25 failing files in a 111-file real-code corpus audit).
//   - parenthesized assignment `(a = b)`: KNOWN LIMITATION of the pinned
//     2023 base (tree-sitter-c fcd1230 + tree-sitter-cpp 2c7aff4). Legal C++
//     like `if ((x = f()) > 0)` parses with ERROR nodes (9 of 111 files in
//     the real-code corpus audit). Fixed upstream by tree-sitter-c
//     f3559c6 (PREC swap) plus follow-ups; porting the swap alone regresses
//     the digraph corpus and does not fix the parse in this base. The fix
//     arrives with a full regeneration against a modern tree-sitter-c/cpp.
//     A corpus test documents the current ERROR behavior as a tripwire.
module.exports = grammar(CPP, {
  name: "mql5",
  rules: {
    storage_class_specifier: ($, original) =>
      choice(original, "input", "sinput"),

    _top_level_item: ($, original) => choice(original, $.input_group),

    input_group: $ =>
      seq("input", "group", field("name", $.string_literal), optional(";")),

    // `void f() export { ... }` marks a function as exported from a library.
    export_specifier: _ => "export",

    // tree-sitter-cpp 2c7aff4 has no `_function_postfix` rule; the export
    // specifier attaches right after a function declarator's parameter list
    // via the `_function_declarator_seq` suffix hook (shared by
    // function_declarator, function_field_declarator and
    // abstract_function_declarator).
    _function_declarator_seq: ($, original) => choice(
      original,
      prec.right(seq(original, $.export_specifier)),
    ),

    primitive_type: _ =>
      token(choice(
        // tree-sitter-c 0.20.3 token list (unchanged)
        "bool",
        "char",
        "int",
        "float",
        "double",
        "void",
        "size_t",
        "ssize_t",
        "ptrdiff_t",
        "intptr_t",
        "uintptr_t",
        "charptr_t",
        "nullptr_t",
        "max_align_t",
        ...[8, 16, 32, 64].map(n => `int${n}_t`),
        ...[8, 16, 32, 64].map(n => `uint${n}_t`),
        ...[8, 16, 32, 64].map(n => `char${n}_t`),
        // MQL-native primitive types
        "string",
        "datetime",
        "color",
        "uchar",
        "ushort",
        "uint",
        "ulong",
      )),

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
