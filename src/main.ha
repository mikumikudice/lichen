use fs;
use os;
use fmt;
use errors;
use strings;

let silent = true;
let stacktrace = false;
const version = "0.0.1-n100a";

export fn main() void = {
    const abt = "mossy is the compiler for the moss programming language.\n";
    const tut = "https://git.sr.ht/~mikaela-md/mossy/tree/main/doc/tut.md";

    const usg = fmt::asprintf("mossy usage:\n\n {}{}{}",
        fmtc("$ ", cmd::YEL), fmtc(os::args[0], cmd::GRN),
        fmtc(" [flags] <main file> [output file name]", cmd::BLU));

    const allflags = strings::concat(
        fmtc("\n -h\t\t", cmd::GRN),
        fmtc("-- prints this help message", cmd::YEL),

        fmtc("\n -v\t\t", cmd::GRN),
        fmtc("-- prints the current version of the compiler", cmd::YEL),

        fmtc("\n -l ", cmd::GRN), fmtc("<lib path>\t", cmd::BLU),
        fmtc("-- sets path for stdlib and runtime", cmd::YEL),

        fmtc("\n -vb\t\t", cmd::GRN),
        fmtc("-- makes the compiler print each executed command", cmd::YEL),

        fmtc("\n -st\t\t", cmd::GRN),
        fmtc("-- makes the compiler print every parsing step", cmd::YEL)
    );
    const flg = fmt::asprintf("\nflags usage:\n{}", allflags);
    const hlp = fmt::asprintf("\nget help on learning how to use moss in {}",
        fmtc(tut, cmd::GRN));

    const home = os::getenv("HOME"): str;
    let argc = len(os::args);
    // check if there are arguments
    if(argc == 1){
        fmt::printfln("{}\n{}\n{}\n{}", abt, usg, flg, hlp)!;
        return;
    } else if(argc == 2){
        if(os::args[1] == "-v" || os::args[1] == "--version"){
            fmt::printfln("moss compiler v{}", version)!;
            return;
        } else if(os::args[1] == "-h" || os::args[1] == "--help"){
            fmt::printfln("{}\n{}\n", usg, flg)!;
            return;
        };
    };
    let libset = false;
    let outset = false;
    let infset = false;
    let libpath = fmt::asprintf("{}/{}", os::getenv("HOME"): str, ".local/lib/lime/");
    let outfile = "";
    let srcname = "";
    // parse command line arguments
    for(let a = 1z; a < argc; a += 1){
        const arg = os::args[a];
        if(strings::hasprefix(arg, "-")){
            switch(arg){
            case "-l" =>
                a += 1;
                if(a < argc){
                    libset = true;
                    libpath = os::args[a];
                    continue;
                } else {
                    fmt::fatalf("{}\n{}\n",
                        fmtc("missing lib path for -l flag", cmd::RED), flg);
                };
            case "-vb" =>
                silent = false;
                continue;
            case "-st" =>
                stacktrace = true;
                continue;
            case =>
                fmt::fatalf("{} {}\n{}\n",
                    fmtc("unknown flag", cmd::RED), fmtc(arg, cmd::GRN), flg);
            };
        };
        if(!infset){
            infset = true;
            srcname = arg;
        } else if(!outset){
            outset = true;
            outfile = arg;
        };
    };
    if(!infset){
        fmt::fatalf("{}\n{}\n", fmtc("no input file given", cmd::RED), usg);
    };
    const path =
        if(strings::hassuffix(libpath, "/")){
            yield libpath;
        } else {
            yield strings::concat(libpath, "/");
        };
    const filename = rem_path(srcname).0;
    if(!outset){
        outfile = strings::replace(filename, ".ms", "");
    };
    if(!os::exists(path)){
        fmt::fatalf("{} the given path {} does not exists",
            fmtc("lib path error:", cmd::BOX_RED), fmtc(path, cmd::YEL));
    };
    let mods = []: []*module;
    let glob = scope {
        over = void,
        defs = [],
        funs = [],
    };
    append(glob.defs, &unit);
    let ctxt = context {
        scp = &glob,
        uses = &mods,
        libpath = path,
        datasec = "",
        strlits = [],
        onloop = false,
        loopid = 0,
        nomain = false,
        hasmain = false,
        hostfn = "",
        effect = [],
    };
    build(srcname, outfile, &ctxt)!;
};
