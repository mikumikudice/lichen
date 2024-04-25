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
type LDDFAIL = !void;
type CRTFAIL = !void;
type UNREACH = !*file;
type INVALID = !(void | unimsg);
type EXPECTD = !(void | bi_msg);
type UNDEFNS = !(void | unimsg);
type MISMTCH = !(void | unimsg);
type CANT_DO = !(void | unimsg);
type IDTCDUP = !(void | unimsg);
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
};

type num = u64;
type idt = str;
type txt = []u8;

type kwd = enum int
    { USE__MOD, PUBFIELD, TEST_BLK
    , IF___BLK, ELSE_BLK, MATCHBLK
    , FOR_LOOP, NEXT_STT, BREAKSTT
    , DEFERSTT, EVAL_STT, RETURNTO
    , U8__TYPE, U16_TYPE, U32_TYPE, U64_TYPE
    , I8__TYPE, I16_TYPE, I32_TYPE, I64_TYPE
    , RATIO__T, STRING_T, NIL_TYPE
    , RECORD_T, TUNION_T, ERROR__T
    , FUNCTION, IS__OPER, DMUTABLE
    , KWRD_END, NOT_KWRD, NUMBER_T
};
const kwdv =
    [ "use"  , "pub" , "test"
    , "if"   , "else", "match"
    , "for"  , "next", "break"
    , "defer", "eval", "ret"
    , "u8"   , "u16" , "u32", "u64"
    , "i8"   , "i16" , "i32", "i64"
    , "rat"  , "str" , "nil"
    , "rec"  , "uni" , "err"
    , "fn"   , "is"  , "mut"
    ];
static assert(kwd::KWRD_END: size == len(kwdv), "keyword values not updated");

type opr = enum int
    { PROPAGTN, ASSERTER
    , LOGICNOT, LOGICAND, LOGIC_OR, BITSHFTR, BITSHFTL
    , BOOL_EQL, BOOL_DIF, BOOL_LSS, BOOL_GRT, BOOL_LEQ, BOOL_GEQ
    , INCREMNT, DECREMNT, MULTIPLY, DIVIDEBY, ASSIGNMT, MAP_CASE
    , ARTH_PLS, ARTH_MIN, ARTH_MUL, ARTH_DIV, ARTH_MOD
    , RANGE_EX, RANGE_IN, COMPLETE
    , BOOL_AND, BOOL__OR
    , OPER_END, NOT_OPER
};
const oprv =
    [ "?"  , "!"
    , "~"  , "&"  , "|"  , "<<", ">>" 
    , "==" , "!=" , ">"  , "<" , ">=", "<="
    , "+=" , "-=" , "*=" , "/=", "=", "=>"
    , "+"  , "-"  , "*"  , "/" , "%"
    , "..<", "..=", "..."
    , "and", "or"
    ];
static assert(opr::OPER_END: size == len(oprv), "operator values not updated");

type sym = enum int
    { OPN_CRLY, CLS_CRLY, OPN_SQRB, CLS_SQRB
    , OPEN_PAR, CLOSEPAR
    , CASTTOTP, MODFIELD, RECFIELD
    , SEMICLNS, SYMCOMMA, SYMB_ANY
    , SYMB_END, NOT_SYMB
};
const symv =
    [ "{" , "}", "[", "]", "(", ")"
    , ":" , "::", "."
    , ";" , "," , "_"
    ];
static assert(sym::SYMB_END: size == len(symv), "symbol values not updated");

type eol = void;
type eof = void;
type tok = ( num | txt | idt | kwd | opr | sym | eol );

type num_t = void;
type nmsp_t = ( kwd | num_t ); // TODO: add composite types
type func = struct {
    fnname: str,
    params: []nmsp_t,
    retrns: [](nmsp | nmsp_t),
    atline: size,
    atcoln: size,
};
type nmsp = struct {
    idntfr: str,
    nstype: nmsp_t,
    atline: size,
    atcoln: size,
};
