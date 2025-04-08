use memio;
// valid syntax sequences
//
// program := global_def+
// global_def := (["pub"], type_def | const_def | fun_def) | test_block | import
//
// type_def := "type", ident, "=", record | enum | union | type
// record := "record", "{",(ident, type, eol)+, "}", eol
// enum := "enum", [type], "{", (ident, ["=", const_val]*), "}", eol
// union := type, ["|", type]+
// type := prim | ident
// prim := u8 | u16 | u32 | u64 | i8 | i16 | i32 | i64 | str | unit | void
//
// ident := (A-Z | a-z | 0-9 | _)+
// const_val := ([unary_operator] number) | string
// number := (["0x" | "0o" | "0b"] (0-9)+) | char_lit
//
// const_def := ident, "=", const_exp
// const_exp := const_val (binary_operator, const_val)*
// binary_operator := "+" | "-" | "*" | "/" | ":" | "%" | "<<" | ">>" | "==" |
//      "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||" | "&" | "|" | "^" | ".."
// unary_operator := "+" | "-" | "~" | "#"
//
// fun_def := "fn", ident, param_list, type, "=", effect, scope, eol
// param_list := "(", (ident, type)*, ")"
// effect := ident | "do" ("&", ident)*
// scope := "{", expression*, ["=>", expression], "}"
//
// expression := (declaration | statement | fun_call | array_indexing) |
//      (member (binary_operator, member)*)
// declaration := "let", ident, [type], "=", expression | array, [type], eol
//
// array := "[", ((expression, (",", expression)*)*) | range, "]"
// range := number, "..", number, [binary_operator, number]
// array_indexing := ident, "[", expression, (",", expression)*, "]"
//
// statement := if_else_block | for_block | match_block | test_block
//
// statement_declaration := ident, "=", expression
//
// if_else_block := if_block, [else_block]
// if_block := "if", [statement_declaration], expression, scope
// else_block := "else", (if_block | scope)
//
// for_block := "for", [statement_declaration], expression, [ident], scope
// match_block := "match", [statement_declaration], expression, "{",
//      (([ident], type) | "else", scope)+, "}"
//
// test_block := "test", (expression | (string, scope))
//
// fun_call := ident | field_access | module_access, "(", (expression, [",", expression])*, ")", [error_handle]
//
// error_handle := ("!" | "?"), expression
//
// member := ([unary_operator] number | ident | field_access | module_access) | string | 
// record_literal | field_assign | record_mod | "todo" | "fail"
//
// field_access := ident, ".", ident
// module_access := ident, "::", ident
//
// record_literal := "{", field_assign, "}"
// field_assign := ident, "=", expression
// record_mod := "{" ident, "|", (field_assign, ("," field_assign)*), "}"
//
// import := ident, "=", "use", string, eol
//
type ident = struct {
    name: str,
    lin: size,
    cln: size
};

type number = (bool, u64);

type keyword = enum {
    USE, PUB, LET, FN, TYPE,
    FOR, MATCH, IF, ELSE,
    TODO, FAIL, DO, TEST,
    RECORD, ENUM,
};

const kwd_value = [
    "use", "pub", "let", "fn", "type",
    "for", "match", "if", "else",
    "todo", "fail", "do", "test",
    "record", "enum"
];

type primitive = enum {
    U8, U16, U32, U64,
    I8, I16, I32, I64,
    STR, UNIT, VOID,
};

const prm_value = [
    "u8", "u16", "u32", "u64",
    "i8", "i16", "i32", "i64",
    "str", "unit", "void",
];

type operator = enum {
    MAP, RANGE, LENGTH, 
    LEQ, GEQ, ASG, EQL, NEQ,
    SHL, SHR, LST, GTT, DEF,
    LOR, LAND, BOR, BAND,
    NOT, PLS, MIN, MUL,
    IDIV, FDIV, MOD,
    PROP, BANG,
};

type symbol = enum {
    EOL,
    COMMA, DOT, FIELD,
    LFT_PAR, RGT_PAR,
    LFT_CURLY, RGT_CURLY,
    LFT_SQUARE, RGT_SQUARE,
};

type eof = void;

type token = (ident | number | str | keyword | primitive |
    operator | symbol | eof);

type source = struct {
    name: str,
    lin: size,
    cln: size,
    ptr: size,
    lst: size,
    src: []u8
};

type COMPERR = !(int, *memio::stream);

const fn_demo =
    "pub fn main() void = {\n"
    "\t// your code goes here!\n"
    "};\n";
