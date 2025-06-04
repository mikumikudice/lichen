use io;
use os;
use fs;
use fmt;
use memio;
use bufio;
use strings;
use os::exec;
use unix::signal;

let silent = true;
let just_check = false;

const version = "0.11.0";
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

        "\n %g-static\t"
        "%y-- generates a static archive from module"

        "\n %g-shared\t"
        "%y-- generates a shared library from module"

        "\n %g-stb %b<path>\t"
        "%y-- sets path for stdlib and runtime"

        "\n %g-E\t\t"
        "%y-- only checks for compile errors and generates no output files"

        "\n %g-vb\t\t"
        "%y-- prompts each substep. if %g-c%y is also set, dumps qbe IR instead"
        
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
    let onlibc = false;
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
                if(arg == "-lc"){
                    onlibc = true;
                } else {
                    append(also_link, strings::dup(arg)!)!;
                };
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
            case "-static" =>
                if(sharedlib){
                    color("%rcannot set both static and shared flags");
                    color_error(flg);
                };
                staticlib = true;
            case "-shared" =>
                if(staticlib){
                    color("%rcannot set both static and shared flags");
                    color_error(flg);
                };
                sharedlib = true;
            // verbose mode
            case "-vb" =>
                silent = false;
                continue;
            // parse-only mode
            case "-E" =>
                just_check = true;
                continue;
            // keep temps mode
            case "-t" =>
                keeptemps = true;
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

    const module_checking = strings::hassuffix(srcname, ".lim") && just_check;

    const literals = []: []str;
    const typedefs = []: [](*aggregated | *ext_array);
    defer free(literals);
    match(compile(srcname, libpath, &literals, &typedefs,
        !(sharedlib || staticlib || module_checking))){
    case let obj: *context =>
        defer free_module(obj);
        const link_args = []: []str;
        defer free(link_args);
        defer for(let obj ..& link_args) free(obj);

        const objname =
            if(strings::index(outfile, "/") is size){
                const (_, r) = strings::rcut(outfile, "/");
                yield r;
            } else {
                yield outfile;
            };
        const qbe_out = fmt::asprintf("{}{}.ssa", temp, objname)!;
        defer free(qbe_out);
        const asm_src = fmt::asprintf("{}{}.asm", temp, objname)!;
        defer free(asm_src);
        const obj_out = fmt::asprintf("{}{}.o", temp, objname)!;
        append(link_args, obj_out)!;

        if(!onlibc){
            if(!staticlib && !sharedlib){
                for(let l .. ["-e", "main", "-o", outfile]){
                    append(link_args, strings::dup(l)!)!;
                };
            } else if(staticlib){
                for(let l .. ["-r", "-o"]){
                    append(link_args, strings::dup(l)!)!;
                };
                append(link_args, fmt::asprintf("{}.o", outfile)!)!;
            } else {
                for(let l .. ["-shared", "-fPIC", "--export-dynamic", "-o"]){
                    append(link_args, strings::dup(l)!)!;
                };
                append(link_args, fmt::asprintf("{}.so", outfile)!)!;
            };
        } else if(staticlib || sharedlib){
            append(link_args, strings::dup("-lc")!)!;
        };
        append(link_args, also_link...)!;

        const file = &memio::dynamic();
        defer io::close(file)!;
        fmt::fprintfln(file, "# code generated by lcc v{}", version)!;
        const tpe_c = len(typedefs);
        for(let tp = 0z; tp < tpe_c; tp += 1){
            const tpe = typedefs[tp];
            if(tpe is *aggregated){
                const agg = tpe as *aggregated;
                if(agg.kind == keyword::UNION){
                    fmt::fprintf(file, "type {} = align 8 {{ l", agg.name)!;
                    for(let tp .. agg.base){
                        if(!comp_type(tp, primitive::UNIT) && !comp_type(tp, primitive::VOID)){
                            fmt::fprintf(file, ", {}", qbe_t(agg.base[0], mode::ASSIGN))!;
                        };
                    };
                    fmt::fprintfln(file, " }} # {}", strtype(agg))!;
                } else {
                    assert(false, "TODO: records");
                };
            };
        };
        fmt::fprint(file, memio::string(obj.buffer)!)!;

        let skip = []: []str;
        defer free(skip);
        match(gen_mods(file, obj, &link_args, &skip)){
        case let err: COMPERR =>
            defer free(err.1);
            defer io::close(err.1)!;

            color(memio::string(err.1)!);
            os::exit(err.0);
        case void => void;
        };
        const lit_c = len(literals);
        for(let lit = 0z; lit < lit_c; lit += 1){
            const length = true_size(literals[lit]);
            fmt::fprintfln(file,
                "section \".rodata\"\ndata $lit.{} = align 16 {{ l {}, l {}, b \"{}\" }}", 
                lit, length + 16, length, literals[lit])!;
        };
        if(just_check){
            if(!silent) fmt::println(memio::string(file)!)!;
            return;
        };
        run_cmd(silent, "mkdir", "-p", temp);
        const object =
            match(os::create(qbe_out, fs::mode::USER_RWX)){
            case let f: io::file => yield f;
            case let e: fs::error =>
                color_error("%Robject dispatch error:%r {}",
                    fs::strerror(e));
            };
        io::write(object, strings::toutf8(memio::string(file)!))!;
        io::close(object)!;

        run_cmd(silent, "qbe", "-o", asm_src, qbe_out);

        // append runtime
        const rt_src = strings::concat(libpath, "rt.asm")!;
        defer free(rt_src);

        const rt_file = os::open(rt_src, fs::flag::RDONLY)!;
        const rt_asm = &memio::dynamic();
        defer io::close(rt_asm)!;

        for(true) match(bufio::read_line(rt_file)!){
        case io::EOF =>
            break;
        case let l: []u8 =>
            fmt::fprintln(rt_asm, u8tostr(l))!;
            free(l);
        };
        io::close(rt_file)!;

        const asm_file = os::open(asm_src, fs::flag::RDWR | fs::flag::APPEND)!;
        io::write(asm_file, strings::toutf8(memio::string(rt_asm)!))!;
        io::close(asm_file)!;

        run_cmd(silent, "as" , "-o", obj_out, asm_src);
        if(!onlibc){
            run_cmd(silent, "ld", link_args...);
        } else {
            run_cmd(silent, "cc", link_args...);
        };
        if(staticlib){
            const out = fmt::asprintf("{}.a", outfile)!;
            defer free(out);
            const obj = fmt::asprintf("{}.o", outfile)!;
            defer free(obj);
            run_cmd(silent, "ar", "rcs", out, obj);
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

fn gen_mods(file: *memio::stream, ctxt: *context, args: *[]str, skip: *[]str)
    (void | COMPERR) = {
    for(let mod ..& ctxt.modules){
        for(let fun_def ..& mod.1.fun_defs){
            const meta = fun_def.meta as *fn_meta;
            const name = strings::replace(meta.name.id, "'", ".q")!;
            defer free(name);
            meta.mod = fmt::asprintf("{}.{}", (mod.0.val as ident).id, name)!;
        };
        for(let var_def ..& mod.1.glob.vars){
            const meta = var_def.meta as *var_meta;
            const name = strings::replace(meta.name.id, "'", ".q")!;
            defer free(name);
            meta.mod = fmt::asprintf("{}.{}", (mod.0.val as ident).id, name)!;
        };
        if(finds(*skip, mod.1.name) is void){
            append(skip, mod.1.name)!;

            gen_file(mod.1, mod.1.head)?;
            fmt::fprint(file, memio::string(mod.1.buffer)!)!;

            gen_mods(file, mod.1, args, skip)?;
        };
    };
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
    const index =
        match(strings::index(strings::sub(u8tostr(ctxt.src), ctxt.begin), "\n")){
        case let i: size => yield i + ctxt.begin;
        case => yield len(ctxt.src);
        };
    const line = ctxt.src[ctxt.begin .. index];
    const (lin, col) = get_pos(ctxt);

    const lin_num = fmt::asprint(lin)!;
    defer free(lin_num);

    fmt::fprintfln(buffer, "\n%b{} %d{}", lin_num,
        u8tostr(line))!;

    for(let c = 0z; c < len(lin_num) + 1; c += 1){
        fmt::fprint(buffer, " ")!;
    };
    const arrow = strings::lpad("^", '~', col)!;
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
