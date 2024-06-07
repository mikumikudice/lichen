use os;
use io;
use fs;
use fmt;
use bufio;
use errors;
use strings;
use strconv;
use encoding::utf8;

fn tktostr(tk: tok, verb: bool = false) str = {
    match(tk){
        case num =>
            if(verb){
                return fmt::asprintf("a number ({})", tk: num: u64);
            } else {
                return "a number";
            };
        case idt =>
            if(verb){
                return fmt::asprintf("an identifier ({})", tk: idt: str);
            } else {
                return "an identifier";
            };
        case txt =>
            if(verb){
                return fmt::asprintf("a string literal ({})", tostr(tk: txt: []u8));
            } else {
                return "a string literal";
            };
        case let t: kwd =>
            if(verb){
                switch(t){
                case kwd::NUMBER_T =>
                    return "number type";
                case kwd::ARRAY__T =>
                    return "array type";
                case kwd::NOT_KWRD =>
                    return "not a keyword";
                case =>
                    return fmt::asprintf("a keyword ({})", kwdv[tk: kwd]);
                };
            } else {
                return "a keyword";
            };
        case opr =>
            if(verb){
                return fmt::asprintf("an operator ({})", oprv[tk: opr]);
            } else {
                return "an operator";
            };
        case sym =>
            if(verb){
                return fmt::asprintf("a symbol ({})", symv[tk: sym]);
            } else {
                return "a symbol";
            };
        case eol =>
            return "end of line";
    };
};

fn tostr(src: []u8) str = {
    match(strings::fromutf8(src)){
    case let s: str => return s;
    case =>
        fmt::fatal("given source file is not UTF-8 encoded");
    };
};

// compares two tokens
fn cmp_tok(l: tok, r: tok) bool = {
    match(l){
        case let n: num =>
            match(n){
            case u64 => return r is u64 && l: u64 == r: u64;
            case i64 => return r is i64 && l: i64 == r: i64;
            };
        case let this: txt =>
            const max = len(this: []u8);
            if(r is txt &&  max == len(r: txt: []u8)){
                const that = r: txt: []u8;
                for(let c = 0: size; c < max; c += 1){
                    if(this[c] != that[c]) return false;
                };
                return true;
            } else {
                return false;
            };
        case let this: idt =>
            return r is idt && this: str == r: idt: str;
        case kwd =>
            return r is kwd && l: kwd == r: kwd;
        case opr =>
            return r is opr && l: opr == r: opr;
        case sym =>
            return r is sym && l: sym == r: sym;
        case eol =>
            return r is eol && r is eol;
    };
};

fn istxt(c: u8) bool = {
    return (c >= 'A' && c <= 'Z')
        || (c >= 'a' && c <= 'z')
        || (c >= '0' && c <= '9')
        ||  c == '_';
};

fn iswsp(c: u8) bool = {
    return c == ' ' || c == '\n' || c == '\t';
};

fn gen_pos(f: *file) str = {
    return fmt::asprintf( "{}:{}:{}", f.name, f.lin + 1, f.cln + 1);
};

fn gen_lin(f: *file) str = {
    const txt = tostr(f.src);
    const idx = strings::index(strings::sub(txt, f.lst + 1), "\n"): size;
    const end = f.lst + idx + 1;
    const out = strings::sub(txt, f.lst, end);
    return strings::replace(out, "\t", " ");
};

fn is_type(tp: tok) bool = {
    if(!(tp is kwd)) return false;
    switch(tp: kwd){
    case kwd::U8__TYPE, kwd::U16_TYPE, kwd::U32_TYPE, kwd::U64_TYPE, kwd::I8__TYPE,
        kwd::I16_TYPE, kwd::I32_TYPE, kwd::I64_TYPE, kwd::RATIO__T, kwd::STRING_T,
        kwd::RAW_TYPE, kwd::UNITTYPE =>
        return true;
    case => return false;
    };
};

fn is_untyped(tp: kwd) bool = {
    return tp == kwd::NOT_KWRD || tp == kwd::NUMBER_T;
};

fn is_num(tp: kwd, sign: bool = false) bool = {
    if(tp == kwd::NUMBER_T) return true;
    if(!sign){
        return kwd::U8__TYPE <= tp && tp <= kwd::U64_TYPE;
    } else {
        return kwd::I8__TYPE <= tp && tp <= kwd::I64_TYPE;
    };
};

