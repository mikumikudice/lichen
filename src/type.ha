// --- compilation errors ---
type unimsg = struct {
    msg: str,
    tip: (str | void),
    ptr: *file,
};
type bi_msg = struct {
    lft: str,
    rgt: str,
    tip: (str | void),
    ptr: *file,
};
type LDDFAIL = !str;
type CRTFAIL = !str;
type UNREACH = !(str, *file);
type INVALID = !(void | unimsg);
type EXPECTD = !(void | bi_msg);
type UNDEFNS = !(void | unimsg);
type MISMTCH = !(void | unimsg);
type CANT_DO = !(void | unimsg);
type IDTCDUP = !(void | bi_msg);
type MODCDUP = !(void | bi_msg);
type NOTPUBL = !(void | bi_msg);
type NOTCALL = !(void | unimsg);
type GENERIC = !(void | unimsg);
type GENTODO = !(void | unimsg);
type CMP_ERR = !
    ( LDDFAIL
    | CRTFAIL
    | INVALID
    | UNREACH
    | EXPECTD
    | UNDEFNS
    | MISMTCH
    | CANT_DO
    | IDTCDUP
    | MODCDUP
    | NOTPUBL
    | NOTCALL
    | GENERIC
    | GENTODO
    );
// --- parser types ---
type file = struct {
    lin: size,
    ptr: size,
    cln: size,
    end: size,
    lst: size,
    src: []u8,
    name: str,
    iseol: bool,
    eolat: nullable *file,
};

type num = (u64 | i64);
type idt = str;
type txt = []u8;

type kwd = enum int
    { USE__MOD, PUBFIELD, TEST_BLK
    , IF___BLK, ELSE_BLK, MATCHBLK
    , FOR_LOOP, NEXT_STT, BREAKSTT
    , EVAL_STT, RETURNTO, DEFERSTT
    , U8__TYPE, U16_TYPE, U32_TYPE, U64_TYPE    // 12
    , I8__TYPE, I16_TYPE, I32_TYPE, I64_TYPE    // 16
    , RATIO__T, STRING_T, RAW_TYPE, UNITTYPE    // 20
    , FUNCTION, RECORD_T, TUNION_T, ENUMTYPE    // 24
    , IS__OPER, DMUTABLE, AND_OPER, OR__OPER
    , KWRD_END, NOT_KWRD, NUMBER_T, ARRAY__T, LLIST__T, EFFECT_T // 32
};
const kwdv =
    [ "use"  , "pub"  , "test"
    , "if"   , "else" , "match"
    , "for"  , "next" , "break"
    , "yield", "return", "defer"
    , "u8"   , "u16"  , "u32", "u64"
    , "i8"   , "i16"  , "i32", "i64"
    , "rat"  , "str"  , "raw", "unit"
    , "fn"   , "rec"  , "uni", "enum"
    , "is"   , "mut"  , "and", "or"
    ];
const stou = kwd::I8__TYPE - kwd::U8__TYPE;
static assert(kwd::KWRD_END: size == len(kwdv), "keyword values not updated");

type opr = enum int
    { LOGICNOT, LOGICAND, LOGIC_OR, BITSHFTR, BITSHFTL
    , BOOL_EQL, BOOL_DIF, BOOL_LSS, BOOL_GRT, BOOL_LEQ, BOOL_GEQ
    , ARTH_PLS, ARTH_MIN, ARTH_MUL, ARTH_DIV, ARTH_MOD
    , INCREMNT, DECREMNT, MULTIPLY, DIVIDEBY, ASSIGNMT, MAP_CASE
    , RANGE_OP, COMPLETE, EFFCTTAG, CASTTOTP, MODFIELD, RECFIELD
    , PROPAGTN, ASSERTER, OPER_END, NOT_OPER
};
const oprv =
    [ "~"  , "&"  , "|"  , "<<", ">>" 
    , "==" , "!=" , "<"  , ">" , "<=", ">="
    , "+"  , "-"  , "*"  , "/" , "%"
    , "+=" , "-=" , "*=" , "/=", "=", "=>"
    , ".." , "...", "\\" , ":", "::", "."
    , "?"  , "!"
    ];
static assert(opr::OPER_END: size == len(oprv), "operator values not updated");

const inst =
    [ "neg", "and", "or"
    , "shr", "shl"
    , "ceq", "cne"
    , "cls", "cgt"
    , "cle", "cge"
    , "add", "sub", "mul", "div", "rem"
    ];

type sym = enum int
    { OPN_CRLY, CLS_CRLY, OPN_SQRB, CLS_SQRB
    , OPEN_PAR, CLOSEPAR, SEMICLNS, SYMCOMMA
    , SYMB_ANY, SYMB_END, NOT_SYMB
};
const symv =
    [ "{" , "}", "[", "]", "(", ")"
    , ";", ",", "_"
    ];
static assert(sym::SYMB_END: size == len(symv), "symbol values not updated");

type eol = void;
type tok = ( num | txt | idt | kwd | opr | sym | eol );

type func = struct {
    fname: str,
    param: []kwd,
    prm_n: []idt,
    retrn: kwd,
    ret_n: str,
    orign: (str | kernel),
    public: bool,
    lin: size,
    cln: size,
};
type nmsp = struct {
    ident: str,
    vtype: kwd,
    mutbl: bool,
    asgnd: bool,
    param: bool,
    globl: bool,
    orign: (str | kernel),
    value: tok,
    public: bool,
    lin: size,
    cln: size,
};
type idref = struct {
    idt: str,
    vtp: kwd,
    globl: bool,
    orign: (str | kernel),
};
type scope = struct {
    over : (*scope | void),
    defs : []*nmsp,
    funs : []*func,
};
type context = struct {
    scp: *scope,
    uses : *[]*module,
    libpath: str,
    nomain: bool,
};

type tkind = enum {
    PRIMITIVE,
    COMPOSITE,
    TAGGEDUNI,
};
type moss_t = struct {
    tdef: []kwd,
    kind: tkind,
    orign: str,
    error: bool,
    linear: bool,
    public: bool,
};
const krnls = [ "IO", "MEM" ];
type kernel = enum size
    { IO, MEM
    };
type module = struct {
    name : str,
    funs : []*func,
    defs : []*nmsp,
    addp : (size, size),
};
