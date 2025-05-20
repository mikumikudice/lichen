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
const version = "0.5.1";

const temp = ".tmp/";

let sharedlib = false;
let staticlib = false;
export fn main() void = {
    const abt = "%glcc is the compiler for the lichen programming language.";
    const usg = fmt::asprintf(
        "%glcc usage:\n\n %y$ {} "
        "%b[flags] <main file> [output file name]",
        os::args[0])!;
    defer free(usg);

    const flg =
        "\n%gflags usage:%d\n"
        "\n %g-h\t\t"
        "%y-- prints this help message"
        "\n %g-v\t\t"
        "%y-- prints the current version of the compiler"

        "\n %g-L %b<path>\t"
        "%y-- includes an object file or library in the linking list"

        "\n %g-l%blibname\t"
        "%y-- searches for %glib%blibname%g.so%y or %glib%blibname%g.a%y and links against it"

        "\n %g-stb %b<path>\t"
        "%y-- sets path for stdlib and runtime"

        "\n %g-c\t\t"
        "%y-- only checks for compile errors and generates no output files"

        "\n %g-vb\t\t"
        "%y-- prompts each substep. if %g-c%y is also set, dumps qbe IR instead"

        "\n %g-static\t"
        "%y-- produces a static library"

        "\n %g-shared\t"
        "%y-- produces a shared library"
        
        "\n %g-t\t\t"
        "%y-- keeps temporary files at %g.tmp/%y folder";

    const hlp =
        "\n%gget help on learning how to use lichen in "
        "%bhttps://git.sr.ht/~mikaela-md/lcc/tree/main/doc/tut.md";

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
            color("%glichen compiler %yv{}", version);
            return;
        // help
        } else if(os::args[1] == "-h" || os::args[1] == "--help"){
            color(usg);
            color(flg);
            return;
        };
    };
    let shared = false;
    let libset = false;
    let outset = false;
    let infset = false;
    let keeptemps = false;

    let outfile = "";
    let srcname = "";
    let libpath = strings::concat(os::getenv("HOME"): str,
        "/.local/lib/lcclib/")!;
    defer free(libpath);

    // parse command line arguments
    for(let a = 1z; a < argc; a += 1){
        const arg = os::args[a];
        if(strings::hasprefix(arg, "-")){
            if(strings::hasprefix(arg, "-l")){
                shared = true;
                append(also_link, strings::dup(arg)!)!;
            };
            switch(arg){
            // std libpath flag
            case "-std" =>
                a += 1;
                if(a < argc){
                    libset = true;
                    //free(libpath);
                    libpath = strings::dup(os::args[a])!;
                    continue;
                } else {
                    color("%rmissing lib path for -std flag");
                    color_error(flg);
                };
            case "-L" =>
                a += 1;
                if(a < argc){
                    append(also_link, strings::dup(os::args[a])!)!;
                    continue;
                } else {
                    color("%rmissing object file for -L flag");
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
            case "-shared" =>
                if(!staticlib){
                    sharedlib = true;
                } else {
                    color("%rshared library flag set over static library flag");
                    color_error(flg);
                };
                continue;
            case "-static" =>
                if(!sharedlib){
                    staticlib = true;
                } else {
                    color("%rstatic library flag set over shared library flag");
                    color_error(flg);
                };
                continue;
            case =>
                if(!strings::hasprefix(arg, "-l")){
                    color("%runknown flag %g{}", arg);
                    color_error(flg);
                };
            };
        };
        if(!strings::hasprefix(arg, "-")){
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
    };
    if(!infset){
        color_error("%rno input file given");
    };
    if(!outset){
        const extension =
            if(strings::hassuffix(srcname, ".lic")){
                yield ".lic";
            } else {
                yield ".lim";
            };
        outfile = strings::rcut(srcname, extension).0;
    };

    libpath =
        if(strings::hassuffix(libpath, "/")){
            yield libpath;
        } else {
            const new = strings::concat(libpath, "/")!;
            //free(libpath);
            yield new;
        };
    if(!os::exists(libpath)){
        color_error("%rthe given path %y\"{}\"%r does not exists", libpath);
    };

    match(compile(srcname, libpath, alloc(memio::dynamic())!,
        !(sharedlib || staticlib))){
    case let obj: comp_obj =>
        defer free_module(obj);
        const link_args = []: []str;
        defer free(link_args);
        defer for(let obj ..& link_args) free(obj);

        for(let l .. ["-z", "noexecstack"]){
            append(link_args, strings::dup(l)!)!;
        };
        if(sharedlib){
            append(link_args, strings::dup("-r")!)!;
            append(link_args, strings::dup("-shared")!)!;
            append(link_args, strings::dup("-fPIC")!)!;
            append(link_args, strings::dup("--export-dynamic")!)!;
            append(link_args, strings::dup("--whole-archive")!)!;
            append(link_args, strings::dup("-o")!)!;
            append(link_args, fmt::asprintf("{}.o", outfile)!)!;
        } else if(staticlib){
            append(link_args, strings::dup("-r")!)!;
            append(link_args, strings::dup("--whole-archive")!)!;
            append(link_args, strings::dup("-o")!)!;
            append(link_args, fmt::asprintf("{}.o", outfile)!)!;
        } else {
            if(shared){
                append(link_args, strings::dup("--dynamic-linker=/lib64/ld-linux-x86-64.so.2")!)!;
            };
            append(link_args, strings::dup("-e")!)!;
            append(link_args, strings::dup("main")!)!;
            append(link_args, strings::dup("-o")!)!;
            append(link_args, strings::dup(outfile)!)!;
        };
        append(link_args, also_link...)!;

        if(!just_check) run_cmd(silent, "mkdir", "-p", temp);
        append(link_args, gen_obj(outfile, memio::string(obj.buffer)!, temp))!;

        let skip = []: []str;
        defer free(skip);
        match(gen_mods(obj.ctxt, &link_args, &skip)){
        case let err: COMPERR =>
            defer free(err.1);
            defer io::close(err.1)!;
            color(memio::string(err.1)!);
            os::exit(err.0);
        case void => void;
        };
        if(just_check){
            if(!silent) fmt::println(memio::string(obj.buffer)!)!;
            return;
        };
        const rt_out = strings::concat(temp, "rt.o")!;
        const rt_src = strings::concat(libpath, "rt.asm")!;
        defer free(rt_src);

        run_cmd(silent, "nasm", "-felf64", "-o", rt_out, rt_src);
        append(link_args, rt_out)!;

        run_cmd(silent, "ld", link_args...);
        if(staticlib || sharedlib){
            const out =
                if(staticlib){
                    yield fmt::asprintf("{}.a", outfile)!;
                } else {
                    yield fmt::asprintf("{}.so", outfile)!;
                };
            defer free(out);
            const obj = fmt::asprintf("{}.o", outfile)!;
            defer free(obj);
            run_cmd(silent, "ar", "-rcs", out, obj);
            run_cmd(silent, "rm", obj);
        };
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
            const outfile =
                if(!strings::hassuffix(mod.1.ctxt.name, ".lim")){
                    color("%Ywarning:%y modules should use \".lim\" as its extension");
                    yield strings::rcut(mod.1.ctxt.name, ".lic").0;
                } else {
                    yield strings::rcut(mod.1.ctxt.name, ".lim").0;
                };
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

    if(!just_check){
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
    };
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
                color_error("%Rmissing dependency:%b {}", cmd);
            } else {
                color_error("%r{} failed", cmd);
            };
        };
    const proc = exec::start(&exe)!;
    const stat = exec::wait(&proc)!;
    if(stat.status != 0) color_error("%r{} failed", cmd);
};

