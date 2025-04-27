use io;
use os;
use fs;
use fmt;
use bufio;
use memio;
use strings;
use strconv;

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

// checks if character is alphanumeric
fn is_alnum(char: u8) bool = {
    const nocase = char | 32;
    return ('a' <= nocase && nocase <= 'z') || ('0' <= char && char <= '9'); 
};

// checks if character is whitespace
fn is_whitespace(char: u8) bool = {
    return char == '\n' || char == '\t' || char == ' ';
};

// extracts a formatted version of the current
// parser position in the file
fn gen_pos(ctxt: context) str = {
    return fmt::asprintf("{}:{}:{}", ctxt.name,
        ctxt.lin + 1, ctxt.cln + 1)!;
};

// function shortcut
fn u8tostr(a: []u8) str = strings::fromutf8(a)!;

// loads the file `fname` and instantiates
// a file parsing object
fn load(fname: str) (context | COMPERR) = {
    // open file or rise an error
    const fsrc = match(os::open(fname)){
    case let f: io::file => yield f;
    case let e: fs::error =>
        return error(void,
            "%rfailed to load %g\"{}\"%r source file: %y{}",
            fname, fs::strerror(e));
    };
    defer io::close(fsrc)!;

    let (_, name) = strings::rcut(fname, "/");
    if(name == "") name = fname;

    const file = context {
        name = name,
        lin = 0, cln = 0,
        ptr = 0, lst = 0,
        src = [], scp = void,
        glob = scope {
            vars = [],
            upper = void,
        },
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
        return fmt::asprintf("keyword \"{}\"", kwd_value[kwd])!;
    case let prm: primitive =>
        switch(prm){
        case primitive::NUMBER =>
            return "number literal";
        case primitive::RATIO =>
            return "ratio literal";
        case =>
            return fmt::asprintf("primitive type \"{}\"", prm_value[prm])!;
        };
    case let opr: operator =>
        return fmt::asprintf("\"{}\" operator", opr: int)!;
    case let sym: symbol =>
        if(sym == symbol::EOL){
            return fmt::asprint("end of line")!;
        } else {
            return fmt::asprintf("symbol \"{}\"", sym: int)!;
        };
    case eof =>
        return fmt::asprint("end of file")!;
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
    case eof =>
        return rgt is eof;
    };
};

fn new_tk(ctxt: context, val: tkval) token = {
    assert(ctxt.lst != len(ctxt.src));
    return token {
        lin = ctxt.lin,
        cln = ctxt.cln,
        lst = ctxt.lst,
        val = val,
    };
};

// move virtual column and adjust line count accordingly
fn move_cln(ctxt: *context, amount: size = 1) void = {
    const max = len(ctxt.src);
    ctxt.cln += amount;
    if(ctxt.ptr < max && ctxt.src[ctxt.ptr] == '\n'){
        ctxt.lin += 1;
        ctxt.cln = 0;
        if(ctxt.ptr + 1 != max) ctxt.lst = ctxt.ptr + 1;
    };
};

fn move_ptr(ctxt: *context, tk: token) void = {
    ctxt.lin = tk.lin;
    ctxt.cln = tk.cln;
    ctxt.lst = tk.lst;
};

// checks if a given operator is unary
fn is_unary(opr: operator) bool = {
    return opr == operator::MAP || opr == operator::LENGTH ||
        opr == operator::NOT || opr == operator::PLS ||
        opr == operator::MIN || opr == operator::BANG;
};

// checks if a given operator is a binary
fn is_binary(opr: operator) bool = {
    return !is_unary(opr) || opr == operator::PLS || opr == operator::MIN;
};

// pulls next token from token array and asserts for buffer overflow/eof
fn next_tk(ctxt: context, tokens: []token, at: size, msg: str)
    (token | COMPERR) = {
    if(at == len(tokens)){
        const tk = tokens[at - 1];
        ctxt.lin = tk.lin;
        ctxt.cln = tk.cln;
        ctxt.lst = tk.lst;
        return error(ctxt, msg, strtoken(eof));
    };
    return tokens[at];
};

// calls next_tk and asserts if said token is equal to `val`
fn pop_assert(ctxt: context, tokens: []token, at: size, val: tkval, msg: str)
    (size | COMPERR) = {
    const tk = next_tk(ctxt, tokens, at, msg)?;
    if(!comp_tk(tk.val, val)){
        move_ptr(&ctxt, tk);
        return error(ctxt, msg, strtoken(tk.val));
    };
    return at + 1;
};

let count = 0z;

// allocates a new empty ast node
fn new_node(tokens: []token, at: size) *ast = {
    count += 1;
    return alloc(ast {
        kind = path_t::EOF,
        path = tokens[at..at],
        meta = void,
        inner = null,
        next = null,
        last = null,
        ...
    })!;
};

// appends a new node to the ast or returns the new node if it's
// the first node in the tree
fn push_node(this: nullable *ast, new: *ast) nullable *ast = {
    if(this is null) return new;
    const node = this: *ast;
    node.next = new;
    new.last = node;
    return new;
};

