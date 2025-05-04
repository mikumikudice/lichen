use io;
use os;
use fs;
use fmt;
use memio;
use strings;
use os::exec;
use unix::signal;

let silent = true;
let just_check = false;
const version = "0.4.0";

const temp = ".tmp/";

export fn main() void = {
    const abt = "%gmmc is the compiler for the moss programming language.";
    const usg = fmt::asprintf(
        "%gmmc usage:\n\n %y$ {} "
        "%b[flags] <main file> [output file name]",
        os::args[0])!;
    defer free(usg);

    const flg =
        "\n%gflags usage:%d\n"
        "\n %g-h\t\t"
        "%y-- prints this help message"
        "\n %g-v\t\t"
        "%y-- prints the current version of the compiler"

        "\n %g-l\t%b<path>\t"
        "%y-- includes an object file or library in the linking list"

        "\n %g-stb\t%b<path>\t"
        "%y-- sets path for stdlib and runtime"

        "\n %g-c\t\t"
        "%y-- only checks for compile errors and generates no output files"

        "\n %g-vb\t\t"
        "%y-- prompts each substep. if %g-c%y is also set, dumps qbe IR"
        
        "\n %g-t\t\t"
        "%y-- keeps temporary files at %g.tmp/%y folder";

    const hlp =
        "\n%gget help on learning how to use moss in "
        "%bhttps://git.sr.ht/~mikaela-md/mossy/tree/main/doc/tut.md";

    const home = os::getenv("HOME"): str;

    const also_link = []: []str;
    defer free(also_link);

    // check if there are arguments
    const argc = len(os::args);
    if(argc == 1){
        // no arguments given
        color("{}\n{}\n{}\n{}", abt, usg, flg, hlp);
        return;
    } else if(argc == 2){
        // versioning
        if(os::args[1] == "-v" || os::args[1] == "--version"){
            color("%gmika's moss compiler %yv{}", version);
            return;
        // help
        } else if(os::args[1] == "-h" || os::args[1] == "--help"){
            color(usg);
            color(flg);
            return;
        };
    };
    let libset = false;
    let outset = false;
    let infset = false;
    let keeptemps = false;

    let outfile = "";
    let srcname = "";
    let libpath = strings::concat(os::getenv("HOME"): str,
        "/.local/lib/mmclib/")!;
    defer free(libpath);

    // parse command line arguments
    for(let a = 1z; a < argc; a += 1){
        const arg = os::args[a];
        if(strings::hasprefix(arg, "-")){
            switch(arg){
            // std libpath flag
            case "-std" =>
                a += 1;
                if(a < argc){
                    libset = true;
                    free(libpath);
                    libpath = strings::dup(os::args[a])!;
                    continue;
                } else {
                    color("%rmissing lib path for -std flag");
                    color_error(flg);
                };
            case "-l" =>
                a += 1;
                if(a < argc){
                    append(also_link, strings::dup(os::args[a])!)!;
                    continue;
                } else {
                    color("%rmissing object file for -l flag");
                    color_error(flg);
                };
            // verbose mode
            case "-vb" =>
                silent = false;
                continue;
            case "-c" =>
                just_check = true;
                continue;
            case "-t" =>
                keeptemps = true;
                continue;
            case =>
                color("%runknown flag %g{}", arg);
                color_error(flg);
            };
        };
        // input file
        if(!infset){
            infset = true;
            srcname = arg;
        // output file
        } else {
            // define only once
            if(!outset){
                outset = true;
                outfile = arg;
            } else {
                color("%rmultiple output files given");
                color_error(usg);
            };
        };
    };
    if(!infset){
        color_error("%rno input file given");
    };
    if(!outset){
        outfile = strings::rcut(srcname, ".ms").0;
    };
    libpath =
        if(strings::hassuffix(libpath, "/")){
            yield libpath;
        } else {
            const new = strings::concat(libpath, "/")!;
            free(libpath);
            yield new;
        };
    if(!os::exists(libpath)){
        color_error("%rthe given path %y\"{}\"%r does not exists", libpath);
    };
    match(compile(srcname, libpath, alloc(memio::dynamic())!, true)){
    case let obj: comp_obj =>
        defer free(defs);
        defer free_module(obj);
        if(just_check){
            if(!silent) fmt::println(memio::string(obj.buffer)!)!;
            return;
        };
        run_cmd(silent, "mkdir", "-p", temp);

        const mold_args = []: []str;
        defer free(mold_args);
        defer for(let obj ..& mold_args) free(obj);

        append(mold_args, strings::dup("-o")!)!;
        append(mold_args, strings::dup(outfile)!)!;

        append(mold_args, also_link...)!;

        append(mold_args, gen_obj(outfile, memio::string(obj.buffer)!, temp))!;

        let skip = []: []str;
        defer free(skip);
        match(gen_mods(obj.ctxt, &mold_args, &skip)){
        case let err: COMPERR =>
            defer free(err.1);
            defer io::close(err.1)!;
            color(memio::string(err.1)!);
            os::exit(err.0);
        case void => void;
        };
        const rt_out = strings::concat(temp, "rt.o")!;
        const rt_src = strings::concat(libpath, "rt.asm")!;
        defer free(rt_src);

        run_cmd(silent, "nasm", "-felf64", "-o", rt_out, rt_src);
        append(mold_args, rt_out)!;

        run_cmd(silent, "mold", mold_args...);
        if(!keeptemps) run_cmd(silent, "rm", "-rf", temp);

    case let err: COMPERR =>
        defer free(err.1);
        defer io::close(err.1)!;
        color(memio::string(err.1)!);
        os::exit(err.0);
    };
};