fn add_color(path: []u8) *memio::stream = {
    const buffer = alloc(memio::dynamic())!;
    for(let c = 0z; c < len(path); c += 1){
        const chr = path[c];
        if(chr == '%'){
            switch(path[c + 1]){
            case 'd' =>
                fmt::fprintf(buffer, "\x1b[0m")!;
            case 'l' =>
                fmt::fprintf(buffer, "\x1b[0;30m")!;
            case 'r' =>
                fmt::fprintf(buffer, "\x1b[0;31m")!;
            case 'g' =>
                fmt::fprintf(buffer, "\x1b[0;32m")!;
            case 'y' =>
                fmt::fprintf(buffer, "\x1b[0;33m")!;
            case 'b' =>
                fmt::fprintf(buffer, "\x1b[0;34m")!;
            case 'p' =>
                fmt::fprintf(buffer, "\x1b[0;35m")!;
            case 'c' =>
                fmt::fprintf(buffer, "\x1b[0;36m")!;
            case 'w' =>
                fmt::fprintf(buffer, "\x1b[0;37m")!;
            case 'K' =>
                fmt::fprintf(buffer, "\x1b[0;40m")!;
            case 'R' =>
                fmt::fprintf(buffer, "\x1b[0;41m")!;
            case 'G' =>
                fmt::fprintf(buffer, "\x1b[0;42m")!;
            case 'Y' =>
                fmt::fprintf(buffer, "\x1b[0;43m")!;
            case 'B' =>
                fmt::fprintf(buffer, "\x1b[0;44m")!;
            case 'P' =>
                fmt::fprintf(buffer, "\x1b[0;45m")!;
            case 'C' =>
                fmt::fprintf(buffer, "\x1b[0;46m")!;
            case 'W' =>
                fmt::fprintf(buffer, "\x1b[0;47m")!;
            case =>
                fmt::fprint(buffer, chr: rune)!;
                c -= 1;
            };
            c += 1;
        } else {
            fmt::fprint(buffer, chr: rune)!;
        };
    };
    fmt::fprint(buffer, "\x1b[0m")!;
    return buffer;
};