// frees the given node and all inner nodes, if any
fn free_nodes(_node: nullable *ast) void = {
    count -= 1;
    const node = _node as *ast;
    match(node.meta){
    case void => void;
    case let exp: expr_meta => void;
    case let var: var_meta => void;
    case let fun: fn_meta =>
        if(len(fun.effects) > 0)
            free(fun.effects);
        free_nodes(fun.params);
    case let param: param_meta =>
        free(param.lin);
        free(param.cln);
        free(param.name);
        free(param.tpe);
    };
    if(!(node.inner is null)){
        free_nodes(node.inner);
    };
    if(!(node.next is null)) free_nodes(node.next);
    free(node);
};

fn get_var(scp: *scope, var: ident) (*ast | void) = {
    for(let var_def ..& scp.vars){
        const meta = var_def.meta as var_meta;
        if(meta.name.name == var.name) return var_def;
    };
    if(scp.upper is *scope)
        return get_var(scp.upper as *scope, var);
};

fn push_var(ctxt: context, var_def: *ast) (void | COMPERR) = {
    const meta = var_def.meta as var_meta;
    match(get_var(ctxt.scp as *scope, meta.name)){
    case void =>
        const scp = ctxt.scp as *scope;
        append(scp.vars, var_def)!;
    case let dup: *ast =>
        const o_meta = dup.meta as var_meta;
        return error(ctxt, "duplicate definition of variable %b{}%r. "
            "previously defined at {}:{}:{}", meta.name.name,
            ctxt.name, o_meta.lin, o_meta.cln);
    };
};

