; inherit: python

; Capture top-level function definitions
(module
  (function_definition) @toplevel)

(module
  (decorated_definition
    (function_definition)) @toplevel)

; Capture top-level class definitions
(module
  (class_definition) @toplevel)

(module
  (decorated_definition
    (class_definition)) @toplevel)

; Capture top-level imports
(module
  (import_statement) @toplevel)

(module
  (import_from_statement) @toplevel)

; Capture other top-level statements (assignments, expressions, etc.)
(module
  (expression_statement) @toplevel)

(module
  (while_statement) @toplevel)

(module
  (for_statement) @toplevel)

(module
  (if_statement) @toplevel)

(module
  (match_statement) @toplevel)

(module
  (type_alias_statement) @toplevel)
