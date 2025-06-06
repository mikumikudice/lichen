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
// type := [[type], "!"], prim | ident | ("(", type, [",", type]+ ")")
// prim := u8 | u16 | u32 | u64 | i8 | i16 | i32 | i64 | str | unit | void
//
// ident := (A-Z | a-z | 0-9 | _)+
// const_val := ([unary_operator], number | string) | FFI_literal
// number := (["0x" | "0o" | "0b"] (0-9)+) | char_lit
// FFI_literal := "$", ident
//
// const_def := ident, type, "=", const_exp
// const_exp := [unary_operator], const_val, (binary_operator, const_val)*
// binary_operator := "+" | "-" | "*" | "/" | ":" | "%" | "<<" | ">>" | "==" |
//      "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||" | "&" | "|" | "^" | ".." | "..."
//
// unary_operator :=  "~" | "#" | "!"
//
// fun_def := "fn", ident, param_list, type, "=", effect, (scope | FFI_literal), eol
// param_list := "(", (ident, type)*, ")"
// effect := ident | "do" ("&", ident)*
// scope := "{", (expression, eol)*, ["=>", expression, eol], "}"
//
// expression := ["+" | "-"], declaration | statement | (member, (binary_operator, member)*), [type]
//
// declaration := "let", ident, [type], "=", expression, eol
//
// array := "[", ((expression, (",", expression)*)*) | range, "]"
// range := number, "..", number, [binary_operator, number]
// array_indexing := ident, "[", expression, (",", expression)*, "]"
//
// tuple := "(", member+, ")"
//
// statement := if_else_block | for_block | match_block | test_block
//
// statement_declaration := ident, [type], "=", expression
//
// if_else_block := if_block, [else_block]
// if_block := "if", [statement_declaration], expression, scope
// else_block := "else", (if_block | scope)
//
// for_block := "for", [statement_declaration], expression, eol, ident | type, scope
// match_block := "match", [statement_declaration], expression, "{",
//      (([ident], type) | "else", scope)+, "}"
//
// test_block := "test", (expression | (string, scope))
//
// error_handle := ("!" | "?"), expression
//
// member := [unary_operator], ("(", expression, ")") | number | ident | string | fun_call | array_indexing | field_access |
//      module_access | record_literal | field_assign | record_mod | tuple | "todo" | "fail" | member, [type]
//
// fun_call := ident | field_access | module_access, "(", (expression, [",", expression])*, ")", [error_handle]
// field_access := expression, ".", ident
// module_access := ident, "::", ident
//
// record_literal := "{", field_assign, "}"
// field_assign := ident, "=", expression
// record_mod := "{" ident, "|", (field_assign, ("," field_assign)*), "}"
//
// import := ident, "=", "use", string, eol
//
type ident = struct {
    pub: bool,
    glob: bool,
    id: str,
    itype: lichen_t,
};

type keyword = enum u8 {
    USE, PUB, LET, FN, TYPE,
    FOR, MATCH, IF, ELSE,
    TODO, FAIL, DO, TEST,
    RECORD, ENUM, UNION
};

const kwd_value = [
    "use", "pub", "let", "fn", "type",
    "for", "match", "if", "else",
    "todo", "fail", "do", "test",
    "record", "enum", ""
];

type primitive = enum u8 {
    U8, U16, U32, U64,
    I8, I16, I32, I64,
    F32, F64,
    STR, CSTR,
    UNIT, VOID,
    NUMBER, RATIO, ARRAY,
    ARR_U8, ARR_U16, ARR_U32, ARR_U64,
    ARR_I8, ARR_I16, ARR_I32, ARR_I64,
    ARR_F32, ARR_F64, ARR_STR, ARR_CSTR,
    ARR_NUMBER, ARR_RATIO, ANY,
};

const prm_value = [
    "u8", "u16", "u32", "u64",
    "i8", "i16", "i32", "i64",
    "f32", "f64",
    "str", "cstr",
    "unit", "void",
    "numeric literal", "ratio literal", "array",
    "u8 array", "u16 array", "u32 array", "u64 array",
    "i8 array", "i16 array", "i32 array", "i64 array",
    "f32 array", "f64 array", "str array", "cstr array",
    "numeric array", "ratio array", "untyped value", 
];

type lichen_t = (primitive | *aggregated | *ext_array);

type aggregated = struct {
    name: str,
    error: bool,
    kind: keyword,
    base: []lichen_t,
    error_val: (void | lichen_t),
};

type ext_array = struct {
    length: (size | void),
    base: (primitive | *aggregated | *ext_array),
};

const opr_value = [
    "assignment", "eq", "neq", "leq", "geq",
    "lt", "gt", "shl", "shr",
    "logic or", "logic and",
    "boolean or", "boolean and",
    "not", "plus", "minus", "multiply",
    "integer division", "ratio division",
    "modulo", "bubble error", "bang",
    "heap-alloc", "map", "range", "spread", "length"
];

