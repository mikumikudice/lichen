use memio;

type namespace = struct {
    pub: bool,
    mut: bool,
    glob: bool,
    name: str,
    ffi: (str | void),
    tpe: lichen_t,
};

type keyword = enum u8 {
    USE, MOD, PUB, MUT, LET, FN, TYPE,
    FOR, SWITCH, IF, ELSE,
    RETURN, UNREACHABLE, DO, TEST,
    RECORD, ENUM, NEW,
    TRUE, FALSE, FAIL, NOMEM,
};

const kwd_value = [
    "use", "mod", "pub", "mut", "let", "fn", "type",
    "for", "switch", "if", "else",
    "return", "unreachable", "do", "test",
    "record", "enum", "new",
    "true", "false", "fail", "nomem",
];

type primitive = enum u8 {
    U8, U16, U32, U64,
    I8, I16, I32, I64,
    F32, F64, BOOL,
    STR, CSTR,
    UNIT, VOID, MEM,
    NUMBER, RATIO, ANY,
};

const prim_value = [
    "u8", "u16", "u32", "u64",
    "i8", "i16", "i32", "i64",
    "f32", "f64",
    "bool", "str", "cstr",
    "unit", "void", "mem",
    "numeric literal", "ratio literal",
    "untyped",
];

type lichen_t = struct {
    fail: bool,
    base: (primitive | *enum_t | *record | *tuple | *array),
};

type enum_t = struct {
    base: primitive,
    variant: []namespace,
};

type record = struct {
    name: str,
    field: []lichen_t,
};

type tuple = struct {
    members: []lichen_t,
};

type array = struct {
    length: (size | void),
    base: lichen_t,
};

const oper_value = [
    "logical or", "logical and", "equal to", "not equal to",
    "less than or equal to", "greater than or equal to",
    "less than", "greater than",
    "bitwise or", "bitwise and",
    "bitwise shift left", "bitwise shift right",
    "bitwise not",
    "plus sign", "minus sign", "multiply", "division",
    "modulo", "error propagation", "allocate at",
    "bang", "range", "spread", "length", "assignment",
];

type operator = enum u8 {
    LOR, LAND, EQL, NEQ, LEQ, GEQ,
    LST, GTT, BOR, BAND, SHL, SHR,
    NOT, PLS, MIN, MUL, DIV, MOD,
    BUBBLE, AT, BANG, RANGE, SPREAD,
    LENGTH, ASG,
};

const sym_value = [
    "end of line",
    "comma", "record field access",
    "module field access",
    "open parenthesis", "close parenthesis",
    "scope definition", "end of scope",
    "indexing", "end of indexing",
];

type symbol = enum u8 {
    EOL, COMMA, DOT, FIELD,
    LFT_PAR, RGT_PAR,
    LFT_CURLY, RGT_CURLY,
    LFT_SQUARE, RGT_SQUARE,
};

type tk_val =
    (size | f64 | str | namespace | keyword | primitive | operator | symbol);

type token = struct {
    pos: size,
    begin: size,
    val: tk_val,
};

type context = struct {
    file: str,
    path: str,
    main: bool,
    branching: bool,
    src: []u8,
    ptr: size,
    last: size,
    begin: size,
    tokens: []token,
    literals: *[]str,
    typedefs: []lichen_t,
    host_fun: nullable *fun_meta,
    global: *scope,
    scp: *scope,
};

type scope = struct {
    defs: [](*fun_meta | *decl_meta | *module_meta),
    upper: nullable *scope,
};

type path_meta = (*const_meta | *decl_meta | *var_meta | *fun_meta |
    *funcall_meta | *scope_meta | *expr_meta | *hand_meta | *member_meta |
    *branch_meta | *ternary_meta | *return_meta | *module_meta);

type decl_meta = struct {
    var: *var_meta,
    val: (void | *const_meta | ...hand_t),
};

type const_meta = struct {
    pre: (void | operator),
    val: tk_val,
};

type var_meta = struct {
    nm: namespace,
    pos: size,
};

type fun_meta = struct {
    fun: namespace,
    pos: size,
    begins: size,
    origin: str,
    body: nullable *scope_meta,
    params: []*decl_meta,
    effect: []str,
    used: bool,
    variadic: bool,
};

type funcall_meta = struct {
    fun: *fun_meta,
    tpe: lichen_t,
    pos: size,
    args: []*expr_meta,
};

type scope_meta = struct {
    pos: size,
    stt: []path_meta,
    tpe: lichen_t,
    self: *scope,
    rets: bool,
};

type hand_t = (*hand_meta | *member_meta | *ternary_meta | *expr_meta);

type expr_meta = struct {
    pos: size,
    tpe: lichen_t,
    pre: (void | operator),
    val: (void | hand_t),
    prop: (void | operator),
};

type hand_meta = struct {
    pos: size,
    tpe: lichen_t,
    lft: hand_t,
    opr: operator,
    rgt: hand_t,
};

type member_meta = struct {
    pos: size,
    tpe: lichen_t,
    pre: (void | operator),
    val: (*const_meta | *var_meta | *funcall_meta | keyword),
    prop: (void | operator),
};

type branch_meta = struct {
    pos: size,
    rets: bool,
    nested: bool,
    conds: []*expr_meta,
    bodies: []((*decl_meta | void), *scope_meta),
};

type ternary_meta = struct {
    pos: size,
    tpe: lichen_t,
    positive: hand_t,
    negative: hand_t,
    condition: *expr_meta,
};

type return_meta = struct {
    val: *expr_meta,
    tpe: lichen_t,
    pos: size,
};

type module_meta = struct {
    name: str,
    pos: size,
    pub: bool,
    freed: bool,
    parsed: bool,
    emitted: bool,
    ctxt: *context,
};

type ERROR = !*memio::stream;
