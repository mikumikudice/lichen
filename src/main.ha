use bufio;
use fmt;
use io;
use memio;
use os;
use strings;

const temp = "lcc_temp/";
const version = "0.12.6";
const help =
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
    "%y-- keeps temporary files at %gtmp/%y folder"
    "\n%gget help on learning how to use lichen in "
    "%bhttps://git.sr.ht/~mikaela-md/lcc/tree/main/doc/tut.md";

export fn main() void = {
    let prompt_log = false;
    let keep_temps = false;
    let just_check = false;
    let static_lib = false;
    let shared_lib = false;
    let target_file = "";
    let source_file = "";
    let stdlib_path = "";

    const about = fmt::asprintf(
        "%glichen compiler usage:%y {} %b[flags]%y <source-file> %b[dest-file]",
        os::args[0])!;
    defer free(about);

    const also_link: []str = [];
    defer free(also_link);

    const argc = len(os::args);
    // parse command line arguments
    for(let a = 1z; a < argc; a += 1){
        const arg = os::args[a];
        if(strings::hasprefix(arg, "-")){
            if(arg == "-l"){
                color_error("%rmissing link object name with %y-l");
            };
            if(strings::hasprefix(arg, "-l")){
                append(also_link, arg)!;
                continue;
            };
            switch(arg){
            // versioning
            case "-v", "--version" =>
                color("%glichen compiler %yv{}", version);
                return;
            // help
            case "-h", "--help" =>
                color(about);
                color(help);
                return;
            // std libpath flag
            case "-std" =>
                a += 1;
                if(a < argc){
                    stdlib_path =
                        if(strings::hassuffix(os::args[a], "/")){
                            yield strings::dup(os::args[a])!;
                        } else {
                            yield strings::concat(os::args[a], "/")!;
                        };
                    continue;
                } else {
                    color_error("%rmissing lib path for -std flag");
                };
            case "-static" =>
                if(shared_lib){
                    color_error("%rcannot set both static and shared flags");
                };
                static_lib = true;
            case "-shared" =>
                if(static_lib){
                    color_error("%rcannot set both static and shared flags");
                };
                shared_lib = true;
            // verbose mode
            case "-verbose" =>
                prompt_log = true;
                continue;
            // parse-only mode
            case "-E" =>
                just_check = true;
                continue;
            // keep temps mode
            case "-t" =>
                keep_temps = true;
                continue;
            case =>
                color_error("%runknown flag %g{}", arg);
            };
        } else {
            // input file
            if(source_file == ""){
                source_file = arg;
            // output file
            } else {
                // define only once
                if(target_file != ""){
                    color_error("%rmultiple output files given");
                };
                target_file = arg;
            };
        };
    };
    if(source_file == ""){
        color_error("%rno input file given");
    };
    // set the output filename to default if not set
    if(target_file == ""){
        target_file = strings::rcut(source_file, ".").0;
    };
    let free_path = false;
    // set the stdlib path to default if not set
    if(stdlib_path == ""){
        stdlib_path = fmt::asprintf("{}/.local/lib/lcc/",
            os::getenv("HOME"): str)!;
        free_path = true;
    };
    defer free(stdlib_path);
    const object =
        match(compile(source_file, stdlib_path,
            !(shared_lib || static_lib))){
        case let obj: *context => yield obj;
        case let err: ERROR => report(err);
        };
    defer free_context(object, true);
    if(just_check && !prompt_log){
        return;
    };
    const qbe_ir = gen_qbe_ir(object);
    defer io::close(&qbe_ir)!;
    if(just_check && prompt_log){
        fmt::println(memio::string(&qbe_ir)!)!;
        return;
    };
    emit_obj(&qbe_ir, also_link, target_file, stdlib_path,
        shared_lib, static_lib, !prompt_log);

    // delete all temp files if not set otherwise
    if(!keep_temps) run_cmd(!prompt_log, "rm", "-r", temp);
};
