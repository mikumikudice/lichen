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
                return fmt::asprintf("an identifier ({})", tk: idt);
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
                return fmt::asprintf("a keyword ({})", kwdv[tk: kwd]);
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
        case eos =>
            return "end of statement";
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
            if(!(r is num)) return false;
            return n: u64 == r: num: u64;
        case let this: txt =>
            if(!(r is num)) return false;
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
            if(!(r is idt)) return false;
            return r is idt && this: str == r: idt: str;
        case kwd =>
            if(!(r is kwd)) return false;
            return r is kwd && l: kwd == r: kwd;
        case opr =>
            if(!(r is opr)) return false;
            return r is opr && l: opr == r: opr;
        case sym =>
            if(!(r is sym)) return false;
            return r is sym && l: sym == r: sym;
        case eos =>
            return r is eos;
        case eol =>
            return r is eol;
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
    const stt =
        if(f.lst > 0){
            yield f.lst;
        } else {
            yield 0z;
        };
    const max = len(txt);
    const idx = strings::index(strings::sub(txt, stt), "\n"): size;
    const end =
        if(stt + idx > max){
            yield max;
        } else {
            yield stt + idx;
        };
    const out = strings::sub(txt, stt, end);
    return strings::replace(out, "\t", " ");
};

fn is_type(tp: tok) bool = {
    if(!(tp is kwd)) return false;
    switch(tp: kwd){
    case kwd::U8__TYPE, kwd::U16_TYPE, kwd::U32_TYPE, kwd::U64_TYPE, kwd::I8__TYPE,
        kwd::I16_TYPE, kwd::I32_TYPE, kwd::I64_TYPE, kwd::F32_TYPE, kwd::F64_TYPE,
        kwd::STRING_T, kwd::UNITTYPE, kwd::VOIDTYPE =>
        return true;
    case => return false;
    };
};

fn is_cmp(oper: opr, skip: bool = false) bool = {
    if(!skip){
        return oper == opr::BOOL_EQL || oper == opr::BOOL_DIF || oper == opr::BOOL_LSS ||
            oper == opr::BOOL_GRT || oper == opr::BOOL_LEQ || oper == opr::BOOL_GEQ;
    } else {
        return oper == opr::BOOL_LSS || oper == opr::BOOL_GRT || oper == opr::BOOL_LEQ ||
            oper == opr::BOOL_GEQ;
    };
};

fn is_opr(oper: opr) bool = {
    return oper <= opr::ARTH_REM;
};

fn is_unry(oper: opr) bool = {
    return oper == opr::ARTH_PLS || oper == opr::ARTH_MIN || oper == opr::LOGICNOT;
};

// loads the file `fname` and instantiates
// a file parsing object
fn load(fname: str) (*file | COMP_ERR) = {
    // open file or rise an error
    let fsrc = match(os::open(fname)){
    case let f: io::file => yield f;
    case let e: fs::error =>
        return fmt::asprintf("{}:{} {}", fname, CMD[cmd::DEF],
            lower(fs::strerror(e))): FILE_ERR;
    };
    defer io::close(fsrc)!;

    const (name, _) = rem_path(fname);
    let src = alloc(file {
        name = name,
        lin = 0, cln = 0,
        ptr = 0, lst = 0,
        src = [], ...
    });
    // load every line until EOF
    let lastc = 0: size;
    for(true) match(bufio::read_line(fsrc)!){
        case io::EOF => break;
        case let l: []u8 =>
            append(src.src, l...);
            append(src.src, '\n');
    };
    if(len(src.src) == 0){
        fmt::fatalf("the file {} is empty\n\ntry adding:\n{}",
            fmtc(fname, cmd::BLU), fmtc(fn_demo, cmd::GRN));
    };
    return src;
};