fn gen_mods(ctxt: *context, args: *[]str, skip: *[]str) (void | COMPERR) = {
    for(let mod ..& ctxt.modules){
        for(let fun_def ..& mod.1.ctxt.fun_defs){
            const meta = fun_def.meta as *fn_meta;
            const name = strings::replace(meta.name.id, "'", ".q")!;
            defer free(name);
            meta.mod = fmt::asprintf("{}.{}", (mod.0.val as ident).id, name)!;
        };
        if(finds(*skip, mod.1.ctxt.name) is void){
            append(skip, mod.1.ctxt.name)!;
            const outfile = strings::rcut(mod.1.ctxt.name, ".ms").0;

            gen_file(mod.1.ctxt, mod.1.tokens, mod.1.buffer, mod.1.ast_head)?;
            append(args, gen_obj(outfile, memio::string(mod.1.buffer)!, temp))!;

            gen_mods(mod.1.ctxt, args, skip)?;
        };
    };
};

// receives a output file name and generates the corresponding
// object file. the returned string is the object file name
fn gen_obj(dest: str, code: str, temp: str) str = {
    const objf =
        if(strings::index(dest, "/") is size){
            const (_, r) = strings::rcut(dest, "/");
            yield r;
        } else {
            yield dest;
        };
    const qbe_out = fmt::asprintf("{}{}.ssa", temp, objf)!;
    defer free(qbe_out);
    const bin_src = fmt::asprintf("{}{}.asm", temp, objf)!;
    defer free(bin_src);
    const bin_out = fmt::asprintf("{}{}.o", temp, objf)!;

    const file =
        match(os::create(qbe_out, fs::mode::USER_RWX)){
        case let f: io::file => yield f;
        case let e: fs::error =>
            color_error("%Robject dispatch error:%r {}",
                fs::strerror(e));
        };
    io::write(file, strings::toutf8(code))!;
    io::close(file)!;

    run_cmd(silent, "qbe", "-o", bin_src, qbe_out);
    run_cmd(silent, "as" , "-o", bin_out, bin_src);
    return bin_out;
};

fn run_cmd(noprint: bool, cmd: str, args: str...) void = {
    if(!noprint){
        const argf = memio::dynamic();
        defer io::close(&argf)!;
        for(let a .. args){
            fmt::fprintf(&argf, " {}", a)!;
        };
        color("%gcmd:%d {}{}", cmd, memio::string(&argf)!);
    };
    const exe =
        match(exec::cmd(cmd, args...)){
        case let c: exec::command =>
            yield c;
        case let e: exec::error =>
            if(e is exec::nocmd){
                if(cmd == "mold"){
                    color("%ymold not found. using ld");
                    run_cmd(noprint, "ld", args...);
                } else {
                    color_error("%Rmissing dependency:%b {}", cmd);
                };
            };
            color_error("%r{} failed", cmd);
        };
    match(exec::fork()!){
    case void =>
        exec::exec(&exe);
    case let proc: exec::process =>
        const stat = exec::wait(&proc)!;
        free(exe.argv);
        free(exe.files);
        strings::freeall(exe.env);
        if(stat.status != 0) color_error("%r{} failed", cmd);
    };
};