// compiles down a given file to its QBE IR equivalent as a memio stream
// returns a COMPERR if any compilation error occurs.
fn compile(filename: str, buffer: *memio::stream, main: bool = false)
    (*memio::stream | COMPERR) = {
    // load source file
    const ctxt = load(filename)?;
    defer free(ctxt.src);
    defer if(len(ctxt.glob.vars) > 0) free(ctxt.glob.vars);
    ctxt.scp = &ctxt.glob;

    // tokenize
    let max = len(ctxt.src);
    let tokens = []: []token;
    for(ctxt.ptr < max){
        // remove comments
        if(ctxt.src[ctxt.ptr] == '/' && ctxt.ptr < max - 1){
            if(strings::fromutf8(ctxt.src[ctxt.ptr .. ctxt.ptr + 2])! == "//"){
                for(ctxt.ptr < max && ctxt.src[ctxt.ptr] != '\n'){
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                };
            };
        };
        // keyword, numeric literal or identifier
        if(is_alnum(ctxt.src[ctxt.ptr]) || ctxt.src[ctxt.ptr] == '_'){
            const start = ctxt.ptr;
            for(ctxt.ptr < max && is_alnum(ctxt.src[ctxt.ptr]) ||
                ctxt.src[ctxt.ptr] == '_'){
                ctxt.ptr += 1;
                move_cln(&ctxt);
            };
            let matched = false;
            const path = u8tostr(ctxt.src[start..ctxt.ptr]);
            const check = strings::replace(path, "_", "")!;
            defer free(check);

            ctxt.cln = start - ctxt.lst;

            // check for reserved keywords
            for(let i = 0z; i < len(kwd_value); i += 1){
                if(kwd_value[i] == path){
                    append(tokens, new_tk(ctxt, i: keyword))!;
                    matched = true;
                    break;
                };
            };
            if(matched) continue;
            // check for primitive types
            for(let i = 0z; i < len(prm_value); i += 1){
                if(prm_value[i] == path){
                    append(tokens, new_tk(ctxt, i: primitive))!;
                    matched = true;
                    break;
                };
            };
            if(matched) continue;
            // check for numeric literals
            if(strings::hasprefix(check, "0x")){
                match(strconv::stou64(strings::sub(check, 2),
                strconv::base::HEX)){
                case let n: u64 =>
                    append(tokens, new_tk(ctxt, (false, n)))!;
                case strconv::overflow =>
                    return error(ctxt,
                        "64-bit hexadecimal literal overflow");
                case =>
                    return error(ctxt,
                        "invalid hexadecimal literal");
                };
            } else if(strings::hasprefix(check, "0o")){
                match(strconv::stou64(strings::sub(check, 2),
                strconv::base::OCT)){
                case let n: u64 =>
                    append(tokens, new_tk(ctxt, (false, n)))!;
                case strconv::overflow =>
                    return error(ctxt,
                        "64-bit octal literal overflow");
                case =>
                    return error(ctxt,
                        "invalid hexadecimal literal");
                };
            } else if(strings::hasprefix(check, "0b")){
                match(strconv::stou64(strings::sub(check, 2),
                strconv::base::BIN)){
                case let n: u64 =>
                    append(tokens, new_tk(ctxt, (false, n)))!;
                case strconv::overflow =>
                    return error(ctxt,
                        "64-bit binary literal overflow");
                case =>
                    return error(ctxt,
                        "invalid binary literal");
                };
            } else {
                match(strconv::stou64(check)){
                case let n: u64 =>
                    append(tokens, new_tk(ctxt, (false, n)))!;
                case strconv::overflow =>
                    return error(ctxt,
                        "64-bit literal overflow");
                case =>
                    for(ctxt.ptr < max && ctxt.src[ctxt.ptr] == '\''){
                        ctxt.ptr += 1;
                        move_cln(&ctxt);
                    };
                    append(tokens, new_tk(ctxt, ident {
                        name = path,
                        itype = primitive::ANY
                    }))!;
                };
            };
        // symbol or string/character literal
        } else if(!(is_alnum(ctxt.src[ctxt.ptr]) || is_whitespace(ctxt.src[ctxt.ptr]))){
            let start = ctxt.ptr;
            let end = start;
            for(end < max && !(is_alnum(ctxt.src[end]) ||
                is_whitespace(ctxt.src[end]))){
                end += 1;
            };
            // string literal
            if(ctxt.src[start] == '\"'){
                start += 1;
                ctxt.ptr = start;
                let escape = false;
                let closed = false;
                for(ctxt.ptr < max && !closed){
                    switch(ctxt.src[ctxt.ptr]){
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
                        ctxt.ptr += 1;
                        move_cln(&ctxt);
                        break;
                    case =>
                        if(escape){
                            return error(ctxt, "invalid escape sequence \"\\{}\"",
                                ctxt.src[ctxt.ptr]: rune);
                        };
                    };
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                };
                if(!closed) return error(ctxt, "unclosed string found here");
                assert(!escape);
                append(tokens, new_tk(ctxt,
                    u8tostr(ctxt.src[start..(ctxt.ptr - 1)])))!;
                continue;
            // character literal
            } else if(ctxt.src[start] == '\''){
                let val: u64 = 0;
                switch(ctxt.src[start]){
                case '\\' =>
                    if(start < max){
                        switch(ctxt.src[start + 1]){
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
                            return error(ctxt, "invalid escape sequence");
                        };
                    } else {
                        return error(ctxt, "invalid escape sequence");
                    };
                case =>
                    val = ctxt.src[start];
                };
                if(start >= max || ctxt.src[start + 1] != '\''){
                    return error(ctxt, "unclosed character literal found here");
                };
                append(tokens, new_tk(ctxt, (false, val): number))!;
                continue;
            };
            for(start < end) switch(ctxt.src[start]){
            case ';' =>
                append(tokens, new_tk(ctxt, symbol::EOL))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case ',' =>
                append(tokens, new_tk(ctxt, symbol::COMMA))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '(' =>
                append(tokens, new_tk(ctxt, symbol::LFT_PAR))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case ')' =>
                append(tokens, new_tk(ctxt, symbol::RGT_PAR))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '{' =>
                append(tokens, new_tk(ctxt, symbol::LFT_CURLY))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '}' =>
                append(tokens, new_tk(ctxt, symbol::RGT_CURLY))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '[' =>
                append(tokens, new_tk(ctxt, symbol::LFT_SQUARE))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case ']' =>
                append(tokens, new_tk(ctxt, symbol::RGT_SQUARE))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '#' =>
                append(tokens, new_tk(ctxt, operator::LENGTH))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '@' =>
                append(tokens, new_tk(ctxt, operator::RAW))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '.' =>
                if(start < ctxt.ptr - 1 && ctxt.src[start + 1] == '.'){
                    append(tokens, new_tk(ctxt, operator::RANGE))!;
                    ctxt.ptr += 2;
                    move_cln(&ctxt, 2);
                    start += 2;
                } else {
                    append(tokens, new_tk(ctxt, symbol::DOT))!;
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                    start += 1;
                };
            case '=' =>
                if(start < ctxt.ptr - 1 && ctxt.src[start + 1] == '='){
                    append(tokens, new_tk(ctxt, operator::EQL))!;
                    ctxt.ptr += 2;
                    move_cln(&ctxt, 2);
                    start += 2;
                } else {
                    append(tokens, new_tk(ctxt, operator::ASG))!;
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                    start += 1;
                };
            case '<' =>
                if(start < ctxt.ptr - 1){
                    if(ctxt.src[start + 1] == '='){
                        append(tokens, new_tk(ctxt, operator::LEQ))!;
                        ctxt.ptr += 2;
                        move_cln(&ctxt, 2);
                        start += 2;
                    } else if(ctxt.src[start + 1] == '>'){
                        append(tokens, new_tk(ctxt, operator::SHL))!;
                        ctxt.ptr += 2;
                        move_cln(&ctxt, 2);
                        start += 2;
                    } else {
                        append(tokens, new_tk(ctxt, operator::LST))!;
                        ctxt.ptr += 1;
                        move_cln(&ctxt);
                        start += 1;
                    };
                } else {
                    append(tokens, new_tk(ctxt, operator::LST))!;
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                    start += 1;
                };
            case '>' =>
                if(start < ctxt.ptr - 1){
                    if(ctxt.src[start + 1] == '='){
                        append(tokens, new_tk(ctxt, operator::GEQ))!;
                        ctxt.ptr += 2;
                        move_cln(&ctxt, 2);
                        start += 1;
                    } else if(ctxt.src[start + 1] == '>'){
                        append(tokens, new_tk(ctxt, operator::SHR))!;
                        ctxt.ptr += 2;
                        move_cln(&ctxt, 2);
                        start += 2;
                    } else {
                        append(tokens, new_tk(ctxt, operator::GTT))!;
                        ctxt.ptr += 1;
                        move_cln(&ctxt);
                        start += 1;
                    };
                } else {
                    append(tokens, new_tk(ctxt, operator::GTT))!;
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                    start += 1;
                };
            case '|' =>
                if(start < ctxt.ptr - 1 && ctxt.src[start + 1] == '|'){
                    append(tokens, new_tk(ctxt, operator::LOR))!;
                    ctxt.ptr += 2;
                    move_cln(&ctxt, 2);
                    start += 2;
                } else {
                    append(tokens, new_tk(ctxt, operator::BOR))!;
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                    start += 1;
                };
            case '&' =>
                if(start < ctxt.ptr - 1 && ctxt.src[start + 1] == '&'){
                    append(tokens, new_tk(ctxt, operator::LAND))!;
                    ctxt.ptr += 2;
                    move_cln(&ctxt, 2);
                    start += 2;
                } else {
                    append(tokens, new_tk(ctxt, operator::BAND))!;
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                    start += 1;
                };
            case ':' =>
                if(start < ctxt.ptr - 1 && ctxt.src[start + 1] == ':'){
                    append(tokens, new_tk(ctxt, symbol::FIELD))!;
                    ctxt.ptr += 2;
                    move_cln(&ctxt, 2);
                    start += 2;
                } else {
                    append(tokens, new_tk(ctxt, operator::FDIV))!;
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                    start += 1;
                };
            case '!' =>
                if(start < ctxt.ptr - 1 && ctxt.src[start + 1] == '='){
                    append(tokens, new_tk(ctxt, operator::NEQ))!;
                    ctxt.ptr += 2;
                    move_cln(&ctxt, 2);
                    start += 2;
                } else {
                    append(tokens, new_tk(ctxt, operator::BANG))!;
                    ctxt.ptr += 1;
                    move_cln(&ctxt);
                    start += 1;
                };
            case '~' =>
                append(tokens, new_tk(ctxt, operator::NOT))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '+' =>
                append(tokens, new_tk(ctxt, operator::PLS))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '-' =>
                append(tokens, new_tk(ctxt, operator::MIN))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '*' =>
                append(tokens, new_tk(ctxt, operator::MUL))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '/' =>
                append(tokens, new_tk(ctxt, operator::IDIV))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '%' =>
                append(tokens, new_tk(ctxt, operator::MOD))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '?' =>
                append(tokens, new_tk(ctxt, operator::PROP))!;
                ctxt.ptr += 1;
                move_cln(&ctxt);
                start += 1;
            case '\"' =>
                ctxt.ptr = start;
                break;
            case '\'' =>
                ctxt.ptr = start;
                break;
            case =>
                return error(ctxt, "invalid symbol \"{}\"", ctxt.src[start]: rune);
            };
        // just whitespace
        } else {
            ctxt.ptr += 1;
            move_cln(&ctxt);
        };
    };
    append(tokens, new_tk(ctxt, eof))!;
    defer free(tokens);

    max = len(tokens);
    let node: nullable *ast = null;
    const head = node;
    for(let t = 0z; t < max; t += 1){
        match(tokens[t].val){
        case let idt: ident =>
            // const global definition
            const (cdef, end) = eval_c_def(ctxt, tokens, t)?;
            push_var(ctxt, cdef)?;
            t = end;
            node = push_node(node, cdef);
            if(head is null) head = node;
        case let kwd: keyword =>
            const (pub, val): (size, tkval) =
                if(kwd == keyword::PUB){
                    const v = t;
                    t += 1;
                    const k = next_tk(ctxt, tokens, t,
                        "global %bdefinition continuation%r, but got %y{}%d")?;
                    yield (v, k.val); 
                } else {
                    yield (t, kwd);
                };
            if(val is keyword){
                switch(val as keyword){
                // type definition
                case keyword::TYPE =>
                    assert(false, "TODO: type_def");
                // function definition
                case keyword::FN =>
                    const (fun, end) = eval_fun_def(ctxt, tokens, t)?;
                    t = end;
                    node = push_node(node, fun);
                    if(head is null) head = node;
                case =>
                    move_ptr(&ctxt, tokens[t]);
                    return error(ctxt, "invalid global expression");
                };
            } else {
                const (cdef, end) = eval_c_def(ctxt, tokens, t)?;
                t = end;
                cdef.path = tokens[pub..t];
                node = push_node(node, cdef);
                if(head is null) head = node;
            };
        case let sym: symbol => void;
        case => continue;
        };
    };
    // free ast
    free_nodes(head);
    return buffer;
};

