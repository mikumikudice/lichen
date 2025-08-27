use memio;

type nm_kind = enum {
    UNKNOWN, FUNC, PARAM, VAR, TYPE
};
type namespace = struct {
    pub: bool,
    mut: bool,
    glob: bool,
    kind: nm_kind,
    name: str,
    ffi: (str | void),
    owner: *context,
    tpe: lichen_t,
};

type keyword = enum u8 {
    USE, MOD, PUB, MUT, LET, FN, TYPE,
    FOR, WHILE, BREAK, NEXT, DEFER,
    SWITCH, IF, ELSE,
    RETURN, UNREACHABLE, DO, TEST,
    RECORD, ENUM, UNION, NEW, CAT, OR,
    IS, TRUE, FALSE, ERROR, NIL,
};

const kwd_value = [
    "use", "mod", "pub", "mut", "let", "fn", "type",
    "for", "while", "break", "next", "defer",
    "switch", "if", "else",
    "return", "unreachable", "do", "test",
    "record", "enum", "union", "new", "cat", "or",
    "is", "true", "false", "error", "nil",
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

type base_type = (primitive | *enum_t | *record | *tuple | *array | *fun_ptr); 
type lichen_t = struct {
    partial: bool,
    base: base_type,
};

type enum_t = struct {
    base: primitive,
    variant: []namespace,
};

type record = struct {
    name: namespace,
    export_name: str,
    fields: []((void | bool), *decl_meta),
    defaults: []*const_meta,
    copiable: bool,
    safe_mut: bool,
};

type tuple = struct {
    members: []lichen_t,
};

type array = struct {
    length: (size | void),
    base: lichen_t,
};

type fun_ptr = struct {
    params: [](bool, lichen_t),
    returns: lichen_t,
    effect: []str,
    shares_efx: bool,
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
    allocating: bool,
    loop_pos: (void | size),
    iterating_on: []*var_meta,
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
    types: *[]*type_meta,
    free_on_ret: []str,
    defer_stack: []path_meta,
    scp: *scope,
};

type scope = struct {
    defs: [](*fun_meta | *decl_meta | *type_meta | *module_meta),
    upper: nullable *scope,
};

type chain_exp_t = (*field_meta | *indexing_meta | *slicing_meta);

type member_t = (*const_meta | *array_lit_meta | *record_lit_meta |
    *field_meta | *indexing_meta | *slicing_meta | *var_meta | *funcall_meta |
    *fn_ptr_meta | *alloc_meta | *concat_meta);

type hand_t = (*hand_meta | *member_meta | *ternary_meta | *expr_meta);

type path_meta = (*hand_meta | *member_meta | *ternary_meta | *expr_meta |
    *const_meta | *array_lit_meta | *record_lit_meta | *field_meta |
    *indexing_meta | *slicing_meta | *var_meta | *funcall_meta | *fn_ptr_meta |
    *alloc_meta | *concat_meta | *decl_meta | *assign_meta | *arena_meta |
    *fun_meta | *scope_meta | *expr_meta | *branch_meta | *return_meta |
    *test_meta | *for_meta | *while_meta | *switch_meta | *type_meta |
    *module_meta | loop_break | loop_next | *defer_meta | unreachable);

type const_meta = struct {
    pre: (void | operator),
    val: tk_val,
};

type array_lit_meta = struct {
    pos: size,
    tpe: lichen_t,
    items: []*expr_meta,
    length: (void | *expr_meta),
    spreads_at: (void | size),
    has_allocs: bool,
};

type indexing_meta = struct {
    before: (void | *field_meta | *indexing_meta | *slicing_meta),
    index: (*const_meta | *expr_meta),
    base: nullable *member_meta,
    pos: size,
    tpe: lichen_t,
    prop: (void | propagation),
    from_tpe: lichen_t,
};

type slicing_meta = struct {
    before: (void | *field_meta | *indexing_meta | *slicing_meta),
    begin: (*const_meta | *expr_meta),
    end: (*const_meta | *expr_meta),
    base: nullable *member_meta,
    pos: size,
    tpe: lichen_t,
    safe: bool,
    prop: (void | propagation),
};

type record_lit_meta = struct {
    tpe: lichen_t,
    has_allocs: bool,
    values: [](str, size, *expr_meta),
};

type field_meta = struct {
    before: (void | ...chain_exp_t),
    field: *decl_meta,
    base: nullable *member_meta,
    mut: bool,
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

type short_prop = (operator, size, *memio::stream);
type alloc_meta = struct {
    pos: size,
    val: *member_meta,
    tpe: lichen_t,
    prop: (void | short_prop),
    host: lichen_t,
    arena: *var_meta,
};

type concat_meta = struct {
    pos: size,
    left: iterator_t,
    right: (iterator_t | *member_meta),
    are_slices: bool,
    tpe: lichen_t,
    prop: (void | short_prop),
    host: lichen_t,
    arena: *var_meta,
};

type var_meta = struct {
    nm: namespace,
    lifetime: (void | size),
    allocated: bool,
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
    recursive: bool,
    borrows: (void | size),
    shares_efx: []size,
};

type funcall_meta = struct {
    fun: *fun_meta,
    tpe: lichen_t,
    pos: size,
    args: []*expr_meta,
    lifetime: (void | size),
    tailcall: bool,
};

type fn_ptr_meta = struct {
    points_to: *fun_meta,
};

type scope_meta = struct {
    pos: size,
    stt: []path_meta,
    defer_stack: []path_meta,
    tpe: lichen_t,
    rets: bool,
};

type propagation = (operator, (void | path_meta), size, *memio::stream);

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
    tpe: lichen_t,
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

type iterator_t = (*var_meta | *funcall_meta | *array_lit_meta |
    *indexing_meta | *slicing_meta | *field_meta | *alloc_meta |
    *concat_meta | *const_meta);

type for_meta = struct {
    pos: size,
    mut: bool,
    tpe: lichen_t,
    rets: bool,
    indx: nullable *decl_meta,
    local: nullable *decl_meta,
    iter: iterator_t,
    iter_t: lichen_t,
    item: *decl_meta,
    body: *scope_meta,
};

type while_meta = struct {
    pos: size,
    tpe: lichen_t,
    rets: bool,
    local: nullable *decl_meta,
    cond: *expr_meta,
    body: *scope_meta,
};

type loop_break = size;
type loop_next = size;

type defer_meta = struct {
    self: path_meta,
    pos: size,
};

type switch_case = (([]*const_meta | void), (operator | void), path_meta);

type switch_meta = struct {
    pos: size,
    rets: bool,
    tpe: lichen_t,
    cases: []switch_case,
    check: *expr_meta,
    else_case: (void | size),
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