fn color(fmt: str, args: fmt::field...) void = {
    let buffer = memio::dynamic();
    defer io::close(&buffer)!;

    let path =
        if(len(args) > 0){
            yield strings::toutf8(fmt::asprintf(fmt, args...)!);
        } else {
            yield strings::toutf8(fmt::asprint(fmt)!);
        };
    defer free(path);
    for(let c = 0z; c < len(path); c += 1){
        const chr = path[c];
        if(chr == '%'){
            switch(path[c + 1]){
            case 'd' =>
                fmt::fprintf(&buffer, "\x1b[0m")!;
            case 'l' =>
                fmt::fprintf(&buffer, "\x1b[0;30m")!;
            case 'r' =>
                fmt::fprintf(&buffer, "\x1b[0;31m")!;
            case 'g' =>
                fmt::fprintf(&buffer, "\x1b[0;32m")!;
            case 'y' =>
                fmt::fprintf(&buffer, "\x1b[0;33m")!;
            case 'b' =>
                fmt::fprintf(&buffer, "\x1b[0;34m")!;
            case 'p' =>
                fmt::fprintf(&buffer, "\x1b[0;35m")!;
            case 'c' =>
                fmt::fprintf(&buffer, "\x1b[0;36m")!;
            case 'w' =>
                fmt::fprintf(&buffer, "\x1b[0;37m")!;
            case 'K' =>
                fmt::fprintf(&buffer, "\x1b[0;40m")!;
            case 'R' =>
                fmt::fprintf(&buffer, "\x1b[0;41m")!;
            case 'G' =>
                fmt::fprintf(&buffer, "\x1b[0;42m")!;
            case 'Y' =>
                fmt::fprintf(&buffer, "\x1b[0;43m")!;
            case 'B' =>
                fmt::fprintf(&buffer, "\x1b[0;44m")!;
            case 'P' =>
                fmt::fprintf(&buffer, "\x1b[0;45m")!;
            case 'C' =>
                fmt::fprintf(&buffer, "\x1b[0;46m")!;
            case 'W' =>
                fmt::fprintf(&buffer, "\x1b[0;47m")!;
            case =>
                fmt::fprint(&buffer, chr: rune)!;
                c -= 1;
            };
            c += 1;
        } else {
            fmt::fprint(&buffer, chr: rune)!;
        };
    };
    fmt::fprint(&buffer, "\x1b[0m")!;
    fmt::println(memio::string(&buffer)!)!;
};

fn color_error(fmt: str, args: fmt::field...) never = {
    color(fmt, args...);
    os::exit(1);
};

fn error(file: (*context | void), fmt: str,
    args: fmt::field...) COMPERR = {
    let buffer = alloc(memio::dynamic())!;
    match(file){
    case void =>
        fmt::fprintfln(buffer, fmt, args...)!;
    case let f: *context =>
        const pos = gen_pos(f);
        defer free(pos);
        fmt::fprintf(buffer, "%R{}:%r ", pos)!;
        fmt::fprintfln(buffer, fmt, args...)!;

        const max = len(f.src);
        const index = strings::index(u8tostr(f.src[f.lst..max]), "\n") as size + f.lst;
        assert(index > f.lst);

        const line = fmt::asprint(f.lin + 1)!;
        defer free(line);

        fmt::fprintfln(buffer, "\n%b{} %d{}", line,
            u8tostr(f.src[f.lst..index]))!;
        for(let c = 0z; c < len(line) + 1; c += 1){
            fmt::fprint(buffer, " ")!;
        };
        const arrow = strings::lpad("^", '~', f.cln + 1)!;
        defer free(arrow);
        fmt::fprintfln(buffer, "%r{}", arrow)!;
    };
    return (1, buffer);
};