fn is_asg_opr(oper: tok) bool = {
    if(oper is opr){
        const op = oper: opr;
        return op == opr::ASSIGNMT || op == opr::INCREMNT || op == opr::DECREMNT;
    };
    return false;
};

fn is_cmp(oper: opr) bool = {
    return oper == opr::BOOL_EQL || oper == opr::BOOL_DIF || oper == opr::BOOL_LSS ||
        oper == opr::BOOL_GRT || oper == opr::BOOL_LEQ || oper == opr::BOOL_GEQ;
};

// loads the file `fname` and instantiates
// a file parsing object
fn load(fname: str) (*file | CMP_ERR) = {
    // debug info
    if(stacktrace)
        fmt::printfln("loading file \"{}\"", fname)!;
    
    // open file or rise an error
    let fsrc = match(os::open(fname)){
    case let f: io::file => yield f;
    case let e: fs::error =>
        return fmt::asprintf("{}:{} {}", fname, CMD[cmd::DEF],
            lower(fs::strerror(e))): LDDFAIL;
    };
    defer io::close(fsrc)!;

    let src = alloc(file {
        name = fname,
        lin = 0 , cln = 0,
        ptr = 0 , end = 0,
        lst = 0, src = [],
        iseol = false,
        eolat = null,
    });
    // load every line until EOF
    let lastc = 0: size;
    for(true) match(bufio::read_line(fsrc)!){
        case io::EOF => break;
        case let l: []u8 =>
            append(src.src, l...);
            append(src.src, '\n');
    };
    return src;
};

