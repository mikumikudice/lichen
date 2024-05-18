use os;
use fmt;
use strlib;
use strings;

const stacktrace = false;

export fn main() void = {
    const abt = "mossy is the compiler for the moss programming language.";
    const tut = "not-implemented-yet";

    const usg = fmt::asprintf(
        "mossy usage:\n{}{}{}",
        col("$ ", cmd::YEL),
        col(os::args[0], cmd::GRN),
        col(" <main file> [output file name]", cmd::BLU),
    );
    const hlp = fmt::asprintf(
        "get help on learning how to use moss in {}",
        col(tut, cmd::GRN)
    );
    // check if there are arguments
    if(len(os::args) == 1){
        fmt::printfln("{}\n{}\n\n{}", abt, usg, hlp)!;
        return;
    };
    const src = os::args[1];
    const (name, _) = rem_path(src);
    const outf =
        if(len(os::args) == 2){
            yield strlib::replace(name, ".ms", "");
        } else {
            yield os::args[2];
        };
    build(src, outf);
};
