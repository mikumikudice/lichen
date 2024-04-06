use os;
use io;
use fs;
use fmt;

use bufio;
use strings;
use strconv;
use encoding::utf8;

fn tktostr(tk: tok, f: *src_file, verb: bool) str = {
    match(tk){
        case eol =>
            return "end of line";
        case num =>
            if(verb){
                return fmt::asprintf("a number ({})", tk: num: u64);
            } else {
                return "a number";
            };
        case txt =>
            match(tk: txt){
                case let string: str =>
                    if(verb){
                        return fmt::asprintf("an identifier ({})", string);
                    } else {
                        return "an identifier";
                    };
                case let asciic: []u8 =>
                    if(verb){
                        return fmt::asprintf("a string literal ({})", toutf(asciic, f)!);
                    } else {
                        return "a string literal";
                    };
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
    };
};

fn toutf(src: []u8, f: *src_file) (str | CMP_ERR) = {
    match(strings::fromutf8(src)){
        case let s: str => return s;
        case =>
            return unimsg {
                msg = "utf8 encoding",
                tip = "some characters in your file may not be encodable by the utf8 standard",
                ptr = f,
            }: INVALID;
    };
};

fn istxt(c: u8) bool = {
    return (c >= 'A' && c <= 'Z')
        || (c >= 'a' && c <= 'z')
        || (c >= '0' && c <= '9')
        || c == '#' || c == '_';
};

fn iswsp(c: u8) bool = {
    return c == ' ' || c == '\t';
};

fn load(file: str) (*src_file | CMP_ERR) = {
    // open file or rise an error
    let fsrc = match(os::open(file)){
        case let f: io::file =>
            yield f;
        case => //let e: fs::error =>
            // TODO: specific messages for different filesystem errors
            return LDDFAIL;
    };
    defer io::close(fsrc)!;

    let src = alloc(src_file {
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

fn parse(file: str) (str | CMP_ERR) = {
    const lin = load(file)?;
    const max = len(lin.src);
    for(lin.ptr < max){
        let tkn = nxttk(lin)?;
        if(tkn is eof) break;

        fmt::println(tktostr(tkn: tok, lin, true))!;
    };
    return "dummy";
};

fn nxttk(f: *src_file) (tok | eof | CMP_ERR) = {
    let onstr = false;
    let escpd = false;

    let tkv: []u8 = [];
    f.cln = f.end;

    const max = len(f.src);
    if(f.ptr >= max) return eol;

    for(f.ptr < max; incptr(f, false)){
        const chr = f.src[f.ptr];

        if(chr == '\n'){
            f.lin += 1;
            f.ptr += 1;
            f.end = 0;
            f.lst = f.ptr;
            continue;
        };
        if(onstr){
            // TODO: add support for character literals
            let (s, e) = parse_str(chr, &tkv, onstr, escpd);
            onstr = s; escpd = e;
            if(!onstr){
                incptr(f, false);
                return tkv: txt;
            };
        } else {
            if(iswsp(chr)){
                continue;
            } else if(chr == '"'){
                onstr = true;
                continue;
            } else if(chr == ';'){
                f.ptr += 1;
                f.end += 1;
                return eol;
            } else {
                // comments
                // TODO: multiple line comments
                if(chr == '#' && f.src[f.ptr + 1] == '#'){
                    f.lin += 1;
                    f.end = 0;

                    f.ptr += finda(toutf(f.src, f)?, "\n", f.ptr)! + 1;
                    f.lst = f.ptr;
                    return eol;
                };
                // just text
                if(istxt(chr)){
                    append(tkv, chr);

                    // it's the last valid character
                    if(f.ptr == max - 1 || !istxt(f.src[f.ptr + 1])){
                        let val = toutf(tkv, f)?;
                        for(let k = 0; k < kwd::KWRD_END; k += 1){
                            if(strings::compare(val, kwdv[k]) == 0){
                                incptr(f, false);
                                return k: kwd;
                            };
                        };
                        // TODO: handle different numerical bases
                        match(strconv::stou64(replace(val, "_", ""))){
                        case let n: u64 =>
                            incptr(f, false);
                            return n: num;
                        case =>
                            incptr(f, false);
                            return val: txt;
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

                    const slc = toutf(
                        f.src[f.ptr..(idx)], f
                    )?;
                    let last = 0: size;

                    let oprc = opr::NOT_OPER;
                    for(let o = 0; o < opr::OPER_END; o += 1){
                        const olen = len(oprv[o]);
                        if(olen > len(slc)) continue;

                        const sub = strings::sub(slc, 0, len(oprv[o]));
                        if(strings::compare(sub, oprv[o]) == 0){
                            oprc = o: opr;
                            last = olen;
                        };
                    };
                    if(oprc != opr::NOT_OPER){
                        f.ptr += last - 1;
                        f.end += last - 1;
                        incptr(f, false);
                        return oprc;
                    };

                    let symc = sym::NOT_SYMB;
                    for(let s = 0; s < sym::SYMB_END; s += 1){
                        const slen = len(symv[s]);
                        if(slen > len(slc)) continue;

                        const sub = strings::sub(slc, 0, slen);
                        if(strings::compare(sub, symv[s]) == 0){
                            symc = s: sym;
                            last = slen;
                        };
                    };
                    if(symc != sym::NOT_SYMB){
                        f.ptr += last - 1;
                        f.end += last - 1;
                        incptr(f, false);
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
    };
    if(f.ptr >= max) return eof;

    assert(false, "unhandled lexer path");
    return eol;
};

fn expct(eql: bool, tk: tok, f: *src_file, e: CMP_ERR, msg: str) (void | CMP_ERR) = {
    if(!eql){
        match(e){
        case INVALID =>
            return unimsg {
                msg = msg,
                tip = void,
                ptr = f,
            }: INVALID;
        case EXPECTD =>
            return bi_msg {
                lft = msg,
                rgt = tktostr(tk, f, false),
                tip = void,
                ptr = f,
            }: EXPECTD;
        case GENERIC =>
            return unimsg {
                msg = msg,
                tip = void,
                ptr = f,
            }: GENERIC;
        case =>
            assert(false, "unreachable");
            return e;
        };
    };
};

fn incptr(f: *src_file, onstr: bool) void = {
    const max = len(f.src);
    f.end += 1;
    f.ptr += 1;

    if(!onstr)
    for(f.ptr < max && iswsp(f.src[f.ptr])){
        f.end += 1;
        f.ptr += 1;
    };
};

fn parse_str(chr: u8, tkv: *[]u8, onstr: bool, escpd: bool) (bool, bool) = {
    switch(chr){
        case '"' =>
            if(!escpd){
                onstr = !onstr;
                escpd = false;
            } else {
                append(tkv, '"');
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
                append(tkv, 't');
            };
        case 'b' =>
            if(escpd){
                append(tkv, '\b');
                escpd = false;
            } else {
                append(tkv, 'b');
            };
        case 'a' =>
            if(escpd){
                append(tkv, '\a');
                escpd = false;
            } else {
                append(tkv, 'a');
            };
        case 'r' =>
            if(escpd){
                append(tkv, '\r');
                escpd = false;
            } else {
                append(tkv, 'r');
            };
        case 'n' =>
            if(escpd){
                append(tkv, '\n');
                escpd = false;
            } else {
                append(tkv, 'n');
            };
        case '0' =>
            if(escpd){
                append(tkv, '\0');
                escpd = false;
            } else {
                append(tkv, '0');
            };
        case =>
            append(tkv, chr);
    };
    return (onstr, escpd);
};