// returns the next token or end of file
// returns a compilation error on invalid tokens
fn nxttk(f: *file, rev: bool = false) (tok | CMP_ERR) = {
    const strsrc = tostr(f.src);
    if(rev) setptr(f);

    let tkv: []u8 = [];
    f.cln = f.end;

    const max = len(f.src);
    if(f.ptr >= max) return eol;

    for(f.ptr < max; incptr(f)){
        let chr = f.src[f.ptr];

        if(iswsp(chr)){
            continue;
        } else if(chr == '"'){
            incptr(f, true);
            return parse_str(f)?;
        } else if(chr == '\''){
            incptr(f, true);
            return parsechar(f)?;
        } else if(chr == ';'){
            incptr(f);
            return eol;
        } else {
            // comments
            if(chr == '/'){
                // single line
                if(f.src[f.ptr + 1] == '/'){
                    f.end = 0;
                    const end = strings::index(strings::sub(strsrc, f.ptr + 1), "\n"): size;
                    f.ptr = f.ptr + end + 1;
                    f.lin += 1;
                    f.lst = f.ptr;
                    f.end = 0;
                    f.cln = f.end;
                    return eol;
                // multiple lines
                } else if(f.src[f.ptr + 1] == '*'){
                    let depth = 1z;
                    setptr(f);
                    incptr(f);
                    assert(len(tkv) == 0);
                    const dup = alloc(*f);
                    for(f.ptr < max; incptr(f)){
                        if(f.ptr + 1 < max){
                            if(f.src[f.ptr] == '/' && f.src[f.ptr + 1] == '*'){
                                setptr(f);
                                depth += 1;
                            } else if(f.src[f.ptr] == '*' && f.src[f.ptr + 1] == '/'){
                                if(depth == 0){
                                    return unimsg {
                                        msg = "invalid trailing symbol found here",
                                        tip = void,
                                        ptr = f,
                                    }: GENERIC;
                                };
                                depth -= 1;
                                incptr(f);
                                if(depth == 0) break;
                            };
                        };
                    };
                    if(depth > 0){
                        setptr(f, true);
                        return unimsg {
                            msg = "unclosed commend block found here",
                            tip = void,
                            ptr = dup,
                        }: GENERIC;
                    };
                    incptr(f);
                    return eol;
                };
            };
            // trailing closing commend block
            if(f.ptr + 1 < max && f.src[f.ptr] == '*' && f.src[f.ptr + 1] == '/'){
                incptr(f);
                return unimsg {
                    msg = "invalid trailing symbol found here",
                    tip = void,
                    ptr = f,
                }: GENERIC;
            };
            // just text
            if(istxt(chr)){
                append(tkv, chr);
                // it's the last valid character
                if(!istxt(f.src[f.ptr + 1]) || f.ptr == max - 1){
                    let val = tostr(tkv);
                    for(let k = 0; k < kwd::KWRD_END; k += 1){
                        if(val == kwdv[k]){
                            incptr(f);
                            return k: kwd;
                        };
                    };
                    const numexp = strings::replace(val, "_", "");
                    const numlen = len(numexp);
                    match(strconv::stou64(numexp)){
                    case let n: u64 =>
                        incptr(f);
                        return n: num;
                    case strconv::overflow =>
                        return unimsg {
                            msg = fmt::asprintf("number overflow: this literal exceeds 64-bits"),
                            tip = void,
                            ptr = f,
                        }: GENERIC;
                    case =>
                        // check number base prefix
                        if(strings::hasprefix(numexp, "0x")){
                            const chk =
                                if(len(numexp) > 2){
                                    let i = 2z;
                                    for(i < numlen; i += 1){
                                        if(i + 1 < numlen)
                                        if(strings::sub(numexp, i, i + 1) != "0") break;
                                        if(i == numlen - 1){
                                            incptr(f);
                                            return 0: u64: num;
                                        };
                                    };
                                    yield i;
                                } else {
                                    return unimsg {
                                        msg = fmt::asprintf("invalid hex literal"),
                                        tip = void,
                                        ptr = f,
                                    }: GENERIC;
                                };
                            match(strconv::stou64(strings::sub(numexp, chk), strconv::base::HEX_LOWER)){
                            case let n: u64 =>
                                incptr(f);
                                return n: num;
                            case strconv::overflow =>
                                return unimsg {
                                    msg = fmt::asprintf("number overflow: this literal exceeds 64-bits"),
                                    tip = void,
                                    ptr = f,
                                }: GENERIC;
                            case =>
                                return unimsg {
                                    msg = fmt::asprintf("invalid hex literal"),
                                    tip = void,
                                    ptr = f,
                                }: GENERIC;
                            };
                        };
                        if(strings::hasprefix(numexp, "0o")){
                            const chk =
                                if(len(numexp) > 2){
                                    let i = 2z;
                                    for(i < numlen; i += 1){
                                        if(i + 1 < numlen)
                                        if(strings::sub(numexp, i, i + 1) != "0") break;
                                        if(i == numlen - 1){
                                            incptr(f);
                                            return 0: u64: num;
                                        };
                                    };
                                    yield i;
                                } else {
                                    return unimsg {
                                        msg = fmt::asprintf("invalid hex literal"),
                                        tip = void,
                                        ptr = f,
                                    }: GENERIC;
                                };
                            match(strconv::stou64(strings::sub(numexp, chk), strconv::base::OCT)){
                            case let n: u64 =>
                                incptr(f);
                                return n: num;
                            case strconv::overflow =>
                                return unimsg {
                                    msg = fmt::asprintf("number overflow: this literal exceeds 64-bits"),
                                    tip = void,
                                    ptr = f,
                                }: GENERIC;
                            case =>
                                return unimsg {
                                    msg = fmt::asprintf("invalid octal literal"),
                                    tip = void,
                                    ptr = f,
                                }: GENERIC;
                           };
                        };
                        if(strings::hasprefix(numexp, "0b")){
                            const chk =
                                if(len(numexp) > 2){
                                    let i = 2z;
                                    for(i < numlen; i += 1){
                                        if(i + 1 < numlen)
                                        if(strings::sub(numexp, i, i + 1) != "0") break;
                                        if(i == numlen - 1){
                                            incptr(f);
                                            return 0: u64: num;
                                        };
                                    };
                                    yield i;
                                } else {
                                    return unimsg {
                                        msg = fmt::asprintf("invalid hex literal"),
                                        tip = void,
                                        ptr = f,
                                    }: GENERIC;
                                };
                            match(strconv::stou64(strings::sub(numexp, chk), strconv::base::OCT)){
                            case let n: u64 =>
                                incptr(f);
                                return n: num;
                            case strconv::overflow =>
                                return unimsg {
                                    msg = fmt::asprintf("number overflow: this literal exceeds 64-bits"),
                                    tip = void,
                                    ptr = f,
                                }: GENERIC;
                            case =>
                                return unimsg {
                                    msg = fmt::asprintf("invalid binary literal"),
                                    tip = void,
                                    ptr = f,
                                }: GENERIC;
                           };
                        };
                        incptr(f);
                        if(f.src[f.ptr] == '\''){
                            for(f.ptr < max && f.src[f.ptr] == '\''; incptr(f)){
                                append(tkv, '.');
                                append(tkv, 'p');
                            };
                            val = tostr(tkv);
                        };
                        return val: idt;
                    };
                };
            } else {
                let idx = f.ptr;
                for(idx < max; idx += 1){
                    const nxtc = f.src[idx];
                    if(istxt(nxtc) || iswsp(nxtc)){
                        break;
                    };
                };
                assert(idx > f.ptr);

                const slc = tostr(f.src[f.ptr..(idx)]);
                let last = 0z;
                let lst_l = 0z;

                let oprc = opr::NOT_OPER;
                for(let o = 0; o < opr::OPER_END; o += 1){
                    const olen = len(oprv[o]);
                    if(olen > len(slc)) continue;

                    const sub = strings::sub(slc, 0, len(oprv[o]));
                    if(sub == oprv[o] && lst_l < olen){
                        oprc = o: opr;
                        last = olen;
                        lst_l = olen;
                    };
                };
                if(oprc != opr::NOT_OPER){
                    f.ptr += last - 1;
                    f.end += last - 1;
                    incptr(f);
                    return oprc;
                };
                lst_l = 0;
                let symc = sym::NOT_SYMB;
                for(let s = 0; s < sym::SYMB_END; s += 1){
                    const slen = len(symv[s]);
                    if(slen > len(slc)) continue;

                    const sub = strings::sub(slc, 0, slen);
                    if(sub == symv[s] && lst_l < slen){
                        symc = s: sym;
                        last = slen;
                        lst_l = slen;
                    };
                };
                if(symc != sym::NOT_SYMB){
                    f.ptr += last - 1;
                    f.end += last - 1;
                    incptr(f);
                    return symc;
                };

                return bi_msg {
                    lft = "valid identifier, keyword, operator or symbol",
                    rgt = fmt::asprintf("\"{}\"", slc),
                    tip = void,
                    ptr = f,
                }: EXPECTD;
            };
        };
    };
    assert(false, "unhandled lexer path");
    return eol;
};

