use memio;
// valid syntax sequences
//
// program := global_def+
// global_def := type_def | const_def | fun_def | import
//
// type_def := "let", ident, "=", "type", record | enum | union | type
// record := "{",(ident, type, eol)+, "}", eol
// enum := "{", (ident, ["=", const_val]*), "}", eol
// union := type, ["|", type]+
// type := prim | ident | "fail"
// prim := u8 | u16 | u32 | u64 | i8 | i16 | i32 | i64 | str | unit | void
//
// ident := (A-Z | a-z | 0-9 | _)+
// const_val := ([unary_operator] number) | string
// number := (["0x" | "0o" | "0b"] (0-9)+) | char_lit
//
// const_def := ident, "=", const_exp
// const_exp := const_val [binary_operator, const_val]*
// binary_operator := "+" | "-" | "*" | "/" | ":" | "%" | "<<" | ">>" | "==" |
//      "/=" | "<" | ">" | "<=" | ">=" | "&&" | "||" | "&" | "|" | "^"
// unary_operator := "+" | "-" | "~"
//
// fun_def := ["pub"], "fn", ident, param_list, type, "=", [effect], scope
// param_list := "(", (ident, type)*, ")"
// effect := ident | "do" ("&", ident)*
// scope := "{", expression*, "}"
//
// expression := ["=>"], (declaration | statement | fun_call) |
//      (member (binary_operator, member)*)
// declaration := "let", ident, "=", expression | array, eol
//
// array := "[", (expression, (",", expression)*)*, "]"
//
// statement := if_else_block | for_block | match_block
//
// statement_declaration := ident, "=", expression
//
// if_else_block := if_block, [else_block]
// if_block := "if", [statement_declaration], expression, scope
// else_block := "else", if_block | scope
//
// for_block := "for", [statement_declaration], expression, [ident], scope
// match_block := "match", [statement_declaration], expression, "{",
//      (([ident], type) | "else", scope)+, "}"
//
// fun_call := ident | field_access | module_access, "(", (expression, [",", expression])*, ")"
// member := ([unary_operator] number | ident) | string | field_access | module_access | "todo" | "fail"
// field_access := ident, ".", ident
// module_access := ident, "::", ident
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
    TODO, FAIL,
};

const kwd_value = [
    "use", "pub", "let", "fn", "type",
    "for", "match", "if", "else",
    "todo", "fail",
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
    MAP,
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
