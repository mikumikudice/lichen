use os;
use os::exec;
use unix::signal;

use io;
use fs;
use fmt;
use strings;
use strlib;

const fix_entry = "export function $_start(){\n@start\n    call $main()\n    hlt\n}\n";

fn build(src: str, dest: str, silent: bool = false) void = {
    let global = scope {
        over = void,
        defs = [],
        funs = [],
    };
    const qbe_ir = match(parse(src, &global)){
        case let e: CMP_ERR => cmperr(e);
        case let s: (str, kwd) => yield s.0;
    };
    const code = fmt::asprintf("# moss {}\n{}{}", version, fix_entry, qbe_ir);
    const root = "./bin";
    const temp = "./bin/tmp";
    const (objf, _) = rem_path(dest);
    
    const rt_src = fmt::asprintf("{}/../src/lib/rt.asm", root);
    const rt_out = fmt::asprintf("{}/rt.o", temp);

    const qbe_out = fmt::asprintf("{}/{}.ssa", temp, objf);
    const bin_src = fmt::asprintf("{}/{}.asm", temp, objf);
    const bin_out = fmt::asprintf("{}/{}.o", temp, objf);

    runc(silent, "mkdir", "-p", "bin");
    runc(silent, "mkdir", "-p", "bin/tmp");

    const file = match(os::create(qbe_out, fs::mode::USER_RWX)){
        case let f: io::file => yield f;
        case let e: fs::error => cmperr(qbe_out: CRTFAIL);
    };

    io::write(file, strings::toutf8(code))!;
    io::close(file)!;

    runc(silent, "qbe", "-o", bin_src, qbe_out);
    runc(silent, "as" , "-o", bin_out, bin_src);

    runc(silent, "nasm", "-felf64", "-o", rt_out, rt_src);
    runc(silent, "mold", "-o", dest, bin_out, rt_out);

    //runc("rm", qbe_out, bin_src, bin_out);
    fmt::printfln(col("successfully compiled {} in {}", cmd::GRN), src, dest)!;
};

fn runc(silent: bool, cmd: str, args: str...) void = {
    let argf = "";
    for(let a .. args){
        argf = fmt::asprintf("{} {}", argf, a);
    };
    if(!silent)
        fmt::printfln("{}{}{}", col("exec: ", cmd::BLU), cmd, argf)!;

    const exe = exec::cmd(cmd, args...)!;
    match(exec::fork()!){
    case void =>
        exec::exec(&exe);
    case let proc: exec::process =>
        peek(silent, fmt::asprintf("{}{}", cmd, argf), &proc);
    };
};

fn peek(silent: bool, cmd: str, proc: * exec::process) void = {
    let stat = exec::wait(proc)!;
    match(exec::check(&stat)){
        case void => void;
        case =>
            if(silent){
                assert(false, cmd);
            } else {
                os::exit(1);
            };
    };
};

fn rem_path(f: str) (str, str) = {
    let name = f;
    let path = "";
    let i = strlib::find(f, "/"); 
    for(!(i is strlib::match_err); i = strlib::finda(f, "/", i: size + 1)){
        name = strings::sub(f, i: size + 1, strings::end);
        path = strings::sub(f, 0, i: size);
    };

    return (name, path);
};

fn errstr(e: CMP_ERR) (str, (*file | void), (str | void)) = {
    match(e){
    case let name: LDDFAIL =>
        const msg = fmt::asprintf("error while loading file \"{}\"", name: str);
        return (msg, void, void);

    case let name: CRTFAIL =>
    const msg = fmt::asprintf("error while creating file \"{}\"", name: str);
        return (msg, void, void);

    case let ptr: UNREACH =>
        const msg = fmt::asprintf("compiler stuck in a unreachable path: {}",
            col(ptr.0, cmd::BOX_BLK));
        return (msg, ptr.1, void);

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
        const err = uni as bi_msg;
        const msg = fmt::asprintf("the identifier {} is already in use. it was previously defined at {}",
            col(err.lft, cmd::BLU), col(err.rgt, cmd::BLU));
        return (msg, err.ptr, err.tip);

    case let uni: NOTCALL =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("the namespace \"{}\" is not callable", err.msg);
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
        fmt::errorfln(out)!;
    } else {
        const pos = ptr: *file;
        if(pos.iseol){
            pos = pos.eolat: *file;
        };
        const txt = tostr(pos.src);
        const end =
            match(strlib::finda(txt, "\n", pos.lst)){
            case let e: size => yield e;
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
        free(pos);
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
