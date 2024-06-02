use os;
use fmt;
use strlib;
use strings;

const track_nxttk = false;

const version = "0.0.1";

export fn main() void = {
    const abt = "mossy is the compiler for the moss programming language.";
    const tut = "not-implemented-yet";

    const home = os::getenv("HOME"): str;

    const usg = fmt::asprintf("mossy usage:\n\t{}{}{}",
        col("$ ", cmd::YEL), col(os::args[0], cmd::GRN),
        col(" [flags] <main file> [output file name]", cmd::BLU));

    const flg = fmt::asprintf(col("-l{}", cmd::GRN), col("<lib path>", cmd::BLU));
    const hlp = fmt::asprintf("get help on learning how to use moss in {}",
        col(tut, cmd::GRN));

    let argc = len(os::args) - 1;
    // check if there are arguments
    if(argc == 0){
        fmt::printfln("{}\n{}\nflags usage:\n\t{}\n\n{}", abt, usg, flg, hlp)!;
        return;
    } else if(argc == 1 && (os::args[1] == "-v" || os::args[1] == "--version")){
        fmt::printfln("moss compiler v{}", version)!;
        return;
    };
    let libset = false;
    const libpath = fmt::asprintf("{}/{}",
        os::getenv("HOME"): str, ".local/lib/lime/");
    let lib = libpath;
    const src =
        if(strlib::startswith(os::args[1], "-l")){
            yield
            if(argc > 1){
                if(os::args[1] == "-l"){
                    fmt::errorln("empty libpath flag")!;
                    os::exit(1);
                };
                lib = strings::sub(os::args[1], 2);
                libset = true;
                yield os::args[2];
            } else {
                fmt::errorln("missing source file name")!;
                fmt::fatalf("flags usage\n\t:{}", flg);
            };
        } else {
            yield os::args[1];
        };
    const (name, _) = rem_path(src);
    const outf =
        if((argc == 1 && lib == libpath) || argc == 1){
            yield strlib::replace(name, ".ms", "");
        } else {
            if(libset) yield os::args[3];
            yield os::args[2];
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
        libpath = lib,
        nomain = false,
        hasmain = false,
        hostfn = "",
        effect = [],
    };
    build(src, outf, &ctxt)!;
};