fn _nxttk(f: *file, rev: bool = false) (tok | CMP_ERR) = {
    let t = _nxttk(f, rev)?;
    fmt::println(tktostr(t, true), gen_pos(f))!;
    return t;
};

// jumps `num` tokens and checks if it's is/in `tkns`.
// returns it if yes, otherwise returns void.
fn ahead(f: *file, num: size, tkns: (tok | []tok)) (tok | void | CMP_ERR) = {
    const valid =
        match(tkns){
        case let one: tok =>
            yield [one]: []tok;
        case let lot: []tok =>
            yield lot;
        };
    setptr(f);
    let next = eol: tok;
    for(let i = 0z; i < num; i += 1){
        next = nxttk(f)?;
    };
    for(let tkn .. valid){
        if(cmp_tok(next, tkn)){
            setptr(f, true);
            return next;
        };
    };
    setptr(f, true);
};

// asserts `eql`, returning an error if false
fn expct(eql: bool, tk: tok, f: *file, e: CMP_ERR, msg: str, tip: (str | void) = void) (tok | CMP_ERR) = {
    if(!eql){
        match(e){
        case INVALID =>
            return unimsg {
                msg = msg,
                tip = tip,
                ptr = f,
            }: INVALID;
        case EXPECTD =>
            return bi_msg {
                lft = msg,
                rgt = tktostr(tk, false),
                tip = tip,
                ptr = f,
            }: EXPECTD;
        case UNDEFNS =>
            return unimsg {
                msg = msg,
                tip = tip,
                ptr = f,
            }: UNDEFNS;
        case MISMTCH =>
            return unimsg {
                msg = msg,
                tip = tip,
                ptr = f,
            }: MISMTCH;
        case CANT_DO =>
            return unimsg {
                msg = msg,
                tip = tip,
                ptr = f,
            }: CANT_DO;
        case GENTODO =>
            return unimsg {
                msg = msg,
                tip = tip,
                ptr = f,
            }: GENTODO;
        case NOTCALL =>
            return unimsg {
                msg = tk: str,
                tip = tip,
                ptr = f,
            }: NOTCALL;
        case GENERIC =>
            return unimsg {
                msg = msg,
                tip = tip,
                ptr = f,
            }: GENERIC;
        case =>
            return ("unhandled error case", f): UNREACH;
        };
    } else {
        return tk: tok;
    };
};