// evaluates a constant definition. assumes `at` is pointing to the expression's namespace
fn eval_c_def(ctxt: context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const max = len(tokens);
    const begin = at;
    let end = at;
    const name = tokens[end].val as ident;

    end += 1;
    const tpe = next_tk(ctxt, tokens, end,
        "expected %btype notation%r, but got %y{}%d")?;

    if(!(tpe.val is primitive)){
        move_ptr(&ctxt, tpe);
        return error(ctxt,
            "expected %bvalid type notation%r, but got %y{}%d",
            strtoken(tpe.val));
    };
    end += 1;
    name.itype = tpe.val as primitive;

    const node = new_node(tokens, begin);
    node.kind = path_t::CONST_DEF;
    node.meta = var_meta {
        lin = tokens[begin].lin,
        cln = tokens[begin].cln,
        name = name,
    };
    // assignment operator
    end = pop_assert(ctxt, tokens, end, operator::ASG,
        "expected %bconstant definition assignment%r, but got %y{}%d")?;
    const (val, _end) = eval_c_exp(ctxt, tokens, end)?;
    end = _end;
    node.inner = val;
    node.path = tokens[begin..end];
    return (node, end);
};

// evaluates a constant expression
fn eval_c_exp(ctxt: context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const max = len(tokens);
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, tokens, end,
        "expected %bcontant value%r, but got %y{}%d")?;

    const node = new_node(tokens, begin);
    node.kind = path_t::CONST_EXP;
    
    if(tk.val is operator){
        const oper = tk.val as operator;
        end += 1;
        if(!is_unary(oper)){
            move_ptr(&ctxt, tk);
            return error(ctxt, "invalid use of operator");
        };
        tk = next_tk(ctxt, tokens, end,
            "expected %bcontant value%r, but got %y{}%d")?;
        end += 1;
        if(oper == operator::LENGTH && !(tk.val is str || tk.val is ident)){
            move_ptr(&ctxt, tk);
            return error(ctxt, "invalid argument for length operator");
        } else if(oper != operator::LENGTH){
            if(tk.val is ident){
                move_ptr(&ctxt, tk);
                return error(ctxt, "cannot evaluate this at compile time");
            } else if(!(tk.val is number)){
                move_ptr(&ctxt, tk);
                return error(ctxt, "invalid compile time constant value");
            };
        };
        tk = next_tk(ctxt, tokens, end,
            "expected %bcontant value%r, but got %y{}%d")?;
    };
    for(!comp_tk(tk.val, symbol::EOL) && end < max){
        end = eval_c_val(ctxt, tokens, end)?;
        tk = next_tk(ctxt, tokens, end,
            "expected %boperator%r or %bend of line%r, but got %y{}%d")?;
        if(comp_tk(tk.val, symbol::EOL)) break;

        if(!(tk.val is operator)){
            move_ptr(&ctxt, tk);
            return error(ctxt, "expected %boperator%r or %bend of line%r, but got %y{}%d",
                strtoken(tk.val));
        } else if(!is_binary(tk.val as operator)){
            move_ptr(&ctxt, tk);
            return error(ctxt, "invalid %bbinary operator%d");
        };
        end += 1;
        end = eval_c_val(ctxt, tokens, end)?;
        tk = next_tk(ctxt, tokens, end,
            "expected %bcontant value%r, but got %y{}%d")?;
    };
    node.path = tokens[begin..end];
    return (node, end);
};

