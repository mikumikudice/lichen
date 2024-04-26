use os;
use fmt;
use strlib;
use strings;

fn errstr(e: CMP_ERR) (str, (*file | void), (str | void)) = {
    match(e){
    case LDDFAIL =>
        return ("error during source code loading", void, void);

    case CRTFAIL =>
        return ("error during output file creation", void, void);

    case let ptr: UNREACH =>
        const msg = fmt::asprintf("{}", col("compiler stuck in a unreachable path",
            cmd::BOX_BLK));
        return (msg, ptr: *file, void);

    case let uni: INVALID =>
        const err = uni as unimsg;
        const msg = fmt::asprintf(
            "found invalid {}", col(err.msg, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let bim: EXPECTD =>
        const err = bim as bi_msg;
        const msg = fmt::asprintf(
            "expected {}, found {}",
            col(err.lft, cmd::YEL), col(err.rgt, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: UNDEFNS =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("the variable \"{}\" is undefined at this point",
            col(err.msg, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: MISMTCH =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("mismatch between {}",
            col(err.msg, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: CANT_DO =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("you're not allowed to {}",
            col(err.msg, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: IDTCDUP =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("the identifier {} is already in use",
            col(err.msg, cmd::BLU));
        return (msg, err.ptr, err.tip);

    case let uni: GENERIC =>
        const err = uni as unimsg;
        return (err.msg, err.ptr, err.tip);

    case let uni: GENTODO =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("TODO: {}", col(err.msg, cmd::YEL));
        return (msg, err.ptr, void);
    };
};

fn cmperr(e: CMP_ERR) never = {
    const (out, ptr, tip) = errstr(e);
    if(ptr is void){
        fmt::errorln(out)!;
    } else {
        const pos = ptr: *file;
        const txt = tostr(pos.src);
        const end =
            match(strlib::finda(txt, "\n", pos.lst)){
            case let i: size => yield i;
            case => yield len(txt);
            };
        const src = strings::sub(txt, pos.lst, end);
        const num = fmt::asprintf("{} ", pos.lin + 1);

        fmt::errorfln("{} {}", col(fmt::asprintf("error at {}:{}:{}:",
            os::args[1], pos.lin + 1, pos.cln + 1), cmd::BOX_RED), out)!;

        const line = strings::concat(num, src);
        const ofst = len(line) - len(src);

        let arw = "";
        for(let cnt = 0: size; cnt < pos.cln + ofst; cnt += 1){
            if(cnt < len(num) - 1){
                arw = strings::concat(arw, " ");
            } else {
                arw = strings::concat(arw, "~");
            };
        };
        arw = fmt::asprintf("{}^\n", arw);
        fmt::errorfln(
            "\n{}\n{}",
            col(line, cmd::BLU),
            col(arw, cmd::RED)
        )!;
        if(!(tip is void)){
            fmt::errorfln("{} {}", col("compiler tip:",
            cmd::GRN), tip: str)!;
        };
    };
    os::exit(1);
};

fn tktostr(tk: (tok | eof), verb: bool = false) str = {
    if(tk is eof) return "end of source file";
    match(tk: tok){
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

export fn main() void = {
    const abt = "mossy is the compiler for the moss programming language.";
    const tut = "not-implemented-yet";

    const usg = fmt::asprintf(
        "mossy usage:\n{}{}{}",
        col("$ ", cmd::YEL),
        col(os::args[0], cmd::GRN),
        col(" <main file> [output file name]", cmd::BLU),
    );
    const hlp = fmt::asprintf(
        "get help on learning how to use moss in {}",
        col(tut, cmd::GRN)
    );
    // check if there are arguments
    if(len(os::args) == 1){
        fmt::printfln("{}\n{}\n\n{}", abt, usg, hlp)!;
        return;
    };
    let name = os::args[1];
    let outf = strlib::replace(name, ".ms", "");

    let raw = match(parse(name)){
        case let err: CMP_ERR => cmperr(err);
        case let src: (str, nmsp_t) => yield src.0;
    };
    fmt::println(raw)!;
};