fn color(fmt: str, args: fmt::field...) void = {
    const path =
        if(len(args) > 0){
            yield strings::toutf8(fmt::asprintf(fmt, args...)!);
        } else {
            yield strings::toutf8(fmt::asprint(fmt)!);
        };
    defer free(path);

    const buffer = add_color(path);
    defer free(buffer);
    defer io::close(buffer)!;

    fmt::println(memio::string(buffer)!)!;
};

fn color_error(fmt: str, args: fmt::field...) never = {
    color(fmt, args...);
    os::exit(1);
};

fn error_line(ctxt: *context, buffer: *memio::stream) void = {
    const max = len(ctxt.src);
    let index = strings::index(
        u8tostr(ctxt.src[ctxt.lst .. max]), "\n") as size + ctxt.lst;
    if(index <= ctxt.lst){
        const idx =
            if(ctxt.lst > 0){
                yield ctxt.lst - 1;
            } else {
                yield 0z;
            };
        index = strings::index(
            u8tostr(ctxt.src[idx .. max]), "\n") as size + ctxt.lst;
    };

    const line = fmt::asprint(ctxt.lin + 1)!;
    defer free(line);

    fmt::fprintfln(buffer, "\n%b{} %d{}", line,
        u8tostr(ctxt.src[ctxt.lst .. index]))!;

    for(let c = 0z; c < len(line) + 1; c += 1){
        fmt::fprint(buffer, " ")!;
    };
    const arrow = strings::lpad("^", '~', ctxt.cln + 1)!;
    defer free(arrow);
    fmt::fprintfln(buffer, "%r{}", arrow)!;
};

fn error(ctxt: (*context | void), fmt: str,
    args: fmt::field...) COMPERR = {
    let buffer = alloc(memio::dynamic())!;
    match(ctxt){
    case void =>
        fmt::fprintfln(buffer, fmt, args...)!;
    case let f: *context =>
        const pos = gen_pos(f);
        defer free(pos);
        fmt::fprintf(buffer, "%R{}:%r ", pos)!;
        fmt::fprintfln(buffer, fmt, args...)!;
        error_line(f, buffer);
    };
    return (1, buffer);
};