// evaluates a constant value
fn eval_c_val(ctxt: context, tokens: []token, at: size) (size | COMPERR) = {
    let tk = tokens[at];
    match(tk.val){
    case number =>
        return at + 1;
    case str =>
        return at + 1;
    case let idt: ident =>
        move_ptr(&ctxt, tk);
        return error(ctxt, "cannot evaluate {} at compile time", strtoken(idt));
    case =>
        move_ptr(&ctxt, tk);
        return error(ctxt, "invalid constant value ({})", strtoken(tk.val));
    };
};

// evaluates a function definition
fn eval_fun_def(ctxt: context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const max = len(tokens);
    const begin = at;
    let end = at;
    let tk = tokens[end];

    assert(comp_tk(tk.val, keyword::FN));
    end += 1;

    // function name
    tk = next_tk(ctxt, tokens, end,
        "expected %bvalid function name%d, but got %r{}%d")?;
    if(!((tk.val) is ident)){
        move_ptr(&ctxt, tk);
        return error(ctxt, "expected %bvalid function name%r, but got %y{}%d",
            strtoken(tk.val));
    };
    const name = tk.val as ident;
    const (param, _end) = eval_param_l(ctxt, tokens, end + 1)?;
    end = _end;

    // function type
    tk = next_tk(ctxt, tokens, end,
        "expected %bvalid function type notation%r, but got %y{}%d")?;
    if(!((tk.val) is primitive)){ // TODO: agregate types (i.e. "|| is ident")
        move_ptr(&ctxt, tk);
        return error(ctxt, "expected %bvalid function type%r, but got %y{}%d",
            strtoken(tk.val));
    };
    const tpe = tk.val as primitive;
    end += 1;

    // function assignment
    end = pop_assert(ctxt, tokens, end, operator::ASG,
        "expected %bfunction body assignment%r, but got %y{}%d")?;

    tk = next_tk(ctxt, tokens, end,
        "expected %beffect tag%r or %bscope definition%r, but got %y{}%d")?;

    let efx = []: []tkval;
    if(tk.val is ident || comp_tk(tk.val, keyword::DO)){
        append(efx, tk.val)!;
        end += 1;
        tk = next_tk(ctxt, tokens, end,
            "expected %beffect tag list continuation%r or "
            "%bscope definition%r, but got %y{}%d")?;

        if(!comp_tk(tk.val, symbol::LFT_CURLY)){
            end += 1;
        };
        for(comp_tk(tk.val, operator::BAND)){
            tk = next_tk(ctxt, tokens, end,
                "expected %beffect tag list continuation%r or "
                "%bscope definition%r, but got %y{}%d")?;
            end += 1;
            if(!(tk.val is ident || comp_tk(tk.val, keyword::DO))){
                move_ptr(&ctxt, tk);
                return error(ctxt,
                    "expected %beffect tag list continuation%r or "
                    "%bscope definition%r, but got %y{}%d",
                    strtoken(tk.val));
            };
            append(efx, tk.val)!;
            tk = next_tk(ctxt, tokens, end,
                "expected %beffect tag list continuation%r or "
                "%bscope definition%r, but got %y{}%d")?;
            if(!comp_tk(tk.val, symbol::LFT_CURLY)){
                end += 1;
            };
        };
    };
    const (body, _end) = eval_scope(ctxt, tokens, end)?;
    end = _end;
    end = pop_assert(ctxt, tokens, end, symbol::RGT_CURLY,
        "expected %bend of scope%r, but got %y{}%d")?;
    end = pop_assert(ctxt, tokens, end, symbol::EOL,
        "expected %bend of line%r, but got %y{}%d")?;

    const node = new_node(tokens, begin);
    node.kind = path_t::FUN_DEF;
    node.meta = fn_meta {
        lin = tokens[begin].lin,
        cln = tokens[begin].cln,
        name = name,
        params = param,
        fn_type = tpe,
        effects = efx,
    };
    node.inner = body;
    node.path = tokens[begin..end];
    return (node, end);
};