fn check(f: *file, stt: kwd) (void | CMP_ERR) = {
    let next = nxttk(f)?;
};

fn mtchs(s: sym, f: *file, restore: bool = true) (u64 | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("matching symbol \"{}\" at {}", symv[s], gen_pos(f))!;


    const safe = *f;
    let depth = 1z;
    const max = len(f.src);
    let dup = alloc(*f);
    for(f.ptr < max){
        const next = nxttk(f)?;
        if(cmp_tok(next: tok, s: tok)){
            depth += 1;
            free(dup);
            dup = alloc(*f);
        } else if(cmp_tok(next: tok, (s + 1): tok)){
            if(depth == 0){
                free(dup);
                return unimsg {
                    msg = "invalid trailing symbol found here",
                    tip = void,
                    ptr = f,
                }: GENERIC;
            };
            depth -= 1;
            if(depth == 0) {
                if(restore){
                    *f = safe;
                };
                free(dup);
                return f.ptr;
            };
        };
    };
    if(depth > 0){
        return unimsg {
            msg = fmt::asprintf("the simbol {} is unclosed", fmtc(symv[s], cmd::YEL)),
            tip = void,
            ptr = dup,
        }: GENERIC;
    };
    assert(false);
    return 0;
};

// moves the parser to the first instance of `t`
fn jmpto(t: tok, f: *file, before: bool = false) (void | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("jumping to {} at {}", tktostr(t, true), gen_pos(f))!;
    for(let next = nxttk(f, before)?; !(next is eol) && !cmp_tok(next: tok, t)){
        next = nxttk(f, before)?;
    };
    setptr(f, before);
};

fn gotop(f: *file, p: size) (void | CMP_ERR) = {
    let next = nxttk(f)?;
    for(f.ptr < p){
        next = nxttk(f)?;
    };
};

fn skip_field(f: *file) (void | CMP_ERR) = {
    if(stacktrace)
        fmt::println("skiping fields")!;
    let next = nxttk(f, true)?;
    for(cmp_tok(next, opr::MODFIELD) || next is idt){
        next = nxttk(f, true)?;
    };
    setptr(f, true);
};

// checks if it is end of line
fn iseol(f: *file) (bool | CMP_ERR) = {
    if(f.ptr >= len(f.src)) return true;
    if(f.src[f.ptr] == ';' || f.src[f.ptr - 1] == ';') return true;

    const dummy = nxttk(f, true)?;
    if(dummy is eol) return true;
    setptr(f, true);
    return false;
};

fn finsh(f: *file, err: CMP_ERR, msg: str) (void | CMP_ERR) = {
    const end = nxttk(f)?;
    expct(end is eol, end, f, err, msg)?;
};

// assert it's not end of the line
fn noeol(f: *file, msg: str, tip: (str | void) = void) (void | CMP_ERR) = {
    setptr(f);
    const dummy = nxttk(f)?;

    if(dummy is eol){
        return bi_msg {
            lft = msg,
            rgt = "end of file",
            tip = tip,
            ptr = f,
        }: EXPECTD;
    } else {
        setptr(f, true);
    };
};

