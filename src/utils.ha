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

fn findl(strl: []str, itm: []u8) (size | void) = {
    const max = len(strl);
    const lit = tostr(itm);
    for(let i = 0z; i < max; i += 1){
        if(strl[i] == lit) return i;
    };
};

fn finds(strs: []str, itm: str) (size | void) = {
    const max = len(strs);
    for(let i = 0z; i < max; i += 1){
        if(strs[i] == itm) return i;
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

fn rem_path(f: str) (str, str) = {
    let name =
        if(strings::hasprefix(f, "/")){
            yield strings::sub(f, 1);
        } else {
            yield f;
        };
    let path = "";
    let i = strings::index(name, "/");
    for(i is size){
        path = strings::sub(name, 0, i + 1);
        name = strings::sub(name, i + 1);
        i = strings::index(name, "/");
    };
    return (name, path);
};