// evaluates a param list
fn eval_param_l(ctxt: context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const begin = pop_assert(ctxt, tokens, at, symbol::LFT_PAR,
        "expected %bvalid parameter list%r, but got %y{}%d")?;
    let end = begin;
    let tk = tokens[end];
    let meta = param_meta { ... };
    for(!comp_tk(tk.val, symbol::RGT_PAR)){
        tk = next_tk(ctxt, tokens, end + 1,
            "expected %bvalid parameter name%r or %bend of list%r, but got %y{}%d")?;
        if(!(tk.val is ident)){
            move_ptr(&ctxt, tk);
            return error(ctxt, "expected %bvalid parameter name%r "
                "or %bend of list%r, but got %y{}%d",
                strtoken(tk.val));
        };
        end += 1;
        append(meta.lin, tk.lin)!;
        append(meta.cln, tk.cln)!;
        append(meta.name, tk.val as ident)!;

        tk = next_tk(ctxt, tokens, end + 1,
            "expected %bvalid parameter type%r, but got %y{}%d")?;
        if(!(tk.val is primitive)){ // TODO: composite types
            move_ptr(&ctxt, tk);
            return error(ctxt, "expected %bvalid parameter type%r, but got %y{}%d",
                strtoken(tk.val));
        };
        end += 1;
        append(meta.tpe, tk.val as primitive)!;

        tk = next_tk(ctxt, tokens, end,
            "expected %bparameter list continuation%r or %bend of list%r, but got %y{}%d")?;
    };
    end += 1;
    const node = new_node(tokens, begin);
    node.kind = path_t::PARAM_LIST;
    node.path = tokens[begin..end];
    node.meta = meta;
    return (node, end);
};

// evaluates a scope
fn eval_scope(ctxt: context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = pop_assert(ctxt, tokens, at, symbol::LFT_CURLY,
        "expected %bvalid scope definition%r, but got %y{}%d")?;

    const node = new_node(tokens, begin);
    node.kind = path_t::SCOPE;
    node.inner = null;
    const meta = expr_meta {
        rets = false,
        tpe = primitive::ANY,
    };
    let body: nullable *ast = null;

    const upper_scp = ctxt.scp;
    const local_scp = scope {
        vars = [],
        upper = upper_scp,
    };
    defer if(len(local_scp.vars) > 0) free(local_scp.vars);
    ctxt.scp = &local_scp;

    let tk = next_tk(ctxt, tokens, end,
        "expected %bvalid expression%r, but got %y{}%d")?;
    for(!comp_tk(tk.val, symbol::RGT_CURLY)){
        match(tk.val){
        case let oper: operator =>
            if(oper == operator::MAP){
                const (exp, _end) = eval_expression(ctxt, tokens, end + 1)?;
                end = _end;
                body = push_node(body, exp);
                if(node.inner is null) node.inner = body;
                match(exp.meta){
                case let e_meta: expr_meta =>
                    if(!e_meta.rets){
                        move_ptr(&ctxt, tk);
                        return error(ctxt, "root expression %greturns a value%r, "
                            "but the inner one %gdoes not%d");
                    };
                case var_meta =>
                    push_var(ctxt, exp)?;
                };
                meta.rets = true;
                meta.tpe = push_type(ctxt, meta.tpe, (exp.meta as expr_meta).tpe, tk)?;
            } else {
                return error(ctxt, "expected %bvalid expression%r, but got %y{}%d",
                    strtoken(oper));
            };
        case =>
            const (exp, _end) = eval_expression(ctxt, tokens, end)?;
            end = _end;
            body = push_node(body, exp);
            if(node.inner is null) node.inner = body;
            match(exp.meta){
            // parsed expression is being returned
            case let e_meta: expr_meta =>
                move_ptr(&ctxt, tk);
                return error(ctxt, "inner expression %greturns a value%r, "
                    "but the root %gdoes not%d");
            case var_meta =>
                push_var(ctxt, exp)?;
            };
        };
        end = pop_assert(ctxt, tokens, end, symbol::EOL,
            "expected %bend of line%r, but got %y{}%d")?;
        tk = next_tk(ctxt, tokens, end,
            "expected %bvalid expression%r, but got %y{}%d")?;
    };
    node.meta = meta;
    node.path = tokens[begin..end];

    ctxt.scp = upper_scp;
    return (node, end);
};

