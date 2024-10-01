use memio;

// --- compilation errors ---
type FILE_ERR = !str;
type BUNREACH = !void;
type SNTX_ERR = !memio::stream;
type COMP_ERR = !(FILE_ERR | SNTX_ERR | BUNREACH);

// --- parser types ---
type file = struct {
    lin: size,
    cln: size,
    ptr: size,
    lst: size,
    src: []u8,
    name: str,
    last: (size, size, size, size),
};

type num = u64;
type idt = str;
type txt = []u8;
type kwd = enum int
    { USE__MOD, PUBFIELD
    , FUNCTION, RECORD_T, TUNION_T, ENUMERTR
    , IF___BLK, ELSE_BLK, MATCHBLK
    , U8__TYPE, U16_TYPE, U32_TYPE, U64_TYPE
    , I8__TYPE, I16_TYPE, I32_TYPE, I64_TYPE
    , F32_TYPE, F64_TYPE, STRING_T, UNITTYPE
    , IS__OPER, NOT_OPER, AND_OPER, OR__OPER
    , TODO_HLT, FAIL_HLT, VOIDTYPE, DEFERBLK
    , UNIT_LIT, KWRD_END
};
const kwdv =
    [ "use", "pub"
    , "fn" , "rec" , "union", "enum"
    , "if" , "else", "match"
    , "u8" , "u16" , "u32", "u64"
    , "i8" , "i16" , "i32", "i64"
    , "f32", "f64" , "str", "unit"
    , "is" , "not" , "and", "or"
    , "todo", "fail", "void"
    , "defer", "_"
    ];
static assert(kwd::KWRD_END: size == len(kwdv), "keyword values not updated");

type opr = enum int
    { LOGICNOT, LOGICAND, LOGIC_OR, BITSHFTR, BITSHFTL, LOGICXOR
    , BOOL_EQL, BOOL_DIF, BOOL_LSS, BOOL_GRT, BOOL_LEQ, BOOL_GEQ
    , ARTH_PLS, ARTH_MIN, ARTH_MUL, ARTH_DIV, RATIODIV, ARTH_REM
    , ASSIGNMT, RANGE_OP, COMPLETE, MODFIELD, OBJFIELD, MAP_CASE
    , PROPAGTN, ASSERTER, OPER_END, NOT_OPER
};
const oprv =
    [ "~" , "&"  , "|"  , "<<", ">>", "^" 
    , "==", "!=" , "<"  , ">" , "<=", ">="
    , "+" , "-"  , "*"  , "/" , ":" , "%"
    , "=" , ".." , "...", "::", "." , "=>"
    , "?" , "!"
    ];
static assert(opr::OPER_END: size == len(oprv), "operator values not updated");

const inst =
    [ "neg", "and", "or"
    , "shl", "shr", "xor"
    , "ceq", "cne"
    , "lt", "gt"
    , "le", "ge"
    , "add", "sub", "mul", "div", "div", "rem"
    ];

type sym = enum int
    { OPN_CRLY, CLS_CRLY, OPN_SQRB, CLS_SQRB
    , OPEN_PAR, CLOSEPAR, SEMICLNS, SYMCOMMA
    , SYMB_END, NOT_SYMB
};
const symv =
    [ "{", "}", "[", "]"
    , "(", ")", ";", ","
    ];
static assert(sym::SYMB_END: size == len(symv), "symbol values not updated");

type eos = void;
type eol = void;
type tok = ( num | txt | idt | kwd | opr | sym | eos | eol );

type prim = enum int
    { NUMBER, RATIO, U8, U16, U32, U64, I8, I16, I32, I64
    , F32, F64, STRING, UNIT, VOID, FUNCTION, ANY, PRIM_END
    };
const primv =
    [ "numerical type", "ratio type"
    , "unsigned 8-bit int", "unsigned 16-bit int", "unsigned 32-bit int", "unsigned 64-bit int"
    , "signed 8-bit int", "signed 16-bit int", "signed 32-bit int", "signed 64-bit int"
    , "32-bit floating point", "64-bit floating point", "string type", "unit type", "void type"
    , "function", "any type"
    ];
static assert(prim::PRIM_END: size == len(primv), "primitive type values not updated");

