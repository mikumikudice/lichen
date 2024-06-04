use os;
use os::exec;
use unix::signal;

use io;
use fs;
use fmt;
use strings;

const fix_entry = "export function $_start(){\n@start\n    call $main()\n    hlt\n}\n";

let also_link = []: []str;
let cmpd_mods = []: []str;

fn build(src: str, dest: str, ctxt: *context) (void | CMP_ERR) = {
    const path =
        if(strings::hassuffix(ctxt.libpath, "/")){
            yield ctxt.libpath;
        } else {
            yield strings::concat(ctxt.libpath, "/");
        };
    if(findl(cmpd_mods, src) is size && ctxt.nomain){
        return;
    } else {
        append(cmpd_mods, src);
    };
    const qbe_ir =
        match(parse(src, ctxt)){
        case let e: CMP_ERR =>
            if(!ctxt.nomain) cmperr(e);
            return e;
        case let s: (str, kwd) => yield s.0;
        };
    const code =
        if(!ctxt.nomain){
            yield fmt::asprintf("# moss {}\n{}{}", version, fix_entry, qbe_ir);
        } else {
            yield fmt::asprintf("# moss {}\n{}", version, qbe_ir);
        };
    const temp = ".tmp";
    runc(silent, "mkdir", "-p", temp);
    
    const (objf, _) = rem_path(dest);
    const rt_src = fmt::asprintf("{}rt.asm", path);
    const rt_out = fmt::asprintf("{}/rt.o", temp);

    const qbe_out = fmt::asprintf("{}/{}.ssa", temp, objf);
    const bin_src = fmt::asprintf("{}/{}.asm", temp, objf);
    const bin_out = fmt::asprintf("{}/{}.o", temp, objf);

    const file = match(os::create(qbe_out, fs::mode::USER_RWX)){
        case let f: io::file => yield f;
        case let e: fs::error => cmperr(qbe_out: CRTFAIL);
    };

    io::write(file, strings::toutf8(code))!;
    io::close(file)!;

    runc(silent, "qbe", "-o", bin_src, qbe_out);
    runc(silent, "as" , "-o", bin_out, bin_src);
    if(ctxt.nomain){
        append(also_link, bin_out);
        const (name, _) = rem_path(src);
        fmt::printfln(fmtc("successfully compiled {}", cmd::GRN), name)!;
        return;
    };
    runc(silent, "nasm", "-felf64", "-o", rt_out, rt_src);

    let mold_args = []: []str;
    append(mold_args, ["-o", dest, bin_out, rt_out]...);
    append(mold_args, also_link...);
    runc(silent, "mold", mold_args...);

    if(!(stacktrace || !silent)) runc(silent, "rm", "-r", temp);

    const (name, _) = rem_path(src);
    fmt::printfln(fmtc("successfully compiled {} in {}", cmd::GRN), name, dest)!;
};

fn runc(noprint: bool, cmd: str, args: str...) void = {
    let argf = "";
    for(let a .. args){
        argf = fmt::asprintf("{} {}", argf, a);
    };
    if(!noprint)
        fmt::printfln("{}{}{}", fmtc("exec: ", cmd::BLU), cmd, argf)!;

    const exe = exec::cmd(cmd, args...)!;
    match(exec::fork()!){
    case void =>
        exec::exec(&exe);
    case let proc: exec::process =>
        let stat = exec::wait(&proc)!;
        match(exec::check(&stat)){
            case void => void;
            case => os::exit(1);
        };
    };
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
            fmtc(ptr.0, cmd::BOX_BLK));
        return (msg, ptr.1, void);

    case let uni: INVALID =>
        const err = uni as unimsg;
        const msg = fmt::asprintf(
            "found invalid {}", fmtc(err.msg, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let bim: EXPECTD =>
        const err = bim as bi_msg;
        const msg = fmt::asprintf(
            "expected {}, found {}",
            fmtc(err.lft, cmd::YEL), fmtc(err.rgt, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: UNDEFNS =>
        const err = uni as unimsg;
        const idt = strings::replace(err.msg, ".p", "'");
        const msg = fmt::asprintf("the variable {} is undefined at this point",
            fmtc(idt, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: MISMTCH =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("mismatch between {}",
            fmtc(err.msg, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: CANT_DO =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("you're not allowed to {}",
            fmtc(err.msg, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: IDTCDUP =>
        const err = uni as bi_msg;
        const idt = strings::replace(err.lft, ".p", "'");
        const msg = fmt::asprintf("the identifier {} is already in use. it was previously defined at {}",
            fmtc(idt, cmd::YEL), fmtc(err.rgt, cmd::BLU));
        return (msg, err.ptr, err.tip);

    case let uni: MODCDUP =>
        const err = uni as bi_msg;
        const msg = fmt::asprintf("the module {} was already imported. it was previously required at {}",
            fmtc(err.lft, cmd::YEL), fmtc(err.rgt, cmd::BLU));
        return (msg, err.ptr, err.tip);

    case let uni: NOTPUBL =>
        const err = uni as bi_msg;
        const msg = fmt::asprintf("the field {} from the {} module is not public and hence not accessible",
            fmtc(err.lft, cmd::YEL), fmtc(err.rgt, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: NOTCALL =>
        const err = uni as unimsg;
        const idt = strings::replace(err.msg, ".p", "'");
        const msg = fmt::asprintf("the namespace {} is not callable", fmtc(idt, cmd::YEL));
        return (msg, err.ptr, err.tip);
    
    case let uni: NOFIELD =>
        const err = uni as bi_msg;
        const msg = fmt::asprintf("the type {} has no field named {}",
            fmtc(err.lft, cmd::YEL), fmtc(err.rgt, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: NOTINDX =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("the type {} is not indexable", fmtc(err.msg, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: EFX_ERR =>
        const err = uni as bi_msg;
        const lft = strings::replace(err.lft, ".p", "'");
        const rgt = strings::replace(err.rgt, ".p", "'");
        const msg = fmt::asprintf("the function {} produces unhandled effects by the function caller {}",
            fmtc(lft, cmd::YEL), fmtc(rgt, cmd::YEL));
        return (msg, err.ptr, err.tip);

    case let uni: GENERIC =>
        const err = uni as unimsg;
        return (err.msg, err.ptr, err.tip);

    case let uni: GENTODO =>
        const err = uni as unimsg;
        const msg = fmt::asprintf("TODO: {}", fmtc(err.msg, cmd::YEL));
        return (msg, err.ptr, void);
    };
};

fn cmperr(e: CMP_ERR) never = {
    const (out, ptr, tip) = errstr(e);
    if(ptr is void){
        fmt::errorfln(out)!;
    } else {
        const pos = ptr: *file;
        defer free(pos);
        if(pos.iseol){
            pos = pos.eolat: *file;
        };
        const txt = tostr(pos.src);
        const end =
            match(strings::index(strings::sub(txt, pos.lst + 1), "\n")){
            case let e: size => yield pos.lst + e + 1;
            case => yield len(txt);
            };
        const src = strings::sub(txt, pos.lst, end);
        const num = fmt::asprintf("{} ", pos.lin + 1);
        defer free(num);

        fmt::errorfln("{} {}", fmtc(fmt::asprintf("error at {}:{}:{}:",
            pos.name, pos.lin + 1, pos.cln + 1), cmd::BOX_RED), out)!;

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
            fmtc(line, cmd::BLU),
            fmtc(arw, cmd::RED)
        )!;
        if(!(tip is void)){
            fmt::errorfln("{} {}", fmtc("compiler tip:",
            cmd::GRN), tip: str)!;
        };
    };
    os::exit(1);
};
