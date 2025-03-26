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
    const abt = "mmc is the compiler for the moss programming language.\n";
    const usg = fmt::asprintf(
        "mmc usage:\n\n $ {} "
        "[flags] <main file> [output file name]",
        os::args[0])!;
    defer free(usg);

    const flg =
        "\nflags usage:\n"
        "\n -h\t\t"
        "-- prints this help message"
        "\n -v\t\t"
        "-- prints the current version of the compiler"

        "\n -l <lib path>\t"
        "-- sets path for stdlib and runtime"

        "\n -vb\t\t"
        "-- makes the compiler print each executed command";

    const hlp =
        "\nget help on learning how to use moss in "
        "https://git.sr.ht/~mikaela-md/mossy/tree/main/doc/tut.md";

    const home = os::getenv("HOME"): str;

    // check if there are arguments
    let argc = len(os::args);
    if(argc == 1){
        // no arguments given
        fmt::printfln("{}\n{}\n{}\n{}", abt, usg, flg, hlp)!;
        return;
    } else if(argc == 2){
        // versioning
        if(os::args[1] == "-v" || os::args[1] == "--version"){
            fmt::printfln("mika's moss compiler v{}", version)!;
            return;
        // help
        } else if(os::args[1] == "-h" || os::args[1] == "--help"){
            fmt::printfln("{}\n{}\n", usg, flg)!;
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
                    fmt::fatalf("missing lib path for -l flag\n{}\n", flg);
                };
            // verbose mode
            case "-vb" =>
                silent = false;
                continue;
            case "-c" =>
                just_check = true;
                continue;
            case =>
                fmt::fatalf("unknown flag {}\n{}\n", arg, flg);
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
                fmt::fatalf("multiple output files given\n{}\n", usg);
            };
        };
    };
    if(!infset){
        fmt::fatalf("no input file given\n");
    };
    libpath =
        if(strings::hassuffix(libpath, "/")){
            yield libpath;
        } else {
            defer free(libpath);
            yield strings::concat(libpath, "/")!;
        };
    if(!os::exists(libpath)){
        fmt::fatalf("the given path \"{}\" does not exists", libpath);
    };

    match(compile(srcname, &memio::dynamic(), true)){
    case let buffer: *memio::stream =>
        defer io::close(buffer)!;
    case let err: COMPERR =>
        defer free(err.1);
        defer io::close(err.1)!;
        fmt::error(memio::string(err.1)!)!;
        os::exit(err.0);
    };
    if(!outset){
        const (base, _) = strings::cut(srcname, ".");
        outfile = base;
    };
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
        fmt::fprintf(buffer, "{}: ", pos)!;
        fmt::fprintfln(buffer, fmt, args...)!;
    };
    return (1, buffer);
};