type operator = enum u8 {
    ASG, EQL, NEQ, LEQ, GEQ,
    LST, GTT, SHL, SHR,
    LOR, LAND, BOR, BAND,
    NOT, PLS, MIN, MUL,
    IDIV, FDIV, MOD,
    PROP, BANG, HEAP,
    MAP, RANGE, SPREAD, LENGTH,
};

const sym_value = [
    "end of line", "FFI linking",
    "comma", "record field access",
    "module field access",
    "open parenthesis", "close parenthesis",
    "scope definition", "end of scope",
    "indexing", "end of indexing",
];

type symbol = enum u8 {
    EOL, FFI,
    COMMA, DOT, FIELD,
    LFT_PAR, RGT_PAR,
    LFT_CURLY, RGT_CURLY,
    LFT_SQUARE, RGT_SQUARE,
};

type eof = void;

type tkval = (ident | size | str | keyword | primitive |
    operator | symbol | eof);

type token = struct {
    pos: size,
    begin: size,
    val: tkval,
};
type scope = struct {
    vars: []*ast,
    upper: (void | *scope),
    effects: []tkval,
};

type eval_kind = enum u8 { RET, MOV, NONE };

type context = struct {
    name: str,
    libpath: str,

    ptr: size,
    last: size,
    begin: size,
    src: []u8,

    glob: scope,
    scp: (void | *scope),
    literals: *[]str,
    l_arrays: []str,
    fun_defs: []*ast,
    typedefs: *[](*aggregated | *ext_array),
    modules: [](token, *context),
    scope_owner: (void | *fn_meta),

    head: nullable *ast,
    tokens: []token,
    buffer: *memio::stream,

    eval_t: eval_kind,
    fail: bool,
    tailcall: bool,
};

type path_t = enum u8 {
    TYPE_DEF, RECORD, ENUM, UNION,
    CONST_VAL, CONST_DEF, CONST_EXP,
    FUN_DEF, PARAM_LIST, SCOPE, EXPR, DECL,
    MEMBER, OPERATOR, ARRAY, RANGE, INDEXING,
    TUPLE, STATEMENT, STT_DECL,
    FUN_CALL, FIELD_ACCESS, MODULE_ACCESS,
    RECORD_LIT, IMPORT, EOF,
};

type var_meta = struct {
    pos: token,
    ffi: (void | str),
    mod: (void | str),
    glob: bool,
    rets: eval_kind,
    name: ident,
    value: nullable *ast,
};

type fn_meta = struct {
    pos: token,
    ffi: (void | str),
    mod: (void | str),
    name: ident,
    fn_type: lichen_t,
    params: nullable *ast,
    body: nullable *ast,
    scope_begin: size,
    used: bool,
    origin: str,
    generated: bool,
    variadic: bool,
    effects: []tkval,
};

type param_meta = struct {
    names: []ident,
    pos: []token,
    at: []size,
};

type scope_meta = struct {
    rets: eval_kind,
    ret_exp: nullable *ast,
    eval: bool,
    tpe: lichen_t,
    scp: (void | *scope),
    members: []*ast,
};

type expr_meta = struct {
    rets: eval_kind,
    tpe: lichen_t,
    members: [](*ast | operator),
};

type funcall_meta = struct {
    prop: (void | operator),
    dest: (str | void),
    tpe: lichen_t,
    fun: *ast,
    args: []*ast,
};

type member_meta = struct {
    pre: (void | operator),
    val: (tkval | *ast),
    tpe: lichen_t,
};

type array_meta = struct {
    tpe: lichen_t,
    itm_tpe: lichen_t,
    items: [] *ast,
};

type index_meta = struct {
    tpe: lichen_t,
    array: *ast,
    index: *ast,
};

type if_else_meta = struct {
    rets: eval_kind,
    tpe: lichen_t,
    conds: []*ast,
    bodies: []*ast,
};

type for_meta = struct {
    rets: eval_kind,
    tpe: lichen_t,
    item: *expr_meta,
    item_tpe: lichen_t,
    element_tpe: lichen_t,
    out_size: size,
    pairs: []token,
    acc: []*ast,
    out_acc: []token,
    body: *ast,
};

type test_meta = struct {
    cond: *ast,
    global: bool,
    line_msg: *memio::stream,
};

type node_meta = (*var_meta | *fn_meta | *param_meta |
    *scope_meta | *expr_meta | *funcall_meta |
    *member_meta | *array_meta | * index_meta |
    *if_else_meta | *for_meta | *test_meta | 
    lichen_t);

type ast = struct {
    kind: path_t,
    path: []token,
    meta: (void | node_meta),
    next: nullable *ast,
    last: nullable *ast,
};

type COMPERR = !(int, *memio::stream);

const fn_demo =
    "%ppub fn %cmain%y() %bvoid %d= %y{%d\n"
    "    %g// your code goes here!%d\n"
    "%y}%d;";
