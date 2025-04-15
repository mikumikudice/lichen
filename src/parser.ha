use io;
use os;
use fs;
use fmt;
use bufio;
use memio;
use strings;
use strconv;

// checks if character is alphanumeric
fn is_alnum(char: u8) bool = {
    const nocase = char | 32;
    return ('a' <= nocase && nocase <= 'z') || ('0' <= char && char <= '9'); 
};

// checks if character is whitespace
fn is_whitespace(char: u8) bool = {
    return char == '\n' || char == '\t' || char == ' ';
};

// test units
@test fn test_alnum() void = {
    assert(is_alnum('a'));
    assert(is_alnum('z'));
    assert(is_alnum('A'));
    assert(is_alnum('Z'));
    assert(is_alnum('g'));
    assert(is_alnum('G'));
    assert(is_alnum('0'));
    assert(is_alnum('9'));
    assert(is_alnum('7'));
    assert(!is_alnum('_'));
    assert(!is_alnum('.'));
    assert(!is_alnum('{'));
};

// extracts a formatted version of the current
// parser position in the file
fn gen_pos(file: source) str = {
    return fmt::asprintf("{}:{}:{}", file.name,
        file.lin + 1, file.cln + 1)!;
};

// function shortcut
fn u8tostr(a: []u8) str = strings::fromutf8(a)!;

// loads the file `fname` and instantiates
// a file parsing object
fn load(fname: str) (source | COMPERR) = {
    // open file or rise an error
    const fsrc = match(os::open(fname)){
    case let f: io::file => yield f;
    case let e: fs::error =>
        return error(void,
            "failed to load \"{}\" source file: {}",
            fname, fs::strerror(e));
    };
    defer io::close(fsrc)!;

    let (_, name) = strings::rcut(fname, "/");
    if(name == "") name = fname;

    const file = source {
        name = name,
        lin = 0, cln = 0,
        ptr = 0, lst = 0,
        src = []
    };
    // load every line until EOF
    for(true) match(bufio::read_line(fsrc)!){
        case io::EOF =>
            break;
        case let l: []u8 =>
            append(file.src, l...)!;
            append(file.src, '\n')!;
            free(l);
    };

    if(len(file.src) == 0 ||
    (len(file.src) == 1 && file.src[0] == '\n')){
        return error(void,
            "%Rthe file \"{}\" is empty%d\n\ntry adding:\n\n{}",
            fname, fn_demo);
    };
    return file;
};

// returns the given token as a human-readable string
fn strtoken(tok: tkval) str = {
    match(tok){
    case let idt: ident =>
        return fmt::asprintf("identifier \"{}\"", idt.name)!;
    case let num: number =>
        if(num.0){
            return fmt::asprintf("numeric literal -{}", num.1)!;
        } else {
            return fmt::asprintf("numeric literal {}", num.1)!;
        };
    case let txt: str =>
        return fmt::asprintf("string literal \"{}\"", txt)!;
    case let kwd: keyword =>
        return fmt::asprintf("keyword: {}", kwd_value[kwd])!;
    case let prm: primitive =>
        return fmt::asprintf("type: {}", prm_value[prm])!;
    case let opr: operator =>
        return fmt::asprintf("operator: {}", opr: int)!;
    case let sym: symbol =>
        if(sym == symbol::EOL){
            return fmt::asprint("end of line")!;
        } else {
            return fmt::asprintf("symbol: {}", sym: int)!;
        };
    case eof =>
        return fmt::asprint("end of file")!;
    };
};

// move virtual column and adjust line count accordingly
fn move_cln(file: *source) void = {
    const max = len(file.src);
    file.cln += 1;
    if(file.ptr < max && file.src[file.ptr] == '\n'){
        file.lin += 1;
        file.cln = 0;
        file.lst = file.ptr + 1;
    };
};

