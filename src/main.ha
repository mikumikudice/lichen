use io;
use os;
use fs;
use fmt;
use memio;
use strings;

let silent = true;
let just_check = false;
const version = "0.4.0";

export fn main() void = {
    const abt = "mmc is the compiler for the moss programming language.";
    const usg = fmt::asprintf(
        "mmc usage:\n\n %y$ %g{} "
        "%b[flags] <main file> [output file name]%d",
        os::args[0])!;
    defer free(usg);

    const flg =
        "\nflags usage:\n"
        "\n %g-h\t\t"
        "%y-- prints this help message"
        "\n %g-v\t\t"
        "%y-- prints the current version of the compiler"

        "\n %g-l %b<lib path>\t"
        "%y-- sets path for stdlib and runtime"

        "\n %g-c\t\t"
        "%y-- only checks for compile errors and generates no output files"

        "\n %g-vb\t\t"
        "%y-- makes the compiler print each executed command";

    const hlp =
        "\nget help on learning how to use moss in "
        "%ghttps://git.sr.ht/~mikaela-md/mossy/tree/main/doc/tut.md";

    const home = os::getenv("HOME"): str;

    // check if there are arguments
    let argc = len(os::args);
    if(argc == 1){
        // no arguments given
        const pat = fmt::asprintf("{}\n{}\n{}\n{}", abt, usg, flg, hlp)!;
        defer free(pat);
        color(pat);
        return;
    } else if(argc == 2){
        // versioning
        if(os::args[1] == "-v" || os::args[1] == "--version"){
            fmt::printfln("mika's moss compiler v{}", version)!;
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

    let outfile = "";
    let srcname = "";
    let libpath = fmt::asprintf("{}/{}",
        os::getenv("HOME"): str, ".local/lib/mmclib/")!;
    defer free(libpath);

    // parse command line arguments
    for(let a = 1z; a < argc; a += 1){
        const arg = os::args[a];
        if(strings::hasprefix(arg, "-")){
            switch(arg){
            // libpath flag
            case "-l" =>
                a += 1;
                if(a < argc){
                    libset = true;
                    libpath = os::args[a];
                    continue;
                } else {
                    color("%rmissing lib path for -l flag");
                    color_error(flg);
                };
            // verbose mode
            case "-vb" =>
                silent = false;
                continue;
            case "-c" =>
                just_check = true;
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
    libpath =
        if(strings::hassuffix(libpath, "/")){
            yield libpath;
        } else {
            defer free(libpath);
            yield strings::concat(libpath, "/")!;
        };
    if(!os::exists(libpath)){
        color_error("%rthe given path %y\"{}\"%r does not exists", libpath);
    };

    match(compile(srcname, &memio::dynamic(), true)){
    case let buffer: *memio::stream =>
        defer io::close(buffer)!;
    case let err: COMPERR =>
        defer free(err.1);
        defer io::close(err.1)!;
        color(memio::string(err.1)!);
        os::exit(err.0);
    };
    if(!outset){
        const (base, _) = strings::cut(srcname, ".");
        outfile = base;
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
            case 'r' =>
                fmt::fprintf(&buffer, "\x1b[0;31m")!;
            case 'g' =>
                fmt::fprintf(&buffer, "\x1b[0;32m")!;
            case 'y' =>
                fmt::fprintf(&buffer, "\x1b[0;33m")!;
            case 'b' =>
                fmt::fprintf(&buffer, "\x1b[0;34m")!;
            case 'B' =>
                fmt::fprintf(&buffer, "\x1b[0;40m")!;
            case 'R' =>
                fmt::fprintf(&buffer, "\x1b[0;41m")!;
            case =>
                fmt::fatalf("invalid escape color {}", path[c + 1]: rune);
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

fn error(file: (source | void), fmt: str,
    args: fmt::field...) COMPERR = {
    let buffer = alloc(memio::dynamic())!;
    match(file){
    case void =>
        fmt::fprintfln(buffer, fmt, args...)!;
    case let f: source =>
        const pos = gen_pos(f);
        defer free(pos);
        fmt::fprintf(buffer, "%R{}:%r ", pos)!;
        fmt::fprintfln(buffer, fmt, args...)!;

        const max = len(f.src);
        const index = strings::index(u8tostr(f.src[f.lst..max]), "\n") as size + f.lst;
        assert(index > f.lst);

        const line = fmt::asprint(f.lin + 1)!;
        defer free(line);

        fmt::fprintfln(buffer, "%b{} %d{}", line,
            u8tostr(f.src[f.lst..index]))!;
        for(let c = 0z; c < len(line) + 1; c += 1){
            fmt::fprint(buffer, " ")!;
        };
        const arrow = strings::lpad("^", '~', f.cln)!;
        defer free(arrow);
        fmt::fprintfln(buffer, "%r{}", arrow)!;
    };
    return (1, buffer);
};