// returns the next token or end of file
// returns a compilation error on invalid tokens
fn nxttk(f: *file, rev: bool = false) (tok | COMP_ERR) = {
    if(rev) setptr(f);

    let tkv: []u8 = [];
    const strsrc = tostr(f.src);
    const max = len(f.src);
    if(f.ptr >= max) return eol;

    f.last = (f.lin, f.cln, f.ptr, f.lst);
    for(f.ptr < max; incptr(f)){
        let chr = f.src[f.ptr];
        if(chr == '"'){
            f.ptr += 1;
            f.cln = f.ptr - f.lst;
            return parse_str(f)?;
        } else if(chr == '\''){
            f.ptr += 1;
            f.cln = f.ptr - f.lst;
            return parsechar(f)?;
        } else if(chr == ';'){
            f.cln = f.ptr - f.lst;
            incptr(f);
            return eos;
        } else {
            // comments
            if(chr == '/'){
                const l = f.lst;
                // single line
                if(f.src[f.ptr + 1] == '/'){
                    const end = strings::index(strings::sub(strsrc, f.ptr), "\n"): size;
                    f.lst = f.ptr;
                    f.ptr += end;
                    fmt::println(end)!;
                    f.lin += 1;

                    setptr(f);
                    incptr(f);
                    if(l == 0z && f.ptr == len(f.src)){
                        fmt::fatalf("the file {} is empty\n\ntry adding:\n{}",
                            fmtc(f.name, cmd::BLU), fmtc(fn_demo, cmd::GRN));
                    };
                    continue;
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
                                    return errmsg(f, "invalid trailing symbol found here");
                                };
                                depth -= 1;
                                incptr(f);
                                if(depth == 0) break;
                            };
                        };
                    };
                    if(depth > 0){
                        setptr(f, true);
                        return errmsg(f, "unclosed commend block found here");
                    };
                    setptr(f);
                    incptr(f);
                    if(l == 0z && f.ptr == len(f.src)){
                        fmt::fatalf("the file {} is empty\n\ntry adding:\n{}",
                            fmtc(f.name, cmd::BLU), fmtc(fn_demo, cmd::GRN));
                    };
                    setptr(f, true);
                    continue;
                };
            };
            // trailing closing commend block
            if(f.ptr + 1 < max && f.src[f.ptr] == '*' && f.src[f.ptr + 1] == '/'){
                incptr(f);
                return errmsg(f, "invalid trailing symbol found here");
            };
            // just text
            if(istxt(chr)){
                append(tkv, chr);
                f.cln = f.ptr - f.lst - len(tkv) + 1;
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
                        return errmsg(f, "64-bit literal overflow");
                    case =>
                        // check number base prefix
                        if(strings::hasprefix(numexp, "0x")){
                            match(strconv::stou64(strings::sub(numexp, 2), strconv::base::HEX)){
                            case let n: u64 =>
                                incptr(f);
                                return n: num;
                            case strconv::overflow =>
                                return errmsg(f, "64-bit hexadecimal literal overflow");
                            case =>
                                return errmsg(f, "invalid hexadecimal literal");
                            };
                        };
                        if(strings::hasprefix(numexp, "0o")){
                            match(strconv::stou64(strings::sub(numexp, 2), strconv::base::OCT)){
                            case let n: u64 =>
                                incptr(f);
                                return n: num;
                            case strconv::overflow =>
                                return errmsg(f, "64-bit octal literal overflow");
                            case =>
                                return errmsg(f, "invalid octal literal");
                           };
                        };
                        if(strings::hasprefix(numexp, "0b")){
                            match(strconv::stou64(strings::sub(numexp, 2), strconv::base::BIN)){
                            case let n: u64 =>
                                incptr(f);
                                return n: num;
                            case strconv::overflow =>
                                return errmsg(f, "64-bit binary literal overflow");
                            case =>
                                return errmsg(f, "invalid binary literal");
                            };
                        };
                        incptr(f);
                        if(f.src[f.ptr] == '\''){
                            for(f.ptr < max && f.src[f.ptr] == '\''; incptr(f)){
                                append(tkv, '.');
                                append(tkv, 'p');
                            };
                        };
                        return tostr(tkv): idt: tok;
                    };
                };
            } else {
                let idx = f.ptr;
                for(idx < max){
                    idx += 1;
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
                    f.cln = f.ptr - f.lst - len(oprv[oprc]) + 1;
                    f.last = (f.lin, f.cln, f.ptr, f.lst);
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
                    f.cln = f.ptr - f.lst - len(symv[symc]) + 1;
                    f.last = (f.lin, f.cln, f.ptr, f.lst);
                    incptr(f);
                    return symc;
                };
                f.cln = f.ptr - f.lst;
                return errmsg(f, "expected valid identifier, keyword, operator or symbol");
            };
        };
    };
    return errmsg(f, "unhandled lexer path");
};

