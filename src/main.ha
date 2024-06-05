use os;
use fmt;
use strings;

let silent = true;
let stacktrace = false;
const version = "0.0.1";

export fn main() void = {
    const abt = "mossy is the compiler for the moss programming language.";
    const tut = "https://git.sr.ht/~mikaela-md/mossy/tree/main/doc/tut.md";

    const usg = fmt::asprintf("\nmossy usage:\n\t{}{}{}",
        fmtc("$ ", cmd::YEL), fmtc(os::args[0], cmd::GRN),
        fmtc(" [flags] <main file> [output file name]", cmd::BLU));

    const allflags = strings::concat(
        fmtc("\n\t-l ", cmd::GRN), fmtc("<lib path>\t", cmd::BLU), fmtc("-- sets path for stdlib and runtime", cmd::YEL),
        fmtc("\n\t-v\t\t", cmd::GRN), fmtc("-- makes the compiler print each executed command", cmd::YEL),
        fmtc("\n\t-st\t\t", cmd::GRN), fmtc("-- makes the compiler print every parsing step", cmd::YEL)
    );
    const flg = fmt::asprintf("\nflags usage:{}", allflags);
    const hlp = fmt::asprintf("\nget help on learning how to use moss in {}",
        fmtc(tut, cmd::GRN));

    const home = os::getenv("HOME"): str;
    let argc = len(os::args);
    // check if there are arguments
    if(argc == 1){
        fmt::printfln("{}\n{}{}\n{}", abt, usg, flg, hlp)!;
        return;
    } else if(argc == 2 && (os::args[1] == "-v" || os::args[1] == "--version")){
        fmt::printfln("moss compiler v{}", version)!;
        return;
    };
    let libset = false;
    let outset = false;
    let infset = false;
    let libpath = fmt::asprintf("{}/{}",
        os::getenv("HOME"): str, ".local/lib/lime/");
    let outfile = "";
    let srcname = "";
    // parse command line arguments
    for(let a = 1z; a < argc; a += 1){
        const arg = os::args[a];
        switch(arg){
        case "-l" =>
            a += 1;
            if(a < argc){
                libset = true;
                libpath = os::args[a];
                continue;
            } else {
                fmt::fatalf("{}\n{}", fmtc("missing lib path for -l flag", cmd::RED), flg);
            };
        case "-v" =>
            silent = false;
            continue;
        case "-st" =>
            stacktrace = true;
            continue;
        case => void;
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
        fmt::fatalf("{}\n{}", fmtc("no input file given", cmd::RED), usg);
    };
    const filename = rem_path(srcname).0;
    if(!outset){
        outfile = strings::replace(filename, ".ms", "");
    };
    let mods = []: []*module;
    let glob = scope {
        over = void,
        defs = [],
        funs = [],
    };
    let ctxt = context {
        scp = &glob,
        uses = &mods,
        libpath = libpath,
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