type nmsp = struct {
    pos: (size, size),
    name: idt,
    value: expr_h,
    vtype: prim,
    param: bool,
    global: bool,
    origin: str,
    public: bool,
};
type func = struct {
    pos: (size, size),
    name: idt,
    param: [](idt, prim),
    retrn: prim,
    origin: str,
    public: bool,
    impure: bool,
    effect: []str,
};

type fun_def = struct {
    f: file,
    nm: idt,
    pub: bool,
};

type scope = struct {
    pos: (size, size),
    over: (*scope | void),
    vars: []*nmsp,
    funs: []*func,
};
type context = struct {
    scp: *scope,
    uses: []*module,
    srcpath: str,
    libpath: str,
    datasec: memio::stream,
    strlits: []str,
    fnname: (str | void),
    branch: bool,
    nomain: bool,
    assign: bool,
    effect: []str,
};

type express = struct {
    args: []expr_h,
    oprs: []opr,
    expr_t: prim,
};
type synthexp = struct {
    buffer: memio::stream,
    expr_t: prim,
    is_ret: bool,
    single: bool,
    fncall: (void | funcall),
    finish: tok,
    exp_id: str,
};
type expr_h = (*nmsp | *func | u64 | i64 | txt | funcall | synthexp | void);

type funcall = struct {
    fun: *func,
    args: []synthexp,
};

type module = struct {
    pos: (size, size),
    name : str,
    origin: str,
    vars : []*nmsp,
    funs : []*func,
};

const stdin = nmsp {
    pos = (0, 0),
    name = "stdin",
    value = 0: num,
    vtype = prim::U32,
    param = false,
    global = true,
    origin = "rt",
    public = true,
};
const stdout = nmsp {
    pos = (0, 0),
    name = "stdout",
    value = 1: num,
    vtype = prim::U32,
    param = false,
    global = true,
    origin = "rt",
    public = true,
};
const stderr = nmsp {
    pos = (0, 0),
    name = "stderr",
    value = 2: num,
    vtype = prim::U32,
    param = false,
    global = true,
    origin = "rt",
    public = true,
};

// fn(...) unit
const dummy = func {
    pos = (0, 0),
    name = "dummy",
    param = [
        ("x", prim::ANY),
        ("y", prim::ANY),
        ("z", prim::ANY),
        ("w", prim::ANY),
    ],
    retrn = prim::UNIT,
    origin = "rt",
    public = true,
    impure = false,
    effect = ["rt"],
};
// fn(size : u64) rec { u64, u64 }
const arena = func {
    pos = (0, 0),
    name = "arena",
    param = [
        ("size", prim::U64),
    ],
    retrn = prim::U64,
    origin = "rt",
    public = true,
    impure = true,
    effect = ["rt"],
};
// fn(arena : rec { u64, u64 }) unit
const _free = func {
    pos = (0, 0),
    name = "free",
    param = [
        ("arena", prim::U64),
    ],
    retrn = prim::U64,
    origin = "rt",
    public = true,
    impure = true,
    effect = ["rt"],
};
// fn(handle : u32, data : str) unit
const puts = func {
    pos = (0, 0),
    name = "puts",
    param = [
        ("handle", prim::U32),
        ("buffer", prim::STRING),
    ],
    retrn = prim::UNIT,
    origin = "rt",
    public = true,
    impure = true,
    effect = ["rt"],
};
// gets = fn(u32, rec { u64, u64 }) unit
const gets = func {
    pos = (0, 0),
    name = "gets",
    param = [
        ("handle", prim::U32),
        ("arena" , prim::U64),
    ],
    retrn = prim::STRING,
    origin = "rt",
    public = true,
    impure = true,
    effect = ["rt"],
};
// exit = fn(u32) void
const exit = func {
    pos = (0, 0),
    name = "exit",
    param = [("code", prim::U32)],
    retrn = prim::VOID,
    origin = "rt",
    public = true,
    impure = true,
    effect = ["rt"],
};

const rtmod = module {
    pos = (0, 0),
    name = "rt",
    origin = "",
    vars = [
        &stdin,
        &stdout,
        &stderr,
    ],
    funs = [
        &dummy,
        &arena,
        &_free,
        &puts,
        &gets,
        &exit,
    ],
};

const fn_demo =
    "pub main = fn() void {\n"
    "};";
