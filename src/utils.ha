use fmt;
use strings;

// message coloring
const CMD: []str =
    [ "\x1b[0m"
    , "\x1b[0;31m"
    , "\x1b[0;32m"
    , "\x1b[0;33m"
    , "\x1b[0;34m"
    , "\x1b[0;40m"
    , "\x1b[0;41m"
    ];
type cmd = enum int {
    DEF, RED, GRN, YEL, BLU,
    BOX_BLK , BOX_RED
};

fn fmtc(t: fmt::formattable, c: cmd) str = {
    if(c != cmd::DEF){
        return fmt::asprintf("{}{}{}", CMD[c], t, CMD[cmd::DEF]);
    } else {
        return fmt::asprintf("{}{}", CMD[cmd::DEF], t);
    };
};

fn findl(strl: []str, itm: str) (size | void) = {
    const max = len(strl);
    for(let i = 0z; i < max; i += 1){
        if(strl[i] == itm) return i;
    };
};

fn findref(refs: *[]idref, nm: *nmsp) (*idref | void) = {
    const max = len(refs);
    for(let r ..& refs){
        if(r.idt == nm.ident && cmp_origin(r.origin, nm.origin))
            return &r;
    };
};

fn lower(src: str) str = {
    let out = strings::toutf8(strings::dup(src));
    const max = len(out);
    for(let c = 0z; c < max; c += 1){
        if(out[c] >= 'A' && out[c] <= 'z')
            out[c] = out[c] | 0b0100000;
    };
    return strings::fromutf8(out)!;
};

fn upper(src: str) str = {
    let out = strings::toutf8(strings::dup(src));
    const max = len(out);
    for(let c = 0z; c < max; c += 1){
        if(out[c] >= 'A' && out[c] <= 'z')
            out[c] = out[c] ^ 0b0100000;
    };
    return strings::fromutf8(out)!;
};