fn eval_expression(ctxt: context, tokens: []token, at: size, hint: primitive = primitive::ANY)
    ((*ast, size) | COMPERR) = {
    let tk = tokens[at];
    match(tk.val){
    case let kwd: keyword =>
        switch(kwd){
        case keyword::LET =>
            const (exp, end) = eval_decl(ctxt, tokens, at)?;
            tk = next_tk(ctxt, tokens, end, "expected %btype casting%r or "
                "%bend of line%r, but got %y{}%d")?;
            if(tk.val is primitive){
                const meta = &(exp.meta as var_meta);
                meta.name.itype = push_type(ctxt,
                    meta.name.itype, tk.val as primitive, tk)?;
                return (exp, end + 1);
            } else {
                return (exp, end);
            };
        case =>
            move_ptr(&ctxt, tk);
            return error(ctxt, "TODO: statements");
        };
    case =>
        return eval_abbs_exp(ctxt, tokens, at, hint)?;
    };
};

// evaluates a namespace declaration
fn eval_decl(ctxt: context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    assert(comp_tk(tokens[at].val, keyword::LET));

    let tk = next_tk(ctxt, tokens, end + 1, "expected %bdeclaration's namespace%r, "
        "but got %y{}%d")?;
    end += 1;
    if(!(tk.val is ident)){
        move_ptr(&ctxt, tk);
        return error(ctxt, "expected %bdeclarations's namespace%r, but got %y{}%d",
            strtoken(tk.val));
    };
    const name = tk.val as ident;

    tk = next_tk(ctxt, tokens, end + 1, "expected %btype notation%r or "
        "%bvalue assignment%r, but got %y{}%d")?;
    end += 1;

    const node = new_node(tokens, begin);
    node.kind = path_t::DECL;
    match(tk.val){
    case let prim: primitive =>
        end = pop_assert(ctxt, tokens, end + 1, operator::ASG,
            "exprected %bvalue assignment%r, but got %y{}%d")?;
        const eq = end;
        const (exp, _end) = eval_expression(ctxt, tokens, end, prim)?;
        end = _end;
        node.inner = exp;

        if(exp.meta is expr_meta){
            const meta = exp.meta as expr_meta;
            if(meta.rets){
                assert(comp_tk(tokens[eq + 1].val, operator::MAP));
                move_ptr(&ctxt, tokens[eq + 1]);
                return error(ctxt, "cannot return a value from the right side of an assigntment");
            };
            name.itype = push_type(ctxt, prim, meta.tpe, tokens[eq])?;
        };
    case let ctpe: ident =>
        assert(false, "TODO: composite types");
    case let oper: operator =>
        if(oper != operator::ASG){
            move_ptr(&ctxt, tk);
            return error(ctxt, "expected %value bassignment%r, but got %y{}%d");
        };
        const eq = end;
        const (exp, _end) = eval_expression(ctxt, tokens, end + 1)?;
        end = _end;
        node.inner = exp;

        if(exp.meta is expr_meta){
            const meta = exp.meta as expr_meta;
            if(meta.rets){
                assert(comp_tk(tokens[eq + 1].val, operator::MAP));
                move_ptr(&ctxt, tokens[eq + 1]);
                return error(ctxt, "cannot return a value from the right side of an assigntment");
            };
            name.itype = push_type(ctxt, primitive::ANY, meta.tpe, tokens[eq])?;
        };
    };
    node.meta = var_meta {
        lin = tokens[begin].lin,
        cln = tokens[begin].cln,
        name = name,
    };
    return (node, end);
};

// evaluates arithmetic, boolean, binary and string expressions
fn eval_abbs_exp(ctxt: context, tokens: []token, at: size, hint: primitive = primitive::ANY)
    ((*ast, size) | COMPERR) = {
    const max = len(tokens);
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, tokens, end,
        "expected %bexpression member%r, but got %y{}%d")?;

    const node = new_node(tokens, begin);
    node.kind = path_t::EXPR;
    node.inner = null;
    let exp: nullable *ast = null;
    let tpe = hint;

    if(tk.val is operator){
        const oper = tk.val as operator;
        if(!is_unary(oper)){
            move_ptr(&ctxt, tk);
            return error(ctxt, "invalid use of operator");
        };
        end += 1;
        tk = next_tk(ctxt, tokens, end,
            "expected %bexpression member%r, but got %y{}%d")?;
    };
    for(!comp_tk(tk.val, symbol::EOL) && end < max){
        const (mem, _end) = eval_member(ctxt, tokens, end, tpe)?;
        end = _end;
        exp = push_node(exp, mem);
        if(node.inner is null) node.inner = exp;

        const meta = (exp as *ast).meta as expr_meta;
        tpe = push_type(ctxt, tpe, meta.tpe, tk)?;

        tk = next_tk(ctxt, tokens, end,
            "expected %boperator%r or %bend of line%r, but got %y{}%d")?;
        if(comp_tk(tk.val, symbol::EOL)) break;

        if(!(tk.val is operator)){
            move_ptr(&ctxt, tk);
            return error(ctxt, "expected %boperator%r or %bend of line%r, but got %y{}%d",
                strtoken(tk.val));
        } else if(!is_binary(tk.val as operator)){
            move_ptr(&ctxt, tk);
            return error(ctxt, "invalid %bbinary operator%d");
        };
        end += 1;
        const (mem2, _end) = eval_member(ctxt, tokens, end, tpe)?;
        end = _end;
        exp = push_node(exp, mem2);

        tk = next_tk(ctxt, tokens, end,
            "expected %bexpression member%r, but got %y{}%d")?;
        if(comp_tk(tk.val, symbol::RGT_PAR)) break;
    };
    node.path = tokens[begin..end];
    node.meta = expr_meta {
        rets = false,
        tpe = tpe,
    };
    return (node, end);
};

