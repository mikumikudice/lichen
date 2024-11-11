use os;
use io;
use fs;
use fmt;
use memio;
use errors;
use strings;
use os::exec;
use unix::signal;

let also_link = []: []str;
let cmpd_mods = []: []str;

fn build(src: str, dest: str, ctxt: *context) (void | COMP_ERR) = {
    if(finds(cmpd_mods, src) is size && ctxt.nomain){
        return;
    } else {
        append(cmpd_mods, src);
    };
    const qbe_ir =
        match(parse(src, ctxt)){
        case let e: COMP_ERR =>
            if(ctxt.nomain){
                if(e is FILE_ERR && ctxt.libpath != ctxt.srcpath){
                    let newsrc = strings::replace(src, ctxt.libpath, ctxt.srcpath);
                    return build(newsrc, dest, ctxt);
                };
                return e;
            } else {
                cmperr(e);
            };
        case let s: memio::stream => yield s;
        };
    defer io::close(&qbe_ir)!;

    const datasec = memio::string(&ctxt.datasec)!;
    defer io::close(&ctxt.datasec)!;

    const code = fmt::asprintf("# moss {}\n{}{}",
        version, datasec, memio::string(&qbe_ir)!);

    const temp = ".tmp/";
    if(len(also_link) == 0) runc(silent, "mkdir", "-p", temp);

    const (objf, _) = rem_path(dest);
    const qbe_out = fmt::asprintf("{}{}.ssa", temp, objf);
    const bin_src = fmt::asprintf("{}{}.asm", temp, objf);
    const bin_out = fmt::asprintf("{}{}.o", temp, objf);

    const file = match(os::create(qbe_out, fs::mode::USER_RWX)){
        case let f: io::file => yield f;
        case let e: fs::error => cmperr(qbe_out: FILE_ERR);
    };

    io::write(file, strings::toutf8(code))!;
    io::close(file)!;

    runc(silent, "qbe", "-o", bin_src, qbe_out);
    runc(silent, "as" , "-o", bin_out, bin_src);
    if(ctxt.nomain){
        append(also_link, bin_out);
        const (name, _) = rem_path(src);
        if(!silent){
            fmt::printfln(fmtc("successfully compiled {}", cmd::GRN), name)!;
        };
        return;
    };

    const rt_src = fmt::asprintf("{}rt.asm", ctxt.libpath);
    const rt_out = fmt::asprintf("{}rt.o", temp);
    runc(silent, "nasm", "-felf64", "-o", rt_out, rt_src);

    if(!os::exists(dest)){
        match(os::mkfile(dest, fs::mode::USER_RWX)){
        case let e: fs::error =>
            fmt::fatalf(fmtc("invalid output file {}:{} {}", cmd::BOX_RED),
                dest, CMD[cmd::DEF], lower(fs::strerror(e)));
        case => void;
        };
    };
    let mold_args = []: []str;
    append(mold_args, ["-o", dest, bin_out, rt_out]...);
    append(mold_args, also_link...);
    runc(silent, "mold", mold_args...);

    if(silent) runc(silent, "rm", "-r", temp);

    const (name, _) = rem_path(src);
    if(!silent){
        fmt::printfln(fmtc("successfully compiled {} into {}", cmd::GRN),
            name, dest)!;
    };
};

fn runc(noprint: bool, cmd: str, args: str...) void = {
    let argf = "";
    for(let a .. args){
        argf = fmt::asprintf("{} {}", argf, a);
    };
    if(!noprint)
        fmt::printfln("{}{}{}", fmtc("exec: ", cmd::BLU), cmd, argf)!;

    const exe =
        match(exec::cmd(cmd, args...)){
        case let c: exec::command =>
            yield c;
        case let e: exec::error =>
            if(e is exec::nocmd){
                if(cmd == "mold"){
                    fmt::println("mold not found. using ld")!;
                    runc(noprint, "ld", args...);
                } else {
                    fmt::fatalf("missing dependency: {}", cmd);
                };
            };
            fmt::fatalf("{} failed", cmd);
        };
    match(exec::fork()!){
    case void =>
        exec::exec(&exe);
    case let proc: exec::process =>
        let stat = exec::wait(&proc)!;
        match(exec::check(&stat)){
            case void => void;
            case => fmt::fatalf("{} failed", cmd);
        };
    };
};

fn errmsg(f: *file, msg: str, tip: (str | void) = void) COMP_ERR = {
    const buff = memio::dynamic();
    assert(len(f.src) > 0);
    if(f.cln == 0 && iswsp(f.src[f.lst])){
        puttk(f);
    };
    const lin = gen_lin(f);
    const pos = gen_pos(f);

    fmt::fprintfln(&buff, fmtc("{}: {}\n", cmd::BOX_RED), pos, msg)!;
    fmt::fprint(&buff, CMD[cmd::BLU])!;
    const pad = fmt::fprintf(&buff, " {} ", f.lin + 1)!;
    fmt::fprintfln(&buff, "{}\n {}", lin, fmtc(strings::lpad("^", '~', pad + f.cln), cmd::RED))!;

    if(tip is str){
        fmt::fprintfln(&buff, "\n{}", tip as str)!;
    };
    return buff: SNTX_ERR;
};

fn cmperr(e: COMP_ERR) never = {
    match(e){
    case let msg: FILE_ERR =>
        fmt::fatal(msg);
    case let msg: SNTX_ERR =>
        fmt::fatal(memio::string(&msg)!);
    };
};
