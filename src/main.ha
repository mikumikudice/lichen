use fmt;
use  io;
use  os;
use  fs;

use     math;
use     time;
use  strings;

fn errstr(e: CMP_ERR) (str, (*src_file | void), (str | void)) = {
    match(e){
    case LDDFAIL =>
        return ("error during source code loading", void, void);
    case let uni: INVALID =>
        const err = uni as unimsg;
        const msg = fmt::asprintf(
            "found invalid {}", col(err.msg, cmd::YEL)
        );
        return (msg, err.ptr, err.tip);
    case let bim: EXPECTD =>
        const err = bim as bi_msg;
        const msg = fmt::asprintf(
            "expected {}, found {}",
            col(err.lft, cmd::YEL), col(err.rgt, cmd::YEL)
        );
        return (msg, err.ptr, err.tip);
    case let bim: UNDEFNS =>
        const err = bim as bi_msg;
        const msg = fmt::asprintf(
            "the variable \"{}\" is undefined in the \"{}\" scope at this point",
            col(err.lft, cmd::YEL), col(err.rgt, cmd::YEL)
        );
        return (msg, err.ptr, err.tip);
    case let uni: MISMTCH =>
        const err = uni as unimsg;
        const msg = fmt::asprintf(
            "mismatch between {}", col(err.msg, cmd::YEL)
        );
        return (msg, err.ptr, err.tip);
    case let uni: CANT_DO =>
        const err = uni as unimsg;
        const msg = fmt::asprintf(
            "you're not allowed to {}", col(err.msg, cmd::YEL)
        );
        return (msg, err.ptr, err.tip);
    case let uni: GENERIC =>
        const err = uni as unimsg;
        return (err.msg, err.ptr, err.tip);
    case let uni: GENTODO =>
        const err = uni as unimsg;
        const msg = fmt::asprintf(
            "TODO: {}", col(err.msg, cmd::YEL)
        );
        return (msg, err.ptr, void);
    };
};
fn cmperr(e: CMP_ERR) never = {
    const (out, ptr, tip) = errstr(e);
    if(ptr is void){
        fmt::errorln(out)!;
    } else {
        const pos = ptr: *src_file;
        fmt::errorfln(
            "{} {}",
            col(fmt::asprintf(
                "error at {}:{}:{}:",
                os::args[1], pos.lin + 1, pos.cln + 1
            ), cmd::BOX_RED), out
        )!;
        const txt = toutf(pos.src, pos)!;
        const src = strings::sub(txt, pos.lst, finda(txt, "\n", pos.lst)!);
        const num = fmt::asprintf("{} ", pos.lin + 1);
        let arw = "";
        const line = strings::concat(num, src);
        const ofst = len(line) - len(src);

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
            fmt::errorfln(
                "{} {}",
                col("compiler tip:", cmd::GRN),
                tip: str
            )!;
        };
    };
    os::exit(1);
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
    let outf = replace(name, ".ms", "");

    let bast = match(parse(name)){
        case let err: CMP_ERR => cmperr(err);
        case let src: str => yield src;
    };
};