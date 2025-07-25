use fmt;
use memio;
use io;
use os;
use os::exec;
use strings;

// extracts a formatted version of the current
// parser position in the file
fn gen_pos(ctxt: *context) str = {
    const (l, c) = get_pos(ctxt);
    return fmt::asprintf("{}:{}:{}", ctxt.file, l, c)!;
};

// calculates token coordinates from source pointer
// very unoptimized. should be used only when error reporting
fn get_pos(ctxt: *context) (size, size) = {
    const max = len(ctxt.src);
    let l = 0z;
    let c = 0z;
    let i = 0z;
    // iterate over file source
    for(i < ctxt.ptr; i += 1){
        c += 1;
        // reset column and increase line counts
        if(ctxt.src[i] == '\n'){
            c = 0;
            l += 1;
        };
    };
    return (l + 1, c + 1);
};

// parses color notation of a given string
fn add_color(path: []u8) *memio::stream = {
    const buffer = alloc(memio::dynamic())!;
    for(let c = 0z; c < len(path); c += 1){
        const chr = path[c];
        if(chr == '%'){
            if(no_color){
                c += 1;
                continue;
            };
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
    if(!no_color) fmt::fprint(buffer, "\x1b[0m")!;
    return buffer;
};

// prints a colorized string to stdout
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

// prints a colorized string to stderr
fn color_error(fmt: str, args: fmt::field...) void = {
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

    fmt::errorln(memio::string(buffer)!)!;
};

// halts on a TODO item
fn todo(item: str) never = {
    fmt::fatalf("TODO: {}", item);
};

// reports an error an halts execution
fn report(err: ERROR) never = {
    color(memio::string(err)!);
    io::close(err)!;
    free(err);
    os::exit(1);
};

// formats and returns a simple compilation fail
fn fail(fmt: str, args: fmt::field...) ERROR = {
    const buff = memio::dynamic();
    fmt::fprint(&buff, "%r")!;
    fmt::fprintf(&buff, fmt, args...)!;
    fmt::fprint(&buff, "%d")!;
    return alloc(buff)!;
};

// formats and returns a parsing error
fn error(ctxt: *context, fmt: str, args: fmt::field...) ERROR = {
    const buff = memio::dynamic();
    fmt::fprintf(&buff, "%R{}:%r ", gen_pos(ctxt))!;
    fmt::fprintf(&buff, fmt, args...)!;
    fmt::fprint(&buff, "%d\n")!;
    error_line(ctxt, &buff);
    return alloc(buff)!;
};

fn error_hint(
    ctxt: *context,
    hint: str, 
    fmt: str,
    args:
    fmt::field...
) ERROR = {
    const buff = memio::dynamic();
    fmt::fprintf(&buff, "%R{}:%r ", gen_pos(ctxt))!;
    fmt::fprintf(&buff, fmt, args...)!;
    fmt::fprint(&buff, "%d\n")!;
    error_line(ctxt, &buff);
    fmt::fprintln(&buff, hint)!;
    return alloc(buff)!;
};

// generates the error line arrow
fn error_line(ctxt: *context, buffer: *memio::stream) void = {
    const index =
        match(strings::index(
            strings::sub(strings::fromutf8(ctxt.src)!, ctxt.begin), "\n")){
        case let i: size => yield i + ctxt.begin;
        case => yield len(ctxt.src);
        };
    const line = ctxt.src[ctxt.begin .. index];
    const (lin, col) = get_pos(ctxt);

    const lin_num = fmt::asprint(lin)!;
    defer free(lin_num);

    fmt::fprintfln(buffer, "\n%b{} %d{}", lin_num,
        strings::fromutf8(line)!)!;

    for(let c = 0z; c < len(lin_num) + 1; c += 1){
        fmt::fprint(buffer, " ")!;
    };
    const arrow = strings::lpad("^", '~', col)!;
    defer free(arrow);
    fmt::fprintfln(buffer, "%r{}", arrow)!;
};

// runs a command
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
                os::exit(1);
            } else {
                color_error("%r{} failed", cmd);
                os::exit(1);
            };
        };
    const proc = exec::start(&exe)!;
    const stat = exec::wait(&proc)!;
    if(stat.status != 0) color_error("%r{} failed", cmd);
};

fn ordnum(n: u64) str = {
    switch(n){
    case 1 => return strings::dup("first")!;
    case 2 => return strings::dup("second")!;
    case 3 => return strings::dup("third")!;
    case => return fmt::asprintf("{}th", n)!;
    };
};

fn fix_plural(obj: str, count: size) str = {
    if(count > 1) return obj;
    return strings::sub(obj, 0, len(obj) - 2);
};

const fn_demo = "pub fn main() void = {\n\t// your code goes here!%d\n};";