fn _nxttk(f: *file, rev: bool = false) (tok | COMP_ERR) = {
    const t = _nxttk(f, rev)?;
    fmt::println(tktostr(t, true), gen_pos(f))!;
    return t;
};

fn puttk(f: *file) void = {
    assert(f.ptr > 0);
    f.lin = f.last.0;
    f.cln = f.last.1;
    f.ptr = f.last.2;
    f.lst = f.last.3;
};

fn getltkp(f: *file) *file = {
    const dup = alloc(*f);
    puttk(dup);
    return dup;
};

// jumps `num` tokens and checks if it's is/in `tkns`.
// returns it if yes, otherwise returns void.
fn ahead(f: *file, tkns: (tok | []tok), num: size = 1) (tok | void | COMP_ERR) = {
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
fn expct(eql: bool, tk: tok, f: *file, msg: str, tip: (str | void) = void) (tok | COMP_ERR) = {
    if(!eql){
       return errmsg(f, msg, tip);
    } else {
        return tk;
    };
};

// finds the coresponding symbol of `s`. returns an error if none is found
// if restore is set to false, the file will point to the found symbol
fn mtchs(s: sym, f: *file, restore: bool = true) (size | COMP_ERR) = {
    assert(s <= sym::CLOSEPAR);
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
            if(depth == 0z){
                free(dup);
                return errmsg(dup, "invalid trailing symbol");
            };
            depth -= 1;
            if(depth == 0) {
                const r = f.ptr;
                free(dup);
                if(restore){
                    *f = safe;
                };
                return r;
            };
        };
    };
    if(depth > 0z){
        return errmsg(dup, "unclosed symbol");
    };
    assert(false);
    return 0z;
};

// moves the parser to the first instance of `t`
fn jmpto(t: tok, f: *file, before: bool = false) (void | COMP_ERR) = {
    for(let next = nxttk(f, before)?; !cmp_tok(next: tok, t)){
        next = nxttk(f, before)?;
    };
    setptr(f, before);
};

// checks if it is end of statement
fn iseos(f: *file) (bool | COMP_ERR) = {
    if(f.ptr >= len(f.src)) return true;
    if(f.src[f.ptr] == ';' || f.src[f.ptr - 1] == ';') return true;

    const dummy = nxttk(f, true)?;
    if(dummy is eos) return true;
    setptr(f, true);
    return false;
};

// expects to be end of statement
fn finsh(f: *file, msg: str, tip: (str | void) = void) (void | COMP_ERR) = {
    const end = nxttk(f)?;
    expct(end is eos, end, f, msg, tip)?;
};