// evaluates an expression member
fn eval_member(ctxt: context, tokens: []token, at: size, hint: primitive = primitive::ANY)
    ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, tokens, end,
        "expected %bvalid member%r, but got %y{}%d")?;
    let tpe = hint;
    match(tk.val){
    case let sym: symbol =>
        if(sym == symbol::LFT_PAR){
            const (exp, _end) = eval_expression(ctxt, tokens, end + 1)?;
            end = pop_assert(ctxt, tokens, _end, symbol::RGT_PAR,
                "expected %bclosing parenthesis%r, but got %y{}%d")?;
            tk = next_tk(ctxt, tokens, end,
                "expected %btype casting%r or %bexpression continuation%r, "
                "but got %y{}%d")?;
            if(tk.val is primitive){ // TODO: composite types
                const meta = &(exp.meta as expr_meta);
                meta.tpe = push_type(ctxt, meta.tpe, tk.val as primitive, tk)?;
                return (exp, end + 1);
            } else {
                return (exp, end);
            };
        } else {
            move_ptr(&ctxt, tk);
            return error(ctxt, "expected %bvalid member%r, but got %y{}%d",
                strtoken(tk.val));
        };
    case let num: number =>
        end += 1;
        tk = next_tk(ctxt, tokens, end, "expected %btype casting%r or "
            "%bexpression continuation%r, but got %y{}%d")?;
        if(tk.val is primitive){ // TODO: composite types
            const new = tk.val as primitive;
            if(is_castable(primitive::NUMBER, new)){
                tpe = push_type(ctxt, tpe, new, tk)?;
                end += 1;
            } else {
                move_ptr(&ctxt, tk);
                return error(ctxt, "invalid cast of %g{}%r to %g{}%d",
                    strtoken(primitive::NUMBER), strtoken(new));
            };
        } else {
            tpe = push_type(ctxt, tpe, primitive::NUMBER, tk)?;
        };
    case let idt: ident =>
        // TODO: funcalls, module access, field access
        match(get_var(ctxt.scp as *scope, idt)){
        case let var: *ast =>
            const meta = var.meta as var_meta;
            tpe = meta.name.itype;
            end += 1;
        case =>
            move_ptr(&ctxt, tk);
            return error(ctxt, "the variable %y{}%r is undefined at this point",
                idt.name);
        };
        tk = next_tk(ctxt, tokens, end, "expected %btype casting%r or "
            "%bexpression continuation%r, but got %y{}%d")?;
        if(tk.val is primitive){ // TODO: composite types
            const new = tk.val as primitive;
            if(is_castable(tpe, new)){
                tpe = push_type(ctxt, tpe, new, tk)?;
                end += 1;
            } else {
                move_ptr(&ctxt, tk);
                return error(ctxt, "invalid cast of %g{}%r to %g{}%d",
                    strtoken(primitive::NUMBER), strtoken(new));
            };
        };
    case let txt: str =>
        tpe = push_type(ctxt, tpe, primitive::STR, tk)?;
        end += 1;
        // TODO: casting to composite types
    case =>
        move_ptr(&ctxt, tk);
        return error(ctxt, "invalid %bexpression member%r found here%d");
    };
    const node = new_node(tokens, begin);
    node.kind = path_t::EXPR;
    node.meta = expr_meta {
        rets = false,
        tpe = tpe,
    };
    node.path = tokens[begin..end];
    return (node, end);
};

fn push_type(ctxt: context, current: primitive, new: primitive, pos: token) (primitive | COMPERR) = {
    if(untyped(new) && untyped(current)){
        move_ptr(&ctxt, pos);
        return error(ctxt, "the given expression is untyped and cannot be assigned");
    };
    if(is_subtype(new, current)){
        if(current == primitive::ANY || current == primitive::NUMBER ||
            current == primitive::RATIO) return new;
        return current;
    } else {
        move_ptr(&ctxt, pos);
        return error(ctxt, "%Rtype mismatch;%r source is %y{}%r, but dest is %y{}%d",
            strtoken(new), strtoken(current));
    };
};

fn untyped(tpe: primitive) bool = {
    return tpe == primitive::ANY || tpe == primitive::NUMBER || tpe == primitive::RATIO;
};

fn is_castable(this: primitive, that: primitive) bool = {
    return is_subtype(this, that) || is_subtype(that, this);
};

fn is_subtype(this: primitive, that: primitive) bool = {
    return true;
};