// compare two tokens
fn comp_tk(lft: tkval, rgt: tkval) bool = {
    match(lft){
    case let idt: ident =>
        if(rgt is ident){
            const r = rgt as ident;
            return r.name == idt.name;
        } else {
            return false;
        };
    case let num: number =>
        if(rgt is number){
            const r = rgt as number;
            return num.0 == r.0 && num.1 == r.1;
        } else {
            return false;
        };
    case let txt: str =>
        return rgt is str && txt == rgt as str;
    case let kwd: keyword =>
        return rgt is keyword && kwd == rgt as keyword;
    case let prm: primitive =>
        return rgt is primitive && prm == rgt as primitive;
    case let opr: operator =>
        return rgt is operator && opr == rgt as operator;
    case let sym: symbol =>
        return rgt is symbol && sym == rgt as symbol;
    };
};

fn new_tk(file: source, val: tkval) token = {
    return token {
        lin = file.lin,
        cln = file.cln,
        val = val,
    };
};

// compiles down a given file to its QBE IR equivalent as a memio stream
// returns a COMPERR if any compilation error occurs.
fn compile(filename: str, buffer: *memio::stream, main: bool = false)
    (*memio::stream | COMPERR) = {
    // load source file
    const file = load(filename)?;
    defer free(file.src);

    // tokenize
    let max = len(file.src);
    let tokens = []: []token;
    for(file.ptr < max){
        // remove comments
        if(file.src[file.ptr] == '/' && file.ptr < max - 1){
            if(strings::fromutf8(file.src[file.ptr .. file.ptr + 2])! == "//"){
                for(file.ptr < max && file.src[file.ptr] != '\n'){
                    file.ptr += 1;
                    move_cln(&file);
                };
            };
        };
        // keyword or identifier
        if(is_alnum(file.src[file.ptr]) || file.src[file.ptr] == '_'){
            const start = file.ptr;
            for(file.ptr < max && is_alnum(file.src[file.ptr]) ||
                file.src[file.ptr] == '_'){
                file.ptr += 1;
                move_cln(&file);
            };
            let matched = false;
            const path = u8tostr(file.src[start..file.ptr]);

            // check for reserved keywords
            for(let i = 0z; i < len(kwd_value); i += 1){
                if(kwd_value[i] == path){
                    append(tokens, new_tk(file, i: keyword))!;
                    matched = true;
                    break;
                };
            };
            if(matched) continue;
            // check for primitive types
            for(let i = 0z; i < len(prm_value); i += 1){
                if(prm_value[i] == path){
                    append(tokens, new_tk(file, i: primitive))!;
                    matched = true;
                    break;
                };
            };
            if(matched) continue;
            // check for numeric literals
            if(strings::hasprefix(path, "0x")){
                match(strconv::stou64(strings::sub(path, 2),
                strconv::base::HEX)){
                case let n: u64 =>
                    append(tokens, new_tk(file, (false, n)))!;
                case strconv::overflow =>
                    return error(file,
                        "64-bit hexadecimal literal overflow");
                case =>
                    return error(file,
                        "invalid hexadecimal literal");
                };
            } else if(strings::hasprefix(path, "0o")){
                match(strconv::stou64(strings::sub(path, 2),
                strconv::base::OCT)){
                case let n: u64 =>
                    append(tokens, new_tk(file, (false, n)))!;
                case strconv::overflow =>
                    return error(file,
                        "64-bit octal literal overflow");
                case =>
                    return error(file,
                        "invalid hexadecimal literal");
                };
            } else if(strings::hasprefix(path, "0b")){
                match(strconv::stou64(strings::sub(path, 2),
                strconv::base::BIN)){
                case let n: u64 =>
                    append(tokens, new_tk(file, (false, n)))!;
                case strconv::overflow =>
                    return error(file,
                        "64-bit binary literal overflow");
                case =>
                    return error(file,
                        "invalid binary literal");
                };
            } else {
                match(strconv::stou64(path)){
                case let n: u64 =>
                    append(tokens, new_tk(file, (false, n)))!;
                case strconv::overflow =>
                    return error(file,
                        "64-bit literal overflow");
                case =>
                    for(file.ptr < max && file.src[file.ptr] == '\''){
                        file.ptr += 1;
                        move_cln(&file);
                    };
                    append(tokens, new_tk(file, ident {
                        name = u8tostr(file.src[start..file.ptr]),
                        itpe = primitive::ANY
                    }))!;
                };
            };
        // symbol or string/character literal
        } else if(!(is_alnum(file.src[file.ptr]) || is_whitespace(file.src[file.ptr]))){
            let start = file.ptr;
            for(file.ptr < max && !(is_alnum(file.src[file.ptr]) ||
                is_whitespace(file.src[file.ptr]))){
                file.ptr += 1;
                move_cln(&file);
            };
            // string literal
            if(file.src[start] == '\"'){
                start += 1;
                file.cln += start - file.ptr;
                file.ptr = start;
                let escape = false;
                let closed = false;
                for(file.ptr < max && !closed){
                    switch(file.src[file.ptr]){
                    case '\\' =>
                        escape = !escape;
                    case '\"' =>
                        if(!escape){
                            closed = true;
                            escape = false;
                        };
                    case 't' =>
                        if(escape){
                            escape = false;
                        };
                    case 'b' =>
                        if(escape){
                            escape = false;
                        };
                    case 'a' =>
                        if(escape){
                            escape = false;
                        };
                    case 'r' =>
                        if(escape){
                            escape = false;
                        };
                    case 'n' =>
                        if(escape){
                            escape = false;
                        };
                    case 'f' =>
                        if(escape){
                            escape = false;
                        };
                    case '0' =>
                        if(escape){
                            escape = false;
                        };
                    case '\n' =>
                        file.ptr += 1;
                        move_cln(&file);    
                        break;
                    case =>
                        if(escape){
                            return error(file, "invalid escape sequence \"\\{}\"",
                                file.src[file.ptr]: rune);
                        };
                    };
                    file.ptr += 1;
                    move_cln(&file);
                };
                if(!closed) return error(file, "unclosed string found here");
                assert(!escape);
                append(tokens, new_tk(file,
                    u8tostr(file.src[start..(file.ptr - 1)])))!;
                continue;
            // character literal
            } else if(file.src[start] == '\''){
                let val: u64 = 0;
                switch(file.src[start]){
                case '\\' =>
                    if(start < max){
                        switch(file.src[start + 1]){
                        case '\'' =>
                            val = '\'';
                        case 't' =>
                            val = '\t';
                        case 'b' =>
                            val = '\b';
                        case 'a' =>
                            val = '\a';
                        case 'r' =>
                            val = '\r';
                        case 'n' =>
                            val = '\n';
                        case 'f' =>
                            val = '\f';
                        case '0' =>
                            val = '\0';
                        case =>
                            return error(file, "invalid escape sequence");
                        };
                    } else {
                        return error(file, "invalid escape sequence");
                    };
                case =>
                    val = file.src[start];
                };
                if(start >= max || file.src[start + 1] != '\''){
                    return error(file, "unclosed character literal found here");
                };
                append(tokens, new_tk(file, (false, val): number))!;
                continue;
            };
            for(start < file.ptr) switch(file.src[start]){
            case ';' =>
                append(tokens, new_tk(file, symbol::EOL))!;
                start += 1;
            case ',' =>
                append(tokens, new_tk(file, symbol::COMMA))!;
                start += 1;
            case '(' =>
                append(tokens, new_tk(file, symbol::LFT_PAR))!;
                start += 1;
            case ')' =>
                append(tokens, new_tk(file, symbol::RGT_PAR))!;
                start += 1;
            case '{' =>
                append(tokens, new_tk(file, symbol::LFT_CURLY))!;
                start += 1;
            case '}' =>
                append(tokens, new_tk(file, symbol::RGT_CURLY))!;
                start += 1;
            case '[' =>
                append(tokens, new_tk(file, symbol::LFT_SQUARE))!;
                start += 1;
            case ']' =>
                append(tokens, new_tk(file, symbol::RGT_SQUARE))!;
                start += 1;
            case '#' =>
                append(tokens, new_tk(file, operator::LENGTH))!;
                start += 1;
            case '.' =>
                if(start < file.ptr - 1 && file.src[start  + 1] == '.'){
                    append(tokens, new_tk(file, operator::RANGE))!;
                } else {
                    append(tokens, new_tk(file, symbol::DOT))!;
                };
                start += 1;
            case '=' =>
                if(start < file.ptr - 1 && file.src[start  + 1] == '='){
                    append(tokens, new_tk(file, operator::EQL))!;
                } else {
                    append(tokens, new_tk(file, operator::ASG))!;
                };
                start += 1;
            case '<' =>
                if(start < file.ptr - 1){
                    if(file.src[start  + 1] == '='){
                        append(tokens, new_tk(file, operator::LEQ))!;
                    } else if(file.src[start  + 1] == '>'){
                        append(tokens, new_tk(file, operator::SHL))!;
                    } else {
                        append(tokens, new_tk(file, operator::LST))!;
                    };
                } else {
                    append(tokens, new_tk(file, operator::LST))!;
                };
                start += 1;
            case '>' =>
                if(start < file.ptr - 1){
                    if(file.src[start  + 1] == '='){
                        append(tokens, new_tk(file, operator::GEQ))!;
                    } else if(file.src[start  + 1] == '>'){
                        append(tokens, new_tk(file, operator::SHR))!;
                    } else {
                        append(tokens, new_tk(file, operator::GTT))!;
                    };
                } else {
                    append(tokens, new_tk(file, operator::GTT))!;
                };
                start += 1;
            case '|' =>
                if(start < file.ptr - 1 && file.src[start + 1] == '|'){
                    append(tokens, new_tk(file, operator::LOR))!;
                } else {
                    append(tokens, new_tk(file, operator::BOR))!;
                };
                start += 1;
            case '&' =>
                if(start < file.ptr - 1 && file.src[start + 1] == '&'){
                    append(tokens, new_tk(file, operator::LAND))!;
                } else {
                    append(tokens, new_tk(file, operator::BAND))!;
                };
                start += 1;
            case ':' =>
                if(start < file.ptr - 1 && file.src[start + 1] == ':'){
                    append(tokens, new_tk(file, symbol::FIELD))!;
                } else {
                    append(tokens, new_tk(file, operator::FDIV))!;
                };
                start += 1;
            case '!' =>
                if(start < file.ptr - 1 && file.src[start + 1] == '='){
                    append(tokens, new_tk(file, operator::NEQ))!;
                } else {
                    append(tokens, new_tk(file, operator::BANG))!;
                };
                start += 1;
            case '~' =>
                append(tokens, new_tk(file, operator::NOT))!;
                start += 1;
            case '+' =>
                append(tokens, new_tk(file, operator::PLS))!;
                start += 1;
            case '-' =>
                append(tokens, new_tk(file, operator::MIN))!;
                start += 1;
            case '*' =>
                append(tokens, new_tk(file, operator::MUL))!;
                start += 1;
            case '/' =>
                append(tokens, new_tk(file, operator::IDIV))!;
                start += 1;
            case '%' =>
                append(tokens, new_tk(file, operator::MOD))!;
                start += 1;
            case '?' =>
                append(tokens, new_tk(file, operator::PROP))!;
                start += 1;
            case '\"' =>
                file.ptr = start;
                break;
            case '\'' =>
                file.ptr = start;
                break;
            case =>
                return error(file, "invalid symbol \"{}\"", file.src[start]: rune);
            };
        // just whitespace
        } else {
            file.ptr += 1;
            move_cln(&file);
        };
    };
    append(tokens, new_tk(file, eof))!;
    defer free(tokens);
    max = len(tokens);
    let node = alloc(ast {
        kind = tk_type::EOF,
        path = tokens[(max - 1)..(max - 1)],
        next = null,
        last = null,
    })!;
    const head = node;
    for(let t = 0z; t < max; t += 1){
        match(tokens[t].val){
        case let idt: ident =>
            // const global definition
            if(comp_tk(tokens[t + 1].val, operator::ASG)){
                const end = eval_c_exp(tokens, &node, t + 2)?;
            };
        case let kwd: keyword => void;
        case let sym: symbol => void;
        case => continue;
        };
    };
    defer for(let n = head: nullable *ast; !(n is null)){
        defer free(n);
        fmt::println(strtoken(n.))
        n = (n: *ast).next;
    };
    return buffer;
};

fn eval_c_exp(tokens: []token, node: **ast, at: size) (size | COMPERR) = {
    return 0z;
};