// parses a string
fn parse_str(f: *file) (num | txt | COMP_ERR) = {
    let onstr = true;
    let escpd = false;
    let tkv: []u8 = [];

    const max = len(f.src);
    for(onstr && f.ptr < max; incptr(f, true)){
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
            case 't' =>
                if(!escpd){
                    append(tkv, chr);
                } else {
                    append(tkv, '\t');
                    escpd = false;
                };
            case 'b' =>
                if(!escpd){
                    append(tkv, chr);
                } else {
                    append(tkv, '\b');
                    escpd = false;
                };
            case 'a' =>
                if(!escpd){
                    append(tkv, chr);
                } else {
                    append(tkv, '\a');
                    escpd = false;
                };
            case 'r' =>
                if(!escpd){
                    append(tkv, chr);
                } else {
                    append(tkv, '\r');
                    escpd = false;
                };
            case 'n' =>
                if(!escpd){
                    append(tkv, chr);
                } else {
                    append(tkv, '\n');
                    escpd = false;
                };
            case 'f' =>
                if(!escpd){
                    append(tkv, chr);
                } else {
                    append(tkv, '\f');
                    escpd = false;
                };
            case '0' =>
                if(!escpd){
                    append(tkv, chr);
                } else {
                    append(tkv, '\0');
                    escpd = false;
                };
            case =>
                if(escpd){
                    return errmsg(f, "invalid character literal");
                };
                append(tkv, chr);
        };
    };
    return tkv: txt;
};

// parses a character literal
fn parsechar(f: *file) (num | COMP_ERR) = {
    let onstr = true;
    let escpd = false;
    let tkv: u8 = 0;

    const max = len(f.src);
    for(onstr && f.ptr < max; incptr(f, true)){
        const chr = f.src[f.ptr];
        switch(chr){
            case '\'' =>
                if(escpd){
                    tkv = chr;
                    escpd = false;
                };
                break;
            case '"' =>
                tkv = chr;
                break;
            case '\\' =>
                if(escpd){
                    tkv = '\\';
                    escpd = false;
                    break;
                } else {
                    escpd = true;
                };
            case 't' =>
                if(escpd){
                    tkv = '\t';
                } else {
                    tkv = chr;
                };
                break;
            case 'b' =>
                if(escpd){
                    tkv = '\b';
                    escpd = false;
                } else {
                    tkv = chr;
                };
                break;
            case 'a' =>
                if(escpd){
                    tkv = '\a';
                    escpd = false;
                } else {
                    tkv = chr;
                };
                break;
            case 'r' =>
                if(escpd){
                    tkv = '\r';
                    escpd = false;
                } else {
                    tkv = chr;
                };
                break;
            case 'n' =>
                if(escpd){
                    tkv = '\n';
                    escpd = false;
                } else {
                    tkv = chr;
                };
                break;
            case 'f' =>
                if(escpd){
                    tkv = '\f';
                    escpd = false;
                } else {
                    tkv = chr;
                };
                break;
            case '0' =>
                if(escpd){
                    tkv = '\0';
                    escpd = false;
                } else {
                    tkv = chr;
                };
                break;
            case =>
                if(escpd){
                    return errmsg(f, "invalid character literal");
                };
                tkv = chr;
                break;
        };
    };
    if(f.ptr < max - 1 && f.src[f.ptr + 1] == '\''){
        return tkv: u32: num;
    } else {
        return errmsg(f, "invalid character literal");
    };
};

// unescapes string escaped characters
fn rawstr(src: txt) str = {
    static const pairs =
        [ ("\t", "\\t"), ("\b", "\\b")
        , ("\a", "\\a"), ("\r", "\\r")
        , ("\n", "\\n"), ("\f", "\\f")
        , ("\0", "\\0"), ("\"", "\\\""),
        ];
    let fix = strings::dup(tostr(src));
    for(let p .. pairs){
        fix = strings::replace(fix, p.0, p.1);
    };
    return fix;
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
    f.ptr += 1;
    if(!onstr)
    for(f.ptr < max){
        const chr = f.src[f.ptr];
        if(chr == '\n'){
            f.lin += 1;
            f.ptr += 1;
            f.cln = 0;
            f.lst = f.ptr;
        } else if(iswsp(chr)){
            f.ptr += 1;
        } else break;
    };
};
