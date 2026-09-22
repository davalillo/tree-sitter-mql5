; MQL-specific highlight queries for tree-sitter-mql5.
; The generic C/C++ highlighting comes from
; node_modules/tree-sitter-cpp/queries/highlights.scm (chained in package.json);
; this file only adds MQL-native nodes.

; MQL storage classes (`input` / `sinput` parameters)
(storage_class_specifier) @keyword.modifier

; `input group "..."` directive (MQL5 build >= 1861, unified MQL4 compiler)
"input" @keyword
"group" @keyword
(input_group
  name: (string_literal) @label)

; MQL-native literals
(color_literal) @string.special
(datetime_literal) @string.special