// parses a string
fn parse_str(f: *file) (num | txt | CMP_ERR) = {
    let onstr = true;
    let escpd = false;
    let tkv: []u8 = [];

    const max = len(f.src);
    for(onstr && f.ptr < max; incptr(f, onstr)){
        const chr = f.src[f.ptr];
        switch(chr){
            case '\'' =>
                append(tkv, chr);
            case '"' =>
                if(!escpd){
                    onstr = !onstr;
                    escpd = false;
                } else {
                    append(tkv, '\\');
                    append(tkv, chr);
                    escpd = false;
                };
            case '\\' =>
                if(escpd){
                    append(tkv, '\\');
                    escpd = false;
                } else {
                    escpd = true;
                };
            case 't', 'b', 'a', 'r', 'n', 'f', '0' =>
                if(escpd){
                    append(tkv, '\\');
                    escpd = false;
                };
                append(tkv, chr);
            case =>
                if(escpd){
                    return unimsg {
                        msg = fmt::asprintf("invalid escape char {}", chr: rune),
                        tip = void,
                        ptr = f,
                    }: GENERIC;
                };
                append(tkv, chr);
        };
    };
    return tkv: txt;
};

// parses a character literal
fn parsechar(f: *file) (num | CMP_ERR) = {
    let onstr = true;
    let escpd = false;
    let tkv: []u8 = [];

    const max = len(f.src);
    for(onstr && f.ptr < max; incptr(f, onstr)){
        const chr = f.src[f.ptr];
        switch(chr){
            case '\'' =>
                if(!escpd){
                    onstr = !onstr;
                    escpd = false;
                } else {
                    append(tkv, chr);
                    escpd = false;
                };
            case '"' =>
                append(tkv, chr);
            case '\\' =>
                if(escpd){
                    append(tkv, '\\');
                    escpd = false;
                } else {
                    escpd = true;
                };
            case 't' =>
                if(escpd){
                    append(tkv, '\t');
                    escpd = false;
                } else {
                    append(tkv, chr);
                };
            case 'b' =>
                if(escpd){
                    append(tkv, '\b');
                    escpd = false;
                } else {
                    append(tkv, chr);
                };
            case 'a' =>
                if(escpd){
                    append(tkv, '\a');
                    escpd = false;
                } else {
                    append(tkv, chr);
                };
            case 'r' =>
                if(escpd){
                    append(tkv, '\r');
                    escpd = false;
                } else {
                    append(tkv, chr);
                };
            case 'n' =>
                if(escpd){
                    append(tkv, '\n');
                    escpd = false;
                } else {
                    append(tkv, chr);
                };
            case 'f' =>
                if(escpd){
                    append(tkv, '\f');
                    escpd = false;
                } else {
                    append(tkv, chr);
                };
            case '0' =>
                if(escpd){
                    append(tkv, '\0');
                    escpd = false;
                } else {
                    append(tkv, chr);
                };
            case =>
                if(escpd){
                    return unimsg {
                        msg = fmt::asprintf("invalid escape char \"{}\"", chr: rune),
                        tip = void,
                        ptr = f,
                    }: GENERIC;
                };
                append(tkv, chr);
        };
    };
    if(len(tkv) == 1){
        return tkv[0]: u32: num;
    } else {
        return unimsg {
            msg = "invalid character literal",
            tip = void,
            ptr = f,
        }: GENERIC;
    };
};

fn truelen(txt: str) size = {
    static const pairs =
        [ ("\\t", "\t"), ("\\b", "\b")
        , ("\\a", "\a"), ("\\r", "\r")
        , ("\\n", "\n"), ("\\f", "\f")
        , ("\\0", "\0")
        ];
    let fix = txt;
    for(let p .. pairs){
        fix = strings::replace(fix, p.0, p.1);
    };
    return len(fix);
};

fn setptr(f: *file, reset: bool = false) void = {
    static let safe = file { ... };
    if(!reset){
        safe = *f;
    } else {
        *f = safe;
    };
};

fn incptr(f: *file, onstr: bool = false) void = {
    const max = len(f.src);
    const lst = f.src[f.ptr];
    f.iseol = false;
    f.end += 1;
    f.ptr += 1;
    if(!onstr)
    for(f.ptr < max){
        const chr = f.src[f.ptr];
        if(chr == '\n'){
            f.iseol = true;
            f.eolat = alloc(*f);
            f.lin += 1;
            f.ptr += 1;
            f.lst = f.ptr;
            f.end = 0;
            f.cln = f.end;
        } else if(iswsp(chr)){
            f.end += 1;
            f.ptr += 1;
        } else break;
    };
};
