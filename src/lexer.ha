use os;
use io;
use fs;
use fmt;
use bufio;
use strlib;
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
        case kwd =>
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
        case eol =>
            return "end of line";
    };
};

fn tostr(src: []u8) str = {
    // TODO: handle this more elegantly
    return strings::fromutf8(src)!;
};

// compares two tokens
fn cmp_tok(l: tok, r: tok) bool = {
    match(l){
        case num =>
            return r is num && l: num == r: num;
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

fn is_type(tp: tok) bool = {
    if(!(tp is kwd)) return false;
    switch(tp: kwd){
    case kwd::U8__TYPE, kwd::U16_TYPE, kwd::U32_TYPE, kwd::U64_TYPE, kwd::I8__TYPE,
        kwd::I16_TYPE, kwd::I32_TYPE, kwd::I64_TYPE, kwd::RATIO__T, kwd::STRING_T, kwd::UNITTYPE =>
        return true;
    case => return false;
    };
};

fn is_asg_opr(oper: tok) bool = {
    if(oper is opr){
        const op = oper: opr;
        return op == opr::ASSIGNMT || op == opr::INCREMNT || op == opr::DECREMNT;
    };
    return false;
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
        case => //let e: fs::error =>
            // TODO: specific messages for different filesystem errors
            return fname: LDDFAIL;
    };
    defer io::close(fsrc)!;

    let src = alloc(file {
        name = fname,
        lin = 0 , cln = 0,
        ptr = 0 , end = 0,
        lst = 0, src = [],
    });
    // load every line until EOF
    let lastc = 0: size;
    for(true) match(bufio::read_line(fsrc)){
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
    tok_count += 1;
    // debug info
    if(stacktrace && track_nxttk){
        const txt = tostr(f.src);
        const end =
            match(strlib::finda(txt, "\n", f.ptr)){
            case let e: size => yield e;
            case => yield len(txt);
            };
        const src = strings::sub(txt, f.ptr, end);
        fmt::printfln("reading token at {}", gen_pos(f))!;
    };
    if(rev) setptr(f);

    let tkv: []u8 = [];
    f.cln = f.end;

    const max = len(f.src);
    if(f.ptr >= max) return eol;

    for(f.ptr < max; incptr(f)){
        const chr = f.src[f.ptr];

        if(iswsp(chr)){
            continue;
        } else if(chr == '"'){
            incptr(f);
            return parse_str(f)?;
        } else if(chr == '\''){
            incptr(f);
            return parsechar(f)?;
        } else if(chr == ';'){
            incptr(f);
            return eol;
        } else {
            // comments
            // TODO: multiple line comments
            if(chr == '/' && f.src[f.ptr + 1] == '/'){
                f.end = 0;
                match(strlib::finda(tostr(f.src), "\n", f.ptr)){
                case let i: size =>
                    f.ptr = i + 1;        
                    f.lin += 1;
                    f.lst = f.ptr;
                    f.end = 0;
                    f.cln = f.end;
                    return eol;
                case =>
                    assert(false);
                    return eol;
                };
            };
            // just text
            if(istxt(chr)){
                append(tkv, chr);

                // it's the last valid character
                if(f.ptr == max - 1 || !istxt(f.src[f.ptr + 1])){
                    let val = tostr(tkv);
                    for(let k = 0; k < kwd::KWRD_END; k += 1){
                        if(val == kwdv[k]){
                            incptr(f);
                            return k: kwd;
                        };
                    };
                    // TODO: handle different numerical bases
                    match(strconv::stou64(strlib::replace(val, "_", ""))){
                    case let n: u64 =>
                        incptr(f);
                        return n: num;
                    case =>
                        incptr(f);
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

fn mtchs(s: sym, f: *file, restore: bool = true) (u64 | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("matching symbol \"{}\" at {}", symv[s], gen_pos(f))!;

    noeol(f, "matching symbol")?;
    if(restore) setptr(f);

    let depth = 1z;
    const max = len(f.src);
    for(let next = nxttk(f)?; f.ptr < max; next = nxttk(f)?){
        if(next is eol) continue;
        if(cmp_tok(next: tok, s: tok)){
            depth += 1;
        } else if(cmp_tok(next: tok, (s + 1): tok)){
            if(depth == 0){
                return unimsg {
                    msg = "invalid trailing symbol found here",
                    tip = void,
                    ptr = f,
                }: GENERIC;
            };
            depth -= 1;
            if(depth == 0) {
                if(restore) setptr(f, true);
                return f.ptr;
            };
        };
    };
    if(depth > 0){
        return unimsg {
            msg = "unclosed symbol found here",
            tip = void,
            ptr = f,
        }: GENERIC;
    };
    assert(false);
    return 0;
};

// moves the parser to the first instance of `t`
fn jmpto(t: tok, f: *file, before: bool = false) (void | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("jumping to {}", tktostr(t, true))!;
    for(let next = nxttk(f, before)?; !(next is eol) && !cmp_tok(next: tok, t)){
        next = nxttk(f, before)?;
    };
    setptr(f, before);
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
            case '"' =>
                if(!escpd){
                    onstr = !onstr;
                    escpd = false;
                } else {
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
                        msg = fmt::asprintf("invalid escape char {}", chr: rune),
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

fn setptr(f: *file, reset: bool = false) void = {
    static let safe_l = 0z;
    static let safe_p = 0z;
    static let safe_c = 0z;
    static let safe_e = 0z;
    static let safels = 0z;

    if(!reset){
        safe_l = f.lin;
        safe_p = f.ptr;
        safe_c = f.cln;
        safe_e = f.end;
        safels = f.lst;
    } else {
        f.lin = safe_l;
        f.ptr = safe_p;
        f.cln = safe_c;
        f.end = safe_e;
        f.lst = safels;
    };
};

fn incptr(f: *file, onstr: bool = false) void = {
    const max = len(f.src);
    const lst = f.src[f.ptr];
    f.end += 1;
    f.ptr += 1;

    if(!onstr)
    for(f.ptr < max){
        const chr = f.src[f.ptr];
        if(chr == '\n'){
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
