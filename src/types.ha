use memio;

type namespace = struct {
    pub: bool,
    mut: bool,
    glob: bool,
    param: bool,
    name: str,
    ffi: (str | void),
    tpe: lichen_t,
};

type keyword = enum u8 {
    USE, MOD, PUB, MUT, LET, FN, TYPE,
    FOR, SWITCH, IF, ELSE,
    RETURN, UNREACHABLE, DO, TEST,
    RECORD, ENUM, NEW, OR,
    TRUE, FALSE, FAIL, NOMEM,
};

const kwd_value = [
    "use", "mod", "pub", "mut", "let", "fn", "type",
    "for", "switch", "if", "else",
    "return", "unreachable", "do", "test",
    "record", "enum", "new", "or",
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
    name: namespace,
    export_name: str,
    fields: [](bool, *decl_meta),
    defaults: []*const_meta,
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
    "modulo", "error propagation",
    "bang", "range", "spread", "length", "assignment",
];

type operator = enum u8 {
    LOR, LAND, EQL, NEQ, LEQ, GEQ,
    LST, GTT, BOR, BAND, SHL, SHR,
    NOT, PLS, MIN, MUL, DIV, MOD,
    BUBBLE, BANG, RANGE, SPREAD,
    LENGTH, ASG,
};

const sym_value = [
    "end of line", "allocate at",
    "comma", "record field access",
    "module field access",
    "open parenthesis", "close parenthesis",
    "scope definition", "end of scope",
    "open square brackets", "close square brackets",
];

type symbol = enum u8 {
    EOL, AT, COMMA, DOT, FIELD,
    LFT_PAR, RGT_PAR,
    LFT_CURLY, RGT_CURLY,
    LFT_SQUARE, RGT_SQUARE,
};

type eof = void;
type tk_val =
    (size | f64 | str | namespace | keyword | primitive | operator | symbol | eof);

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
    host_fun: nullable *fun_meta,
    lifetime: (void | size),
    re_emit: bool,
    global: *scope,
    scp: *scope,
};

type scope = struct {
    defs: [](*fun_meta | *decl_meta | *type_meta | *module_meta),
    upper: nullable *scope,
};

type member_t = (*const_meta | *array_lit_meta | *record_lit_meta |
    *indexing_meta | *field_meta | *var_meta | *funcall_meta | *alloc_meta);
type hand_t = (*hand_meta | *member_meta | *ternary_meta | *expr_meta);

type path_meta = (*hand_meta | *hand_meta | *member_meta | *ternary_meta |
    *expr_meta | *const_meta | *array_lit_meta | *record_lit_meta |
    *indexing_meta | *field_meta | *var_meta | *funcall_meta | *alloc_meta |
    *decl_meta | *assign_meta | *arena_meta | *fun_meta | *scope_meta |
    *expr_meta | *branch_meta | *return_meta | *test_meta | *for_meta |
    *type_meta | *module_meta | unreachable);

type const_meta = struct {
    pre: (void | operator),
    val: tk_val,
};

type array_lit_meta = struct {
    tpe: lichen_t,
    items: []*expr_meta,
    spreads_at: (void | size),
};

type indexing_meta = struct {
    before: (void | *field_meta | *indexing_meta),
    index: (*const_meta | *expr_meta),
    base: nullable *member_meta,
    pos: size,
    tpe: lichen_t,
    prop: (void | propagation),
    from_tpe: lichen_t,
};

type record_lit_meta = struct {
    tpe: lichen_t,
    values: [](str, *expr_meta),
};

type field_meta = struct {
    before: (void | *field_meta | *indexing_meta),
    field: *decl_meta,
    base: nullable *member_meta,
    pos: size,
    tpe: lichen_t,
    prop: (void | propagation),
    from_tpe: lichen_t,
};

type decl_meta = struct {
    var: *var_meta,
    val: (void | *const_meta | ...hand_t),
};

type assign_meta = struct {
    pos: size,
    var: *var_meta,
    val: *expr_meta,
    host: (void | *decl_meta | *field_meta),
};

type arena_meta = struct {
    pos: size,
    self: *decl_meta,
    body: *scope_meta,
    prop: (void | propagation),
    host: lichen_t,
    length: *expr_meta,
};

type alloc_meta = struct {
    pos: size,
    val: *member_meta,
    tpe: lichen_t,
    prop: (void | operator),
    host: lichen_t,
    arena: *var_meta,
};

type var_meta = struct {
    nm: namespace,
    owner: *context,
    lifetime: (void | size),
    pos: size,
};

type fun_meta = struct {
    fun: namespace,
    owner: *context,
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

type propagation = (operator, (void | path_meta));

type expr_meta = struct {
    pos: size,
    tpe: lichen_t,
    pre: (void | operator),
    val: (void | hand_t),
    prop: (void | propagation),
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
    val: (void | keyword | ...member_t),
    prop: (void | propagation),
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

type test_meta = struct {
    pos: size,
    cond: *expr_meta,
    props: bool,
    buffer: *memio::stream,
    str_id: size,
    host_tpe: (void | lichen_t),
};

type for_meta = struct {
    pos: size,
    mut: bool,
    indx: nullable *decl_meta,
    local: nullable *decl_meta,
    iter: (*decl_meta | *array_lit_meta),
    item: *decl_meta,
    body: *scope_meta,
};

type type_meta = struct {
    owner: *context,
    pos: size,
    pub: bool,
    name: namespace,
    self: lichen_t,
};

type unreachable = void;

type module_meta = struct {
    name: str,
    owner: *context,
    pos: size,
    pub: bool,
    freed: bool,
    parsed: bool,
    emitted: bool,
    ctxt: *context,
};

type ERROR = !*memio::stream;
