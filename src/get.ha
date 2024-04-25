use os;
use io;
use fs;
use fmt;
use bufio;
use strings;

fn tostr(src: []u8) str = {
    // TODO: handle this more elegantly
    return strings::fromutf8(src)!;
};

fn istxt(c: u8) bool = {
    return (c >= 'A' && c <= 'Z')
        || (c >= 'a' && c <= 'z')
        || (c >= '0' && c <= '9')
        ||  c == '_';
};

fn iswsp(c: u8) bool = {
    return c == ' ' || c == '\t';
};

fn load(fname: str) (*file | CMP_ERR) = {
    // open file or rise an error
    let fsrc = match(os::open(fname)){
        case let f: io::file =>
            yield f;
        case => //let e: fs::error =>
            // TODO: specific messages for different filesystem errors
            return LDDFAIL;
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
            return r is idt && strings::compare(this: str, r: idt: str) == 0;
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
