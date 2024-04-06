// --- compilation errors ---
type unimsg = struct {
    msg: str,
    tip: (str | void),
    ptr: *src_file,
};
type bi_msg = struct {
    lft: str,
    rgt: str,
    tip: (str | void),
    ptr: *src_file,
};
type LDDFAIL = !void;
type INVALID = !(void | unimsg);
type EXPECTD = !(void | bi_msg);
type UNDEFNS = !(void | bi_msg);
type MISMTCH = !(void | unimsg);
type CANT_DO = !(void | unimsg);
type GENERIC = !(void | unimsg);
type GENTODO = !(void | unimsg);
type CMP_ERR = !
    ( LDDFAIL
    | INVALID
    | EXPECTD
    | UNDEFNS
    | MISMTCH
    | CANT_DO
    | GENERIC
    | GENTODO
    );

// --- parser types ---
type src_file = struct {
    lin: size,
    ptr: size,
    cln: size,
    end: size,
    lst: size,
    src: []u8,
};

type num = u64;
type txt = (str | []u8);

type kwd = enum int
    { NOT_KWRD
    , MOD__DEF, USE__MOD, PUBFIELD, TEST_BLK
    , IF___BLK, ELSE_BLK, FOR_LOOP, MATCHBLK
    , DEFERSTT, EVAL_STT, RETURNTO, NIL_TYPE
    , U8__TYPE, U16_TYPE, U32_TYPE, U64_TYPE
    , I8__TYPE, I16_TYPE, I32_TYPE, I64_TYPE
    , RATIO__T, STRING_T, FUNCTION, RECORD_T
    , IN__OPER, IS__OPER, AND_OPER, OR__OPER
    , KWRD_END
};
const kwdv =
    [ ""
    , "mod"  , "use" , "pub", "test"
    , "if"   , "else", "for", "match"
    , "defer", "eval", "ret", "nil"
    , "u8"   , "u16" , "u32", "u64"
    , "i8"   , "i16" , "i32", "i64"
    , "rat"  , "str" , "fn" , "rec"
    , "in"   , "is"  , "and", "or"
    ];
static assert(kwd::KWRD_END: size == len(kwdv), "keyword values not updated");

type opr = enum int
    { NOT_OPER
    , PROPAGTN, ASSERTER, FN_TYPED
    , LOGICNOT, LOGICAND, LOGIC_OR, BITSHFTR, BITSHFTL
    , BOOL_EQL, BOOL_DIF, BOOL_LSS, BOOL_GRT, BOOL_LEQ, BOOL_GEQ
    , INCREMNT, DECREMNT, ASSIGNMT, DEFNTION
    , ARTH_PLS, ARTH_MIN, ARTH_MUL, ARTH_DIV, ARTH_MOD
    , RANGE_EX, RANGE_IN, COMPLETE, OPER_END
};
const oprv =
    [ ""
    , "?"  , "!"
    , "~"  , "&"  , "|"  , "<<", ">>" 
    , "+"  , "-"  , "*"  , "/" , "%"
    , "==" , "!=" , ">"  , "<" , ">=", "<="
    , "+=" , "-=" , "="  , ":=", "=>"
    , "..<", "..=", "..."
    ];
static assert(opr::OPER_END: size == len(oprv), "operator values not updated");

type sym = enum int
    { NOT_SYMB
    , OPN_CRLY, CLS_CRLY, OPN_SQRB, CLS_SQRB
    , OPEN_PAR, CLOSEPAR
    , CASTTYPE, MODFIELD, RECFIELD, SEMICLNS
    , REGCOLON, SYMB_END
};
const symv =
    [ "NONE"
    , "{" , "}", "[", "]", "(", ")"
    , ":" , "::", "."
    , ";" , ","
    ];
static assert(sym::SYMB_END: size == len(symv), "symbol values not updated");

type eol = void;
type eof = void;
type tok = (eol | num | txt | kwd | opr | sym);
