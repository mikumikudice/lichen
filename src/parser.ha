use bufio;
use fmt;
use fs;
use io;
use memio;
use os;
use strconv;
use strings;

// checks if character is numeric
fn is_numeric(char: u8) bool = {
    return '0' <= char && char <= '9';
};

// checks if character is alphabetic
fn is_alpha(char: u8) bool = {
    const nocase = char | 32;
    return 'a' <= nocase && nocase <= 'z';
};

// checks if character is whitespace
fn is_whitespace(char: u8) bool = {
    return char == '\n' || char == '\t' || char == ' ';
};

fn is_binary_op(oper: operator) bool = {
    return oper == operator::EQL || oper == operator::NEQ ||
        oper == operator::LEQ || oper == operator::GEQ ||
        oper == operator::LST || oper == operator::GTT ||
        oper == operator::SHL || oper == operator::SHR ||
        oper == operator::LOR || oper == operator::LAND ||
        oper == operator::BOR || oper == operator::BAND ||
        oper == operator::PLS || oper == operator::MIN ||
        oper == operator::MUL || oper == operator::DIV ||
        oper == operator::MOD;
};

fn is_unary_op(oper: operator) bool = {
    return oper == operator::PLS || oper == operator::MIN ||
        oper == operator::NOT || oper == operator::BANG ||
        oper ==operator::LENGTH;
};

// moves the context source pointer by a given amount
fn inc_ptr(ctxt: *context, amount: size = 1) void = {
    const max = len(ctxt.src);
    for(let i = 0z; i < amount && ctxt.ptr < max; i += 1){
        if(ctxt.src[ctxt.ptr] == '\n'){
            ctxt.begin = ctxt.ptr + 1;
        };
        ctxt.ptr += 1;
    };
};

// forcefully moves the context to the position of the
// given token.
fn move_ptr(ctxt: *context, tk: token) void = {
    ctxt.ptr = tk.pos;
    ctxt.begin = tk.begin;
};

// returns a new token with given `val` as
// value at the current context position
fn new_tk(ctxt: context, val: tk_val) token = {
    return token {
        pos = ctxt.ptr,
        begin = ctxt.begin,
        val = val,
    };
};

// returns the given token as a human-readable string
fn strtoken(tok: tk_val) str = {
    match(tok){
    case let nm: namespace =>
        return fmt::asprintf("identifier \"{}\"", nm.name)!;
    case let num: size =>
        return fmt::asprintf("numeric literal {}", num)!;
    case let flt: f64 =>
        return fmt::asprintf("floating point literal {}", flt)!;
    case let txt: str =>
        return fmt::asprintf("string literal \"{}\"", txt)!;
    case let kwd: keyword =>
        return fmt::asprintf("{} keyword", kwd_value[kwd])!;
    case let prim: primitive =>
        switch(prim){
        case primitive::NUMBER, primitive::RATIO, primitive::ANY =>
            return strings::dup(prim_value[prim])!;
        case =>
            return fmt::asprintf("primitive type {}", prim_value[prim])!;
        };
    case let oper: operator =>
        return fmt::asprintf("{} operator", oper_value[oper: int])!;
    case let sym: symbol =>
        return strings::dup(sym_value[sym])!;
    case eof =>
        return strings::dup("end of file")!;
    };
};

// returns the given lichen type as a human-readable string
fn strtype(tpe: lichen_t) str = {
    match(tpe.base){
    case let prim: primitive =>
        if(tpe.fail){
            const temp = strtoken(prim);
            defer free(temp);
            return fmt::asprintf("partial {}", temp)!;
        } else {
            return strtoken(prim);
        };
    case let rec: *record =>
        if(tpe.fail){
            return fmt::asprintf("partial record type {}", rec.name.name)!;
        } else {
            return fmt::asprintf("record type {}", rec.name.name)!;
        };
    case let arr: *array =>
        if(arr.length is void){
            const base = strtype(arr.base);
            defer free(base);
            if(tpe.fail){
                return fmt::asprintf("partial type []{}", base)!;
            } else {
                return fmt::asprintf("type []{}", base)!;
            };
        } else {
            const base = strtype(arr.base);
            defer free(base);
            if(tpe.fail){
                return fmt::asprintf("partial type [{}]{}",
                    arr.length as size, base)!;
            } else {
                return fmt::asprintf("type [{}]{}",
                    arr.length as size, base)!;
            };
        };
    };
};

// compare two tokens
fn comp_tk(lft: tk_val, rgt: tk_val) bool = {
    match(lft){
    case let idt: namespace =>
        if(rgt is namespace){
            const r = rgt as namespace;
            return r.name == idt.name;
        } else {
            return false;
        };
    case let num: size =>
        if(rgt is size){
            const r = rgt as size;
            return num == r;
        } else {
            return false;
        };
    case let flt: f64 =>
        if(rgt is f64){
            const r = rgt as f64;
            return flt == r;
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

// checks if a given namespace is already in use
fn check_shadowing(
    ctxt: *context,
    pos: token,
    nm: namespace,
) (void | ERROR) = {
    match(get_def(ctxt, nm, ctxt.scp)){
    case let fun_def: *fun_meta =>
        move_ptr(fun_def.owner, fun_def.owner.tokens[fun_def.pos]);
        const dup_pos = gen_pos(fun_def.owner);
        defer free(dup_pos);
        move_ptr(ctxt, pos);
        return error(ctxt,
            "a function defined at %b{}%r is already using the namespace %y{}",
            dup_pos, nm.name);
    case let decl: *decl_meta =>
        move_ptr(decl.var.owner, decl.var.owner.tokens[decl.var.pos]);
        const dup_pos = gen_pos(decl.var.owner);
        defer free(dup_pos);
        move_ptr(ctxt, pos);
        return error(ctxt,
            "a variable defined at %b{}%r is already using the namespace %y{}",
            dup_pos, nm.name);
    case let tpe: *type_meta =>
        move_ptr(tpe.owner, tpe.owner.tokens[tpe.pos]);
        const dup_pos = gen_pos(tpe.owner);
        defer free(dup_pos);
        move_ptr(ctxt, pos);
        return error(ctxt,
            "a type declaration defined at %b{}%r is already using the namespace %y{}",
            dup_pos, nm.name);
    case let module: *module_meta =>
        move_ptr(module.owner, module.owner.tokens[module.pos]);
        const dup_pos = gen_pos(module.owner);
        defer free(dup_pos);
        move_ptr(ctxt, pos);
        return error(ctxt,
            "a module defined at %b{}%r is already using the namespace %y{}",
            dup_pos, nm.name);
    case void => void;
    };
};

// pushes given function definition to the given context. returns an
// error if the function namespace is already in use.
fn push_def(
    ctxt: *context,
    pos: token,
    name: namespace,
    meta: (*fun_meta | *decl_meta | *type_meta | *module_meta),
) (void | ERROR) = {
    // assert for dups
    check_shadowing(ctxt, pos, name)?;
    if(meta is *decl_meta){
        append(ctxt.scp.defs, meta)!;
    } else {
        append(ctxt.global.defs, meta)!;
    };
};

// fetches the corresponding function definition of `name` from the
// current scope. returns void if no match is found.
fn get_def(
    ctxt: *context,
    nm: namespace,
    scp: *scope,
) ((*fun_meta | *decl_meta | *type_meta| *module_meta) | void) = {
    for(let meta ..& scp.defs){
        match(meta){
        case let fun_def: *fun_meta =>
            if(fun_def.fun.name == nm.name){
                return fun_def;
            };
        case let decl: *decl_meta =>
            if(decl.var.nm.name == nm.name){
                return decl;
            };
        case let tpe: *type_meta =>
            if(tpe.name.name == nm.name){
                return tpe;
            };
        case let module: *module_meta =>
            if(module.name == nm.name){
                return module;
            };
        };
    };
    if(scp.upper is *scope){
        return get_def(ctxt, nm, scp.upper as *scope);
    };
};

fn push_lit(ctxt: *context, new: str) size = {
    const max = len(ctxt.literals);
    for(let lit = 0z; lit < max; lit += 1){
        if(ctxt.literals[lit] == new) return lit;
    };
    append(ctxt.literals, new)!;
    return max;
};

// converts a primitive type to a lichen type wrapper
fn quick_t(tpe: primitive, fail: bool = false) lichen_t = {
    return lichen_t {
        fail = fail,
        base = tpe,
    };
};

fn dummy_nm(val: str) namespace = namespace {
    name = val,
    ffi = void,
    tpe = quick_t(primitive::ANY),
    ...
};

// compiles down a given source file to a compilation unit context
// returns an error in case of a compilation error
fn compile(filename: str,
    stdlib_path: str,
    has_main: bool,
    mod_emit: bool,
    literals: (*[]str | void) = void,
) (*context | ERROR) = {
    // open source file
    const file = match(os::open(filename)){
    case let f: io::file => yield f;
    case let e: fs::error =>
        return fail("failed to load %g\"{}\"%r source file: %y{}",
            filename, fs::strerror(e));
    };
    defer io::close(file)!;

    const src: []u8 = [];
    // load every line until EOF
    for(true) match(bufio::read_line(file)!){
    case io::EOF =>
        break;
    case let l: []u8 =>
        append(src, l...)!;
        append(src, '\n')!;
        free(l);
    };
    const glob = alloc(scope {
        defs = [], upper = null
    })!;
    // initialize context
    const ctxt = context {
        file = filename,
        path = stdlib_path,
        main = has_main,
        branching = false,
        src = src,
        ptr = 0,
        last = 0,
        begin = 0,
        tokens = [],
        literals =
            if(literals is *[]str){
                yield literals as *[]str;
            } else {
                yield alloc([]: []str)!;
            },
        host_fun = null,
        global = glob,
        scp = glob,
    };
    // tokenize
    let max = len(src);
    for(ctxt.ptr < max){
        ctxt.last = ctxt.ptr;
        // skip whitespace
        for(ctxt.ptr < max && is_whitespace(ctxt.src[ctxt.ptr])) inc_ptr(&ctxt);
        if(ctxt.ptr >= max) break;

        // remove comments
        if(ctxt.src[ctxt.ptr] == '/' && ctxt.ptr < max - 1){
            if(strings::fromutf8(
                ctxt.src[ctxt.ptr .. ctxt.ptr + 2])! == "//"){
                for(ctxt.ptr < max && ctxt.src[ctxt.ptr] != '\n')
                    inc_ptr(&ctxt);
            };
        };
        let end = ctxt.ptr;
        // find the last non-whitespace character
        for(end < max && !is_whitespace(ctxt.src[end])) end += 1;
        if(end >= max) break;
        if(end == ctxt.ptr){
            inc_ptr(&ctxt);
            continue;
        };
        let path = ctxt.src[ctxt.ptr .. end];
        // numeric literal
        if(is_numeric(path[0])){
            end = ctxt.ptr;
            // reprocess the end of the path
            for(end < max && is_alpha(ctxt.src[end]) ||
                is_numeric(ctxt.src[end]) || ctxt.src[end] == '_') end += 1;
            assert(end != ctxt.ptr);
            path = ctxt.src[ctxt.ptr .. end];

            // decimal point literal
            if(ctxt.src[end] == '.' && end + 1 < max &&
                is_numeric(ctxt.src[end + 1])){
                end += 1;
                for(end < max && is_numeric(ctxt.src[end]) ||
                    ctxt.src[end] == '_') end += 1;
                path = ctxt.src[ctxt.ptr .. end];

                const num = strings::replace(
                    strings::fromutf8(path)!, "_", "")!;
                defer free(num);

                match(strconv::stof64(num)){
                case let f: f64 =>
                    append(ctxt.tokens, new_tk(ctxt, f: f64))!;
                    inc_ptr(&ctxt, end - ctxt.ptr);
                    continue;
                case strconv::overflow =>
                    return error(&ctxt, "64-bit floating point literal overflow");
                case =>
                    return error(&ctxt, "invalid floating point literal");
                };
            };
            const num = strings::replace(
                strings::fromutf8(path)!, "_", "")!;
            defer free(num);

            // hex literal
            if(strings::hasprefix(num, "0x")){
                match(strconv::stou64(strings::sub(num, 2),
                strconv::base::HEX)){
                case let n: u64 =>
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(&ctxt, "64-bit hexadecimal literal overflow");
                case =>
                    return error(&ctxt, "invalid hexadecimal literal");
                };
            // oct literal
            } else if(strings::hasprefix(num, "0o")){
                match(strconv::stou64(strings::sub(num, 2),
                strconv::base::OCT)){
                case let n: u64 =>
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(&ctxt, "64-bit octal literal overflow");
                case =>
                    return error(&ctxt, "invalid hexadecimal literal");
                };
            // bin literal
            } else if(strings::hasprefix(num, "0b")){
                match(strconv::stou64(strings::sub(num, 2),
                strconv::base::BIN)){
                case let n: u64 =>
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(&ctxt, "64-bit binary literal overflow");
                case =>
                    return error(&ctxt, "invalid binary literal");
                };
            // dec literal
            } else {
                match(strconv::stou64(num)){
                case let n: u64 =>
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(&ctxt,
                        "64-bit literal overflow");
                case =>
                    return error(&ctxt, "invalid numeric literal %y\"{}\"", num);
                };
            };
            inc_ptr(&ctxt, end - ctxt.ptr);
        // namespace or keyword
        } else if(is_alpha(path[0]) || path[0] == '_'){
            end = ctxt.ptr;
            // reprocess the end of the path
            for(end < max && is_alpha(ctxt.src[end]) ||
                is_numeric(ctxt.src[end]) || ctxt.src[end] == '_') end += 1;
            assert(end != ctxt.ptr);
            path = ctxt.src[ctxt.ptr..end];

            const word = strings::fromutf8(path)!;
            let matched = false;
            // check if it's a keyword
            for(let kwd = 0z; kwd < len(kwd_value); kwd += 1){
                if(kwd_value[kwd] == word){
                    append(ctxt.tokens, new_tk(ctxt, kwd: keyword))!;
                    matched = true;
                };
            };
            if(matched){
                inc_ptr(&ctxt, end - ctxt.ptr);
                continue;
            };
            // check if it's a primitive type
            for(let prim = 0z; prim < len(prim_value); prim += 1){
                if(prim_value[prim] == word){
                    append(ctxt.tokens, new_tk(ctxt, prim: primitive))!;
                    matched = true;
                };
            };
            if(matched){
                inc_ptr(&ctxt, end - ctxt.ptr);
                continue;
            };
            // it's a namespace
            for(end < max && ctxt.src[end] == '\'') end += 1;
            append(ctxt.tokens, new_tk(ctxt, namespace {
                pub = false,
                mut = false,
                glob = false,
                param = false,
                name = strings::fromutf8(ctxt.src[ctxt.ptr..end])!,
                ffi = void,
                tpe = quick_t(primitive::ANY),
            }))!;
            inc_ptr(&ctxt, end - ctxt.ptr);
        // string literal
        } else if(path[0] == '\"'){
            const start = ctxt.ptr + 1;
            let finish = start;
            let escape = false;
            let closed = false;
            for(finish < max && !closed; finish += 1){
                switch(ctxt.src[finish]){
                case '\\' =>
                    escape = !escape;
                case '\"' =>
                    if(!escape){
                        closed = true;
                    } else {
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
                case '\n' => break;
                case =>
                    if(escape){
                        return error(&ctxt, "invalid escape sequence %y\"\\{}\"",
                            ctxt.src[finish]: rune);
                    };
                };
            };
            if(!closed) return error(&ctxt, "unclosed string found here");
            finish -= 1;
            assert(!escape);
            append(ctxt.tokens, new_tk(ctxt,
                strings::fromutf8(ctxt.src[start..finish])!))!;
            // advance to the end of the string
            inc_ptr(&ctxt, finish - ctxt.ptr + 1);
        // character literal
        } else if(path[0] == '\''){
            const start = ctxt.ptr + 1;
            let finish = start;
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
                        return error(&ctxt, "invalid escape sequence");
                    };
                    finish += 2;
                } else {
                    return error(&ctxt, "invalid escape sequence");
                };
            case =>
                val = ctxt.src[start];
                finish += 1;
            };
            if(ctxt.src[finish] != '\''){
                inc_ptr(&ctxt, finish - ctxt.ptr);
                return error(&ctxt, "unclosed character literal");
            };
            finish += 1;
            append(ctxt.tokens, new_tk(ctxt, val: size))!;
            inc_ptr(&ctxt, finish - ctxt.ptr);
            continue;
        // operator or symbol
        } else {
            let start = ctxt.ptr;
            end = start;
            // reprocess the end of the path
            for(end < max && !is_whitespace(ctxt.src[end]) &&
                !is_numeric(ctxt.src[end]) && !is_alpha(ctxt.src[end])) end += 1;
            assert(end != start);
            for(start < end) switch(ctxt.src[start]){
            case ';' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::EOL))!;
                start += 1;
                inc_ptr(&ctxt);
            case ',' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::COMMA))!;
                start += 1;
                inc_ptr(&ctxt);
            case '(' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::LFT_PAR))!;
                start += 1;
                inc_ptr(&ctxt);
            case ')' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::RGT_PAR))!;
                start += 1;
                inc_ptr(&ctxt);
            case '{' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::LFT_CURLY))!;
                start += 1;
                inc_ptr(&ctxt);
            case '}' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::RGT_CURLY))!;
                start += 1;
                inc_ptr(&ctxt);
            case '[' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::LFT_SQUARE))!;
                start += 1;
                inc_ptr(&ctxt);
            case ']' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::RGT_SQUARE))!;
                start += 1;
                inc_ptr(&ctxt);
            case '#' =>
                append(ctxt.tokens, new_tk(ctxt, operator::LENGTH))!;
                start += 1;
                inc_ptr(&ctxt);
            case '@' =>
                append(ctxt.tokens, new_tk(ctxt, operator::AT))!;
                start += 1;
                inc_ptr(&ctxt);
            case '.' =>
                if(start < end - 2 && ctxt.src[start + 1] == '.' &&
                    ctxt.src[start + 2] == '.'){
                    append(ctxt.tokens, new_tk(ctxt, operator::SPREAD))!;
                    start += 3;
                    inc_ptr(&ctxt, 3);
                } else if(start < end - 1 && ctxt.src[start + 1] == '.'){
                    append(ctxt.tokens, new_tk(ctxt, operator::RANGE))!;
                    start += 2;
                    inc_ptr(&ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, symbol::DOT))!;
                    start += 1;
                    inc_ptr(&ctxt);
                };
            case '=' =>
                if(start < end - 1 && ctxt.src[start + 1] == '='){
                    append(ctxt.tokens, new_tk(ctxt, operator::EQL))!;
                    start += 2;
                    inc_ptr(&ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::ASG))!;
                    start += 1;
                    inc_ptr(&ctxt);
                };
            case '<' =>
                if(start < end - 1){
                    if(ctxt.src[start + 1] == '='){
                        append(ctxt.tokens, new_tk(ctxt, operator::LEQ))!;
                        start += 2;
                        inc_ptr(&ctxt, 2);
                        continue;
                    } else if(ctxt.src[start + 1] == '<'){
                        append(ctxt.tokens, new_tk(ctxt, operator::SHL))!;
                        start += 2;
                        inc_ptr(&ctxt, 2);
                        continue;
                    };
                };
                append(ctxt.tokens, new_tk(ctxt, operator::LST))!;
                start += 1;
                inc_ptr(&ctxt);
            case '>' =>
                if(start < end - 1){
                    if(ctxt.src[start + 1] == '='){
                        append(ctxt.tokens, new_tk(ctxt, operator::GEQ))!;
                        start += 2;
                        inc_ptr(&ctxt, 2);
                        continue;
                    } else if(ctxt.src[start + 1] == '>'){
                        append(ctxt.tokens, new_tk(ctxt, operator::SHR))!;
                        start += 2;
                        inc_ptr(&ctxt, 2);
                        continue;
                    };
                };
                append(ctxt.tokens, new_tk(ctxt, operator::GTT))!;
                start += 1;
                inc_ptr(&ctxt);
            case '|' =>
                if(start < end - 1 && ctxt.src[start + 1] == '|'){
                    append(ctxt.tokens, new_tk(ctxt, operator::LOR))!;
                    start += 2;
                    inc_ptr(&ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::BOR))!;
                    start += 1;
                    inc_ptr(&ctxt);
                };
            case '&' =>
                if(start < end - 1 && ctxt.src[start + 1] == '&'){
                    append(ctxt.tokens, new_tk(ctxt, operator::LAND))!;
                    start += 2;
                    inc_ptr(&ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::BAND))!;
                    start += 1;
                    inc_ptr(&ctxt);
                };
            case ':' =>
                if(start < end - 1 && ctxt.src[start + 1] == ':'){
                    append(ctxt.tokens, new_tk(ctxt, symbol::FIELD))!;
                    start += 2;
                    inc_ptr(&ctxt, 2);
                } else {
                    return error(&ctxt,
                        "unrecognized symbol found here");
                };
            case '!' =>
                if(start < end - 1 && ctxt.src[start + 1] == '='){
                    append(ctxt.tokens, new_tk(ctxt, operator::NEQ))!;
                    start += 2;
                    inc_ptr(&ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::BANG))!;
                    start += 1;
                    inc_ptr(&ctxt);
                };
            case '~' =>
                append(ctxt.tokens, new_tk(ctxt, operator::NOT))!;
                start += 1;
                inc_ptr(&ctxt);
            case '+' =>
                append(ctxt.tokens, new_tk(ctxt, operator::PLS))!;
                start += 1;
                inc_ptr(&ctxt);
            case '-' =>
                append(ctxt.tokens, new_tk(ctxt, operator::MIN))!;
                start += 1;
                inc_ptr(&ctxt);
            case '*' =>
                append(ctxt.tokens, new_tk(ctxt, operator::MUL))!;
                start += 1;
                inc_ptr(&ctxt);
            case '/' =>
                // skip comment
                if(start < end - 1 && ctxt.src[start + 1] == '/'){
                    for(start < max && ctxt.src[start] != '\n'){
                        start += 1;
                        inc_ptr(&ctxt);
                    };
                    // drop tokenization if nothing is left
                    if(start >= end) break;
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::DIV))!;
                    inc_ptr(&ctxt);
                    start += 1;
                };
            case '%' =>
                append(ctxt.tokens, new_tk(ctxt, operator::MOD))!;
                start += 1;
                inc_ptr(&ctxt);
            case '?' =>
                append(ctxt.tokens, new_tk(ctxt, operator::BUBBLE))!;
                start += 1;
                inc_ptr(&ctxt);
            // break at string or character literal
            case '\"' =>
                ctxt.ptr = start;
                break;
            case '\'' =>
                ctxt.ptr = start;
                break;
            case =>
                return error(&ctxt, "invalid symbol \"{}\"", ctxt.src[start]: rune);
            };
        };
    };
    // report on empty file
    if(len(ctxt.tokens) == 0){
        return fail("the file \"{}\" is empty%d\n\n%gtry adding:\n\n%d{}\n",
            filename, fn_demo);
    };
    append(ctxt.tokens, new_tk(ctxt, eof))!;
    // parse
    eval_program(&ctxt)?;
    // check if it's defined
    const main = get_def(&ctxt, dummy_nm("main"), ctxt.global);
    // no main on a main file
    if(main is void && has_main){
        move_ptr(&ctxt, ctxt.tokens[len(ctxt.tokens) - 1]);
        const hint = fmt::asprintf("\n%gtry adding:\n\n%d{}", fn_demo)!;
        defer free(hint);
        return error_hint(&ctxt, hint, "missing entry point");
    // main function on a module
    } else if(main is *fun_meta && !has_main){
        const fun = main as *fun_meta;
        move_ptr(&ctxt, ctxt.tokens[fun.pos]);
        return error(&ctxt,
            "modules shall not %yimplement a main function");
    // main is not defined as a function
    } else if(has_main && main is *decl_meta || main is *module_meta){
        const pos =
            match(main){
            case let decl: *decl_meta => yield decl.var.pos;
            case let module: *module_meta => yield module.pos;
            case => fmt::fatal("unreachable");
            };
        move_ptr(&ctxt, ctxt.tokens[pos]);
        return error(&ctxt,
            "namespace main was not defined as a function");
    // everything is ok
    } else if(main is *fun_meta){
        const fun_def = main as *fun_meta;
        if(!comp_type(fun_def.fun.tpe, primitive::VOID)){
            const arg = strtoken(primitive::VOID);
            defer free(arg);
            return error(&ctxt, "main function shall be of %y{}", arg);
        };
        if(len(fun_def.params) != 0){
            return error(&ctxt,
                "main function shall %y receive no parameters");
        };
        // mark to be emitted
        fun_def.used = true;
        if(fun_def.fun.ffi is void && fun_def.used){
            // assign current scope host
            ctxt.host_fun = fun_def;
            // evaluate function scope
            let (body, end) = eval_scope(&ctxt, fun_def.begins,
                fun_def.params)?;
            ctxt.host_fun = null;
            // pop end of line
            end = pop_assert(&ctxt, end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            // assign parsed function body
            fun_def.body = body;
        };
    };
    // parse only needed functions

    // from main file
    for(let meta .. ctxt.global.defs){
        match(meta){
        case let fun_def: *fun_meta =>
            if(fun_def.fun.ffi is void &&
                (fun_def.used || mod_emit) &&
                fun_def.fun.name != "main"){
                // assign current scope host
                ctxt.host_fun = fun_def;
                // evaluate function scope
                let (body, end) = eval_scope(&ctxt, fun_def.begins,
                    fun_def.params)?;
                ctxt.host_fun = null;
                // pop end of line
                end = pop_assert(&ctxt, end, symbol::EOL,
                    "expected %bend of line%r, but got %y{}")?;
                // assign parsed function body
                fun_def.body = body;
            };
        case => void;
        };
    };
    // from modules
    for(let m .. ctxt.global.defs){
        if(m is *module_meta){
            const module = m as *module_meta;
            if(module.parsed) continue;
            module.parsed = true;
            for(let meta .. module.ctxt.global.defs){
                match(meta){
                case let fun_def: *fun_meta =>
                    if(fun_def.fun.ffi is void && fun_def.used){
                        // assign current scope host
                        module.ctxt.host_fun = fun_def;
                        // evaluate function scope
                        let (body, end) = eval_scope(module.ctxt, fun_def.begins,
                            fun_def.params)?;
                        module.ctxt.host_fun = null;
                        // pop end of line
                        end = pop_assert(module.ctxt, end, symbol::EOL,
                            "expected %bend of line%r, but got %y{}")?;
                        // assign parsed function body
                        fun_def.body = body;
                    };
                case => void;
                };
            };
        };
    };
    return alloc(ctxt)!;
};

// evaluates a given context as a valid program
fn eval_program(ctxt: *context) (void | ERROR) = {
    const max = len(ctxt.tokens);
    for(let t = 0z; t < max){
        const tk = ctxt.tokens[t];
        match(tk.val){
        case let kwd: keyword =>
            const (pub, next, n) =
                switch(kwd){
                case keyword::PUB =>
                    if(t + 1 == max){
                        move_ptr(ctxt, tk);
                        return error(ctxt,
                            "expected %bglobal declaration%r, but got %yend of file");
                    };
                    yield (true, ctxt.tokens[t + 1], t + 1);
                case =>
                    yield (false, tk, t);
                };
                match(next.val){
                case let kwd: keyword =>
                    switch(kwd){
                    case keyword::TYPE =>
                        const (tpe_def, end) = eval_type_def(ctxt, n)?;
                        tpe_def.name.pub = pub;
                        t = end;
                    case keyword::FN =>
                        const (fun_def, end) = eval_fun_def(ctxt, n)?;
                        fun_def.fun.pub = pub;
                        t = end;
                    case =>
                        move_ptr(ctxt, next);
                        const arg = strtoken(next.val);
                        defer free(arg);
                        return error(ctxt, "invalid usage of {}", arg);
                    };
                case let nm: namespace =>
                    if(comp_tk(next.val, keyword::MOD)){
                            const (mod, end) = eval_module(ctxt, n)?;
                            mod.pub = pub;
                            t = end;
                        } else {
                            const (decl, end) = eval_const_def(ctxt, n)?;
                            decl.var.nm.pub = pub;
                            t = end;
                        };
                case =>
                    move_ptr(ctxt, next);
                    const arg = strtoken(next.val);
                    defer free(arg);
                    return error(ctxt,
                        "expected %bglobal declaration%r, but got %y{}",
                        arg);
                };
        case let nm: namespace =>
            if(t + 1 < max && comp_tk(ctxt.tokens[t + 1].val, keyword::MOD)){
                const (mod, end) = eval_module(ctxt, t)?;
                t = end;
            } else {
                const (decl, end) = eval_const_def(ctxt, t)?;
                t = end;
            };
        case eof => break;
        case =>
            move_ptr(ctxt, tk);
            return error(ctxt, "unexpected token");
        };
        if(!comp_tk(ctxt.tokens[t].val, symbol::EOL)){
            move_ptr(ctxt, ctxt.tokens[t]);
            const arg = strtoken(ctxt.tokens[t].val);
            defer free(arg);
            return error(ctxt, "expected %bend of line%r, but got %y{}",
                arg);
        };
        t += 1;
    };
};

// evaluates a constant definition. assumes `at` is pointing to the expression's namespace
fn eval_const_def(ctxt: *context, at: size) ((*decl_meta, size) | ERROR) = {
    let end = at;
    const name = ctxt.tokens[at].val as namespace;
    name.pub = false;
    name.glob = true;
    
    let tk = next_tk(ctxt, end + 1,
        "expected %btype notation%r, but got %y{}")?;
    // get type
    const (tpe, _end) = eval_type(ctxt, end + 1)?;
    end = _end;
    name.tpe = tpe;

    // assignment operator
    end = pop_assert(ctxt, end, operator::ASG,
        "expected %bconstant's value assignment%r, but got %y{}")?;

    tk = next_tk(ctxt, end, 
        "expected %bconstant or FFI declaration%r, but got %y{}")?;
    let out_val: (void | *const_meta) = void;
    if(comp_tk(tk.val, keyword::USE)){
        end += 1;
        tk = next_tk(ctxt, end, 
            "expected %bFFI symbol%r, but got %y{}")?;
        if(!(tk.val is str)){
            move_ptr(ctxt, tk);
            return error_hint(ctxt,
                "\n%gFFI syntax:%d\n\n\tmodule mod = use \"path/to/module\";",
                "expected %bFFI symbol%r, but got %y{}");
        };
        end += 1;
        name.ffi = tk.val as str;
    } else {
        const (val, _end) = eval_constant(ctxt, end, tpe)?;
        out_val = val;
        end = _end;
    };
    const out = alloc(decl_meta {
        var = alloc(var_meta {
            nm = name,
            owner = ctxt,
            pos = at,
        })!,
        val = out_val,
    })!;
    push_def(ctxt, ctxt.tokens[at], name, out)?;
    return (out, end);
};

// evaluates a constant value
fn eval_constant(
    ctxt: *context,
    at: size,
    hint: lichen_t,
) ((*const_meta, size) | ERROR) = {
    let end = at;
    // fetch constant value
    let val = next_tk(ctxt, end,
        "expected %bconstant value%r, but got %y{}")?;
    end += 1;
    const meta = const_meta {
        pre = void,
        val = val.val,
    };
    // unary operator
    if(val.val is operator){
        assert_unary(ctxt, end, val.val as operator, hint)?;
        meta.pre = val.val as operator;
        val = next_tk(ctxt, end,
            "expected %bconstant value%r, but got %y{}")?;
        end += 1;
        meta.val = val.val;
    };
    // assert if it's valid
    validate_const(ctxt, val, hint)?;
    return (alloc(meta)!, end);
};

// validates a constant value by its expected type hint
fn validate_const(
    ctxt: *context,
    val: token, 
    hint: lichen_t,
) (void | ERROR) = {
    match(val.val){
    case size =>
        assert_hint(ctxt, val, hint, primitive::NUMBER)?;
    case str =>
        assert_hint(ctxt, val, hint, primitive::STR)?;
    case f64 =>
        assert_hint(ctxt, val, hint, primitive::RATIO)?;
    case let kwd: keyword =>
        switch(kwd){
        case keyword::TRUE, keyword::FALSE =>
            assert_hint(ctxt, val, hint, primitive::BOOL)?;
        case keyword::FAIL, keyword::NOMEM =>
            let as_err = hint;
            as_err.fail = true;
            assert_hint(ctxt, val, hint, as_err)?;
        case =>
            move_ptr(ctxt, val);
            const arg = strtoken(kwd);
            defer free(arg);
            return error(ctxt,
                "expected %bconstant value%r, but got %y{}", arg);
        };
    case =>
        move_ptr(ctxt, val);
        const arg = strtoken(val.val);
        defer free(arg);
        return error(ctxt,
            "expected %bconstant value%r, but got %y{}", arg);
    };
};

fn eval_module(ctxt: *context, at: size) ((*module_meta, size) | ERROR) = {
    const bind = ctxt.tokens[at].val as namespace;
    assert(comp_tk(ctxt.tokens[at + 1].val, keyword::MOD));

    // pop assignment
    let end = pop_assert(ctxt, at + 2, operator::ASG,
        "expected %bmodule assignment%r, but got %y{}")?;
    // pop `use` keyword
    end = pop_assert(ctxt, end, keyword::USE,
        "expected %bmodule loading (%buse keyword%r), but got %y{}")?;
    // get module path
    let tk = next_tk(ctxt, end,
        "expected %bmodule path%r, but got %y{}")?;
    end += 1;
    if(!(tk.val is str)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt,
            "expected %bmodule path%r, but got %y{}", arg);
    };
    let path = strings::concat(ctxt.path, tk.val as str)!;
    if(!os::exists(path)){
        free(path);
        path = strings::concat(strings::rcut(ctxt.file, "/").0, "/", tk.val as str)!;
    };
    if(path == ctxt.file){
        move_ptr(ctxt, ctxt.tokens[at]);
        return error(ctxt, "cannot %yrecursively import main file");
    };
    let mod_ctxt: nullable *context = null;
    for(let mod .. ctxt.global.defs){
        if(mod is *module_meta){
            const meta = mod as *module_meta;
            if(meta.ctxt.file == path){
                mod_ctxt = meta.ctxt;
            };
        };
    };
    if(mod_ctxt == null){
        mod_ctxt = compile(path, ctxt.path, false, false, ctxt.literals)?;
    };
    const module = alloc(module_meta {
        name = bind.name,
        owner = ctxt,
        pos = at,
        pub = false,
        freed = false,
        parsed = false,
        emitted = false,
        ctxt = mod_ctxt as *context,
    })!;
    push_def(ctxt, ctxt.tokens[at], bind, module)?;
    return (module, end);
};

fn eval_type_def(ctxt: *context, at: size) ((*type_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, keyword::TYPE));
    let end = at + 1;
    let tk = next_tk(ctxt, end, "expected %btype binding%r, but got %y{}")?;
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt,
            "expected %btype binding%r, but got %y{}", arg);
    };
    const name = tk.val as namespace;
    end = pop_assert(ctxt, end + 1, operator::ASG, 
        "expected %btype value assignment%r, but got %y{}")?;

    const (tpe, _end) = eval_type(ctxt, end, name)?;
    end = _end;
    const out = alloc(type_meta {
        owner = ctxt,
        pos = at,
        name = name,
        self = tpe,
    })!;
    push_def(ctxt, ctxt.tokens[at], name, out)?;
    return (out, _end);
};

// evaluates a function definition
fn eval_fun_def(ctxt: *context, at: size) ((*fun_meta, size) | ERROR) = {
    let end = at + 1;
    let tk = next_tk(ctxt, end,
        "expected %bfunction name%r, but got %y{}")?;
    // fetch function name
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt,
            "expected %bfunction name%r, but got %y{}", arg);
    };
    const name = tk.val as namespace;
    const pos = end;
    end += 1;

    end = pop_assert(ctxt, end, symbol::LFT_PAR,
        "expected %bfunction parameter list declaration%r, but got %y{}")?;

    // eval param list
    tk = next_tk(ctxt, end,
        "expected %bparameter%r or %bend of parameter list%r, but got %y{}")?;

    let variadic = false;
    let all_muts = true;
    let any_muts = false;
    let first_mut = 0z;
    const params: []*decl_meta = [];
    // evaluate parameter declarations
    for(!comp_tk(tk.val, symbol::RGT_PAR)){
        if(variadic){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "no additional parameters may follow a %yvariadic parameter");
        };
        tk = next_tk(ctxt, end,
            "expected %bparameter%r or %bend of parameter list%r, but got %y{}")?;
        const mut =
            if(comp_tk(tk.val, keyword::MUT)){
                end += 1;
                yield true;
            } else {
                yield false;
            };
        const (param, _end) = eval_declaration(ctxt, end)?;
        param.var.nm.mut = mut;
        param.var.nm.param = true;
        // assert for FFI aggregated parameters' mutation
        if(is_aggregated(param.var.nm.tpe)){
            if(mut){
                first_mut = end;
                any_muts = true;
            } else {
                all_muts = false;
            };
        } else if(mut){
            move_ptr(ctxt, ctxt.tokens[end - 1]);
            return error_hint(ctxt,
                "\n%bonly %yarrays, records and strings%b can mutate its value",
                "mutability is %bnot applicable%r to %ynon-aggregated types");
        };
        // append to parameter list
        append(params, param)!;
        end = _end;

        tk = next_tk(ctxt, end,
            "expected %bnext parameter%r or %bend of parameter list%r, but got %y{}")?;

        if(comp_tk(tk.val, operator::SPREAD)){
            variadic = true;
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bend of parameter list%r, but got %y{}")?;
        };
        if(comp_tk(tk.val, symbol::RGT_PAR)) break;
        end += 1;
        if(!comp_tk(tk.val, symbol::COMMA)){
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %bcomma%r, bug got %y{}", arg);
        };
        tk = next_tk(ctxt, end,
            "expected %bparameter%r or %bend of parameter list%r, but got %y{}")?;
    };
    end = pop_assert(ctxt, end, symbol::RGT_PAR,
        "expected %bend of parameter list%r, but got %y{}")?;
    // eval function return type
    const (tpe, _end) = eval_type(ctxt, end)?;
    end = _end;
    name.pub = false;
    name.glob = true;
    name.tpe = tpe;

    end = pop_assert(ctxt, end, operator::ASG,
        "expected %bfunction assignment%r, but got %y{}")?;

    // eval effect tags
    const (efx, _end) = eval_efx(ctxt, end)?;
    end = _end;

    // assert mutability
    if(len(efx) == 0 && any_muts){
        move_ptr(ctxt, ctxt.tokens[first_mut]);
        return error_hint(ctxt,
            "\na mutable reference may mutate the data it carries, generating side-effects",
            "this function %btakes mutable references%r of values, but it %ydeclares no effects");
    };
    const begins = end;
    tk = next_tk(ctxt, end,
        "expected %bFFI symbol%r or %bscope declaration%r, but got %y{}")?;
    // FFI function
    if(comp_tk(tk.val, keyword::USE)){
        end += 1;
        const symb = next_tk(ctxt, end,
            "expected %bFFI symbol%r, but got %y{}")?;
        end += 1;
        if(!(symb.val is str)){
            move_ptr(ctxt, symb);
            const arg = strtoken(symb.val);
            defer free(arg);
            return error(ctxt,
                "expected %bFFI symbol%r, but got %y{}", arg);
        };
        name.ffi = symb.val as str;
        if(!all_muts){
            move_ptr(ctxt, tk);
            return error_hint(ctxt,
                "\ncompiler cannot guarantee this foreign function won't mutate aggregated parameters",
                "this function is declared as foreign, but not all of its aggregated-typed parameters are declared as mutable");
        };
    } else if(comp_tk(tk.val, symbol::LFT_CURLY)){
        end = skip_scope(ctxt, end)?;
    } else {
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt,
            "expected %bFFI symbol%r or %bscope declaration%r, but got %y{}",
            arg);
    };
    // create a new AST node
    const out = alloc(fun_meta {
        fun = name,
        owner = ctxt,
        pos = pos,
        begins = begins,
        origin = ctxt.file,
        body = null,
        params = params,
        effect = efx,
        used = false,
        variadic = variadic,
    })!;
    // reserve namespace
    push_def(ctxt, ctxt.tokens[pos], name, out)?;
    return (out, end);
};

// evaluates a list of effect tags
fn eval_efx(ctxt: *context, at: size) (([]str, size) | ERROR) = {
    let end = at;
    let efx = []: []str;
    let tk = next_tk(ctxt, end,
        "expected %beffect tag%r or %bscope definition%r, but got %y{}")?;
    // single do effect
    if(comp_tk(tk.val, keyword::DO)){
        append(efx, "do")!;
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %beffect tag list continuation%r, %bscope "
            "definition%r or %bFFI symbol%r, but got %y{}")?;
        if(comp_tk(tk.val, operator::BAND)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "the %bdo%r effect shall not followed by additional effects");
        };
    // list of effects
    } else if(tk.val is namespace){
        end += 1;
        // loop until start of declaration
        for(!comp_tk(tk.val, symbol::LFT_CURLY) &&
            !comp_tk(tk.val, keyword::USE)){
            // append to list
            append(efx, (tk.val as namespace).name)!;
            // address following code
            tk = next_tk(ctxt, end,
                "expected %beffect tag list continuation%r, %bscope "
                "definition%r or %bFFI symbol%r, but got %y{}")?;
            // break at end of list
            if(comp_tk(tk.val, symbol::LFT_CURLY) ||
                comp_tk(tk.val, keyword::USE)) break;
            end += 1;
            // validate following tags
            if(!comp_tk(tk.val, operator::BAND)){
                move_ptr(ctxt, tk);
                const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %beffect tag concatenation%r, bug got %y{}", arg);
            };
            tk = next_tk(ctxt, end,
                "expected %beffect tag list continuation%r, %bscope "
                "definition%r or %bFFI symbol%r, but got %y{}")?;
            end += 1;
            if(!(tk.val is namespace)){
                move_ptr(ctxt, tk);
                const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %beffect tag list continuation%r or "
                    "%bscope definition%r, but got %y{}", arg);
            };
        };
    };
    return (efx, end);
};

// skips a scope definition
fn skip_scope(ctxt: *context, at: size) (size | ERROR) = {
    const max = len(ctxt.tokens);
    let end = pop_assert(ctxt, at, symbol::LFT_CURLY,
        "expected %bvalid scope definition%r, but got %y{}")?;
    for(end < max; end += 1){
        if(comp_tk(ctxt.tokens[end].val, symbol::LFT_CURLY)){
            end = skip_scope(ctxt, end)? - 1;
        } else if(comp_tk(ctxt.tokens[end].val, symbol::RGT_CURLY)){
            return end + 1;
        };
    };
    move_ptr(ctxt, ctxt.tokens[end - 1]);
    return error(ctxt, "expected %bend of scope%r, but got %yend of file");
};

// evaluates a scope and its statements
fn eval_scope(
    ctxt: *context,
    at: size,
    params: []*decl_meta = [],
) ((*scope_meta, size) | ERROR) = {
    const upper = ctxt.scp;
    // instantiate scope definitions
    ctxt.scp = alloc(scope {
        defs = [], upper = upper,
    })!;
    for(let param .. params){
        const dup = alloc(*param)!;
        dup.var = alloc(*param.var)!;
        append(ctxt.scp.defs, dup)!;
    };
    let end = at + 1;
    let rets = false;
    let tpe = quick_t(primitive::ANY);
    let last_tpe = tpe;
    const stt_list: []path_meta = [];
    const host = ctxt.host_fun as *fun_meta;
    // fetch first token
    let tk = next_tk(ctxt, end,
        "expected %bstatement%r, but got %y{}")?;
    // iterate until end of scope
    for(!comp_tk(tk.val, symbol::RGT_CURLY)){
        if(rets){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "no additional code shall fallow %yvoid expressions%r or %yreturn statements");
        };
        const (stt, _end) = eval_statement(ctxt, end)?;
        append(stt_list, stt)!;
        match(stt){
        case let ret: *return_meta =>
            last_tpe = ret.val.tpe;
            tpe = ret.val.tpe;
            rets = true;
        case let decl: *decl_meta =>
            last_tpe = decl.var.nm.tpe;
        case let exp: *expr_meta =>
            last_tpe = exp.tpe;
        case let asg: *assign_meta =>
            last_tpe = quick_t(primitive::UNIT);
        case let branch: *branch_meta =>
            if(branch.rets){
                last_tpe = host.fun.tpe;
                tpe = host.fun.tpe;
                rets = true;
            } else {
                last_tpe = quick_t(primitive::UNIT);
            };
        };
        // assign terminant expressions
        if(comp_type(last_tpe, quick_t(primitive::VOID)) ||
            comp_type(last_tpe, quick_t(primitive::VOID, true))){
            rets = true;
        };
        // address for ignored errors
        if(last_tpe.fail && !(stt is *decl_meta) && !rets &&
            !comp_type(last_tpe, quick_t(primitive::VOID, true))){
            move_ptr(ctxt, tk);
            return error_hint(ctxt,
                "\n%gtry bubbling the error with %d?%g or asserting it with %d!",
                "cannot %yignore error value%r in here");
        };
        // address for unassigned pure functions
        if(stt is *expr_meta){
            const root = extract_root(stt as *expr_meta);
            if(root is *funcall_meta){
                const call = root as *funcall_meta;
                if(len(call.fun.effect) == 0 &&
                    !comp_type(call.fun.fun.tpe, primitive::VOID) &&
                    !comp_type(call.fun.fun.tpe, quick_t(primitive::VOID, true))){
                    move_ptr(ctxt, tk);
                    if(call.fun.origin == ctxt.file){
                        return error_hint(ctxt,
                            "\n%btry assigning it to a variable or comparing it in a if block",
                            "the function %b{}()%r is %ypure%r, but its value is %ynever used",
                            call.fun.fun.name);
                    } else {
                        const mod = strings::rcut(
                            strings::rcut(call.fun.origin, "/").1, ".").0;
                        return error_hint(ctxt,
                            "\n%btry assigning it to a variable or comparing it in a if block",
                            "the function %b{}::{}()%r is %ypure%r, but its value is %ynever used",
                            mod, call.fun.fun.name);
                    };
                };
            };
        };
        end = _end;
        tk = next_tk(ctxt, end,
            "expected %bstatement%r, but got %y{}")?;
    };
    if(untyped(tpe)) tpe = quick_t(primitive::UNIT);
    if(rets){
        tpe = host.fun.tpe;
    } else if(comp_type(host.fun.tpe, primitive::VOID)){
        tpe = host.fun.tpe;
    };
    assert_hint(ctxt, ctxt.tokens[at], tpe, host.fun.tpe)?;
    const meta = alloc(scope_meta {
        pos = at,
        stt = stt_list,
        tpe = tpe,
        self = ctxt.scp,
        rets = rets,
    })!;
    // restore to upper scope
    ctxt.scp = upper;
    return (meta, end + 1);
};

// evaluates a statement
fn eval_statement(ctxt: *context, at: size) ((path_meta, size) | ERROR) = {
    let end = at;
    // fetch first token
    let tk = next_tk(ctxt, end, "expected %bstatement%r, but got %y{}")?;
    match(tk.val){
    case let kwd: keyword =>
        switch(kwd){
        case keyword::TEST => todo("test block");
        case keyword::LET =>
            end += 1;
            const (decl, _end) = eval_var_def(ctxt, end)?;
            push_def(ctxt, ctxt.tokens[end], decl.var.nm, decl)?;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (decl, end);
        case keyword::IF =>
            const (branch, _end) = eval_ifelse(ctxt, end)?;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (branch, end);
        case keyword::SWITCH => todo("switch block");
        case keyword::RETURN =>
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %breturn value%r or %bend of line%r, but got %y{}")?;
            const host = ctxt.host_fun as *fun_meta;
            if(comp_tk(tk.val, symbol::EOL)){
                const val = expr_meta {
                    pos = end,
                    tpe = quick_t(primitive::UNIT),
                    pre = void,
                    val = void,
                    prop = void,
                };
                end += 1;
                const out = return_meta {
                    val = alloc(val)!,
                    tpe = host.fun.tpe,
                    pos = at,
                };
                return (alloc(out)!, end);
            };
            const (val, _end) = eval_expression(ctxt, end, host.fun.tpe)?;
            const out = alloc(return_meta {
                val = val,
                tpe = host.fun.tpe,
                pos = at,
            })!;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (out, end);
        case =>
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt, "unexpected %y{}", arg);
        };
    case let var: namespace =>
        const begin = end;
        tk = next_tk(ctxt, end + 1,
            "expected %bassignment%r or %bexpression continuation%r, but got %y{}")?;
        if(comp_tk(tk.val, operator::ASG)){
            end += 2;
            match(get_def(ctxt, var, ctxt.scp)){
            case let var_def: *decl_meta =>
                // assert for parameters
                if(var_def.var.nm.param){
                    move_ptr(ctxt, ctxt.tokens[begin]);
                    if(var_def.var.nm.mut){
                        return error_hint(ctxt,
                            "\n%bparameter mutability refers to its data, not the namespace",
                            "cannot %breassign%r to %ymutable%r parameter %b{}",
                            var_def.var.nm.name);
                    } else {
                        return error(ctxt,
                            "cannot %breassign%r to %yimmutable%y parameter %b{}",
                            var_def.var.nm.name);
                    };
                };
                // assert for mutability
                if(!var_def.var.nm.mut){
                    move_ptr(ctxt, tk);
                    return error(ctxt,
                        "cannot %breassign to immutable%r variable %y{}",
                        var.name);
                };
                const (val, _end) = eval_expression(ctxt, end, var_def.var.nm.tpe)?;
                const root = extract_root(val);
                // assert for immutability dropping
                if(root is *var_meta){
                    const pass = root as *var_meta;
                    if(is_aggregated(var_def.var.nm.tpe) &&
                        !size_known(var_def.var.nm.tpe) &&
                        !pass.nm.mut){
                        move_ptr(ctxt, tk);
                        const hint = fmt::asprintf(
                            "\n%baggregated types such as strings and arrays cannot be copied to the stack.\n"
                            "try using:\n\n\t%d{} = new ! {} @ arena",
                            var_def.var.nm.name, pass.nm.name)!;
                        defer free(hint);
                        return error_hint(ctxt,
                        hint,
                        "cannot copy this %bimmutable aggregated value%r to %ymutable variable");
                    };
                };
                end = pop_assert(ctxt, _end, symbol::EOL,
                    "expected %bend of line%r, but got %y{}")?;
                const asg = assign_meta {
                    pos = begin,
                    var = var_def.var,
                    val = val,
                };
                return (alloc(asg)!, end);
            case let fun_def: *fun_meta =>
                move_ptr(ctxt, ctxt.tokens[begin]);
                return error(ctxt,
                    "cannot reassign to function %b{}%r", fun_def.fun.name);
            case let module: *module_meta =>
                move_ptr(ctxt, ctxt.tokens[begin]);
                return error(ctxt,
                    "cannot reassign to module binding %b{}%r", module.name);
            case void =>
                move_ptr(ctxt, ctxt.tokens[begin]);
                return error(ctxt,
                    "namespace %b{}%r undefined at this point", var.name);
            };
        } else {
            const (exp, _end) = eval_expression(ctxt, end, quick_t(primitive::ANY))?;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (exp: path_meta, end);
        };
    case =>
        const (exp, _end) = eval_expression(ctxt, end, quick_t(primitive::ANY))?;
        end = pop_assert(ctxt, _end, symbol::EOL,
            "expected %bend of line%r, but got %y{}")?;
        return (exp: path_meta, end);
    };
};

// evaluates a variable definition
// assumes `at` points to the first variable namespace
fn eval_var_def(ctxt: *context, at: size) ((*decl_meta, size) | ERROR) = {
    let end = at;
    let tk = next_tk(ctxt, end,
        "expected %bvariable namespace%r or %bmut keyword%r, but got %y{}")?;
     const mut =
        if(comp_tk(tk.val, keyword::MUT)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bvariable namespace%r, but got %y{}")?;
            yield true;
        } else {
            yield false;
        };
    // validate namespace
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt, 
            "expected %bvariable namespace%r, but got %y{}", arg);
    };
    const name = tk.val as namespace;
    const pos = end;
    end += 1;
    name.tpe = quick_t(primitive::ANY);
    match(eval_type(ctxt, end)){
    case let some: (lichen_t, size) =>
        name.tpe = some.0;
        end = some.1;
    case => void;
    };
    const eq = end;
    end = pop_assert(ctxt, end, operator::ASG,
        "expected %bdeclaration value assignment%r, but got %y{}")?;
    // eval variable assignment expression value
    const (val, _end) = eval_expression(ctxt, end, name.tpe)?;
    const root = extract_root(val);
    // assert for immutability dropping
    if(root is *var_meta){
        const pass = root as *var_meta;
        if(is_aggregated(val.tpe) && !size_known(val.tpe) && !pass.nm.mut){
            move_ptr(ctxt, ctxt.tokens[end]);
            const hint = fmt::asprintf(
                "\n%baggregated types such as strings and arrays cannot be copied to the stack."
                "\ntry using:\n\n\t%dlet mut {} = new ! {} @ arena",
                name.name, pass.nm.name)!;
            defer free(hint);
            return error_hint(ctxt,
            hint,
            "cannot copy this %bimmutable aggregated value%r to %ymutable variable");
        };
    };
    end = _end;
    name.tpe = val.tpe;
    name.mut = mut;
    // assert for typing
    if(untyped(name.tpe)){
        move_ptr(ctxt, ctxt.tokens[eq]);
        return error(ctxt, "cannot deduce %yexpression type");
    } else if(comp_type(name.tpe, quick_t(primitive::VOID, true)) ||
        comp_type(name.tpe, quick_t(primitive::VOID, true))){
        move_ptr(ctxt, ctxt.tokens[eq]);
        const arg = strtype(name.tpe);
        defer free(arg);
        return error_hint(ctxt, 
            "\n%ga (partial) primitive void type never returns",
            "cannot assign %b{}%r to variables", arg);
    };
    const out = alloc(decl_meta {
        var = alloc(var_meta {
            nm = name,
            owner = ctxt,
            pos = pos,
        })!,
        val = val,
    })!;
    return (out, end);
};

fn eval_ifelse(ctxt: *context, at: size) ((*branch_meta, size) | ERROR) = {
    let end = at;
    assert(comp_tk(ctxt.tokens[end].val, keyword::IF));
    let tk = ctxt.tokens[end];
    end += 1;

    const old_branch = ctxt.branching;
    ctxt.branching = true;

    let rets = true;
    let notret = false;
    let conds: []*expr_meta = [];
    let bodies: []((*decl_meta | void), *scope_meta) = [];
    let locals: []*decl_meta = [];
    defer free(locals);
    for(comp_tk(tk.val, keyword::IF)){
        tk = next_tk(ctxt, end,
            "expected %belse block%r or %bend of line%r, but got %y{}")!;
        let local_set = false;
        // local variable
        if(tk.val is namespace){
            const name = tk.val as namespace;
            const decl = get_def(ctxt, name, ctxt.scp);
            // namespace not defined suggests an assignment
            if(decl is void){
                const (local, _end) = eval_var_def(ctxt, end)?;
                end = pop_assert(ctxt, _end, symbol::EOL,
                    "expected %bend of line%r, but got %y{}")?;
                local_set = true;
                push_def(ctxt, tk, local.var.nm, local)?;
                append(locals, local)!;
            };
        };
        const (cond, _end) = eval_expression(ctxt, end,
            quick_t(primitive::BOOL))?;
        append(conds, cond)!;
        end = _end;
        const (body, _end) = eval_scope(ctxt, end)?;
        end = _end;
        if(local_set){
            append(bodies, (locals[len(locals) - 1], body))!;
        } else {
            append(bodies, (void, body))!;
        };
        // check if all branches return
        if(!body.rets){
            rets = false;
            notret = true;
        };
        tk = next_tk(ctxt, end,
            "expected %belse block%r or %bend of line%r, but got %y{}")!;
        if(comp_tk(tk.val, symbol::EOL)) break;
        if(comp_tk(tk.val, keyword::ELSE)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %belse block%r or %bend of line%r, but got %y{}")!;
            // skip to parse the else-if block
            if(comp_tk(tk.val, keyword::IF)){
                end += 1;
                continue;
            };
            local_set = false;
            // local variable
            if(tk.val is namespace){
                const name = tk.val as namespace;
                const decl = get_def(ctxt, name, ctxt.scp);
                // namespace not defined suggests an assignment
                if(decl is void){
                    const (local, _end) = eval_var_def(ctxt, end)?;
                    end = pop_assert(ctxt, _end, symbol::EOL,
                        "expected %bend of line%r, but got %y{}")?;
                    local_set = true;push_def(ctxt, tk, local.var.nm, local)?;
                    append(locals, local)!;
                };
            };
            const (else_body, _end) = eval_scope(ctxt, end)?;
            end = _end;
            if(local_set){
                append(bodies, (locals[len(locals) - 1], else_body))!;
            } else {
                append(bodies, (void, else_body))!;
            };
            // check if all branches return
            if(!body.rets) rets = false;
        } else {
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %belse block%r or %bend of line%r, but got %y{}", arg);
        };
    };
    move_ptr(ctxt, ctxt.tokens[at]);
    ctxt.branching = old_branch;
    const branch = branch_meta {
        pos = at,
        rets = rets && !notret && len(conds) < len(bodies),
        nested = ctxt.branching,
        conds = conds,
        bodies = bodies,
    };
    return (alloc(branch)!, end);
};

// evaluates an expression of members and operators
fn eval_expression(
    ctxt: *context,
    at: size,
    hint: lichen_t,
    ternary: bool = false,
) ((*expr_meta, size) | ERROR) = {
    let end = at;
    let members: [](hand_t | operator) = [];

    // eval first member
    const (left, _end, invalid) = eval_member(ctxt, end,
        quick_t(primitive::ANY), hint, true)?;
    if(invalid){
        if(comp_tk(ctxt.tokens[end].val, keyword::ELSE) && ternary){
            assert(false);
        };
        move_ptr(ctxt, ctxt.tokens[end]);
        const arg = strtoken(ctxt.tokens[end].val);
        defer free(arg);
        return error(ctxt,
            "expected %bexpression member%r, but got %y{}", arg);
    };
    let tk = next_tk(ctxt, _end,
        "expected %boperator%r, %bternary operator%r or %bend of line%r, but got %y{}")?;
    // ternary operator
    if(comp_tk(tk.val, keyword::IF) && _end != end){
        return eval_ternary(ctxt, _end, end,
            left as (*member_meta | *expr_meta));
    };
    match(left){
    case let exp: *expr_meta => append(members, exp)!;
    case let memb: *member_meta => append(members, memb)!;
    case void => assert(false, "unreachable");
    };
    end = _end;
    tk = next_tk(ctxt, end,
        "expected %bexpression member%r, but got %y{}")?;
    // keep iterating while there's an operator at the right of the member
    for(tk.val is operator){
        const oper = tk.val as operator;
        if(!is_binary_op(oper)){
            // halt on invalid state
            if(comp_tk(oper, operator::SPREAD)) break;
            // report error otherwise
            move_ptr(ctxt, tk);
            const arg = strtoken(oper);
            defer free(arg);
            return error(ctxt,
                "%b{}%r is an %yinvalid binary operator", arg);
        };
        append(members, oper)!;
        const (right, _end, invalid) = eval_member(ctxt, end + 1,
            quick_t(primitive::ANY), hint)?;

        // address for expresison types
        match(right){
        case let exp: *expr_meta => append(members, exp)!;
        case let memb: *member_meta => append(members, memb)!;
        case void =>
            move_ptr(ctxt, ctxt.tokens[end]);
            const arg = strtoken(ctxt.tokens[end].val);
            defer free(arg);
            return error(ctxt,
                "expected %bvalid righthand side%r, but got %y{}", arg);
        };
        tk = next_tk(ctxt, _end,
            "expected %boperator%r, %bternary operator%r or %bend of line%r, but got %y{}")?;
        // ternary operator
        if(comp_tk(tk.val, keyword::IF) && _end != end){
            const (hand, _) = reduce_members(ctxt, at, members)?;
            return eval_ternary(ctxt, _end, end, hand);
        };
        end = _end;
        // break if encountered an invalid path
        if(invalid) break;
        // fetch potential next operator
        tk = next_tk(ctxt, end,
            "expected %bexpression member%r, but got %y{}")?;
    };
    let (val, tpe) = reduce_members(ctxt, at, members)?;
    // assign a possible less-untyped type
    if(untyped(tpe) && !comp_type(hint, primitive::ANY)) tpe = hint;
    // assert for expected expression type
    assert_hint(ctxt, ctxt.tokens[at], tpe, hint)?;
    assert(!comp_type(tpe, primitive::ANY));

    const out = alloc(expr_meta {
        pos = at,
        tpe = tpe,
        pre = void,
        val = val,
        prop = void,
    })!;
    return (out, end);
};

// parses down a list of expression members to a
// hand, a member or an expression abstraction
fn reduce_members(
    ctxt: *context,
    pos: size,
    members: [](hand_t | operator),
) ((hand_t, lichen_t) | ERROR) = {
    if(len(members) > 1){
        for(let pre = 4z; pre > 0; pre -= 1){
            for(let o = 1z; o < len(members); o += 2){
                const oper = members[o] as operator;
                if(get_op_precedence(oper) == pre){
                    const h_pos = pos + o + pre - 4;

                    const lft_h = members[o - 1] as hand_t;
                    const lft_t = extract_hand_type(lft_h);

                    const rgt_h = members[o + 1] as hand_t;
                    const rgt_t = extract_hand_type(rgt_h);

                    // assert for valid operators and member types
                    if(!valid_exp(oper, lft_t, rgt_t)){
                        move_ptr(ctxt, ctxt.tokens[h_pos]);
                        const arg1 = strtype(lft_t);
                        defer free(arg1);
                        const arg2 = strtype(rgt_t);
                        defer free(arg2);
                        return error(ctxt,
                            "cannot apply %b{}%r over lefthand (%b{}%r) and righthand (%b{}%r)",
                            oper_value[oper], arg1, arg2);
                    };
                    const hand = hand_meta {
                        pos = h_pos,
                        tpe = reduce_exp_t(oper, lft_t, rgt_t),
                        lft = lft_h,
                        opr = oper,
                        rgt = rgt_h,
                    };
                    // remove consumed members
                    delete(members[(o - 1)..(o + 2)]);
                    // if it's not the final iteration 
                    if(len(members) > 0){
                        insert(members[o - 1], alloc(hand)!)!;
                    } else {
                        free(members);
                        return (alloc(hand)!, hand.tpe);
                    };
                };
            };
        };
    };
    defer free(members);
    return (members[0] as hand_t, extract_hand_type(members[0] as hand_t));
};


fn get_op_precedence(oper: operator) size = switch(oper){
    case operator::SHL, operator::SHR, operator::BOR,
        operator::BAND, operator::MUL, operator::DIV,
        operator::MOD =>
        yield 4z;
    case operator::PLS, operator::MIN =>
        yield 3z;
    case operator::EQL, operator::NEQ, operator::LEQ,
        operator::GEQ, operator::LST, operator::GTT =>
        yield 2z;
    case operator::LOR, operator::LAND =>
        yield 1z;
    case =>
        assert(false, "unreachable");
        return 0z;
    };

// evaluates an expression member
fn eval_member(
    ctxt: *context,
    at: size,
    hint: lichen_t,
    possible: lichen_t,
    first: bool = false,
) (((*member_meta | *expr_meta | void), size, bool) | ERROR) = {
    const tk = next_tk(ctxt, at,
        "expected %bexpression member%r, but got %y{}")?;
    let end = at;
    let as_err = hint;
    as_err.fail = true;
    const memb = member_meta {
        pos = at,
        tpe = as_err,
        pre = void,
        val = keyword::FAIL,
        prop = void,
    };
    match(tk.val){
    case let sym: symbol =>
        switch(sym){
        case symbol::LFT_PAR =>
            const (exp, _end) = eval_expression(ctxt, at + 1,
                quick_t(primitive::ANY))?;

            end = pop_assert(ctxt, _end, symbol::RGT_PAR,
                "expected %bclosing parenthesis%r, but got %y{}")?;
            // assert for a potential casting
            const (tpe, prop, _end) = eval_cast(ctxt, exp.tpe, end)?;
            exp.tpe = tpe;
            exp.prop = prop;
            end = _end;
            tk = next_tk(ctxt, end,
                "expected %bpropagation operator%r or %bexpression continuation%r, but gor %y{}")?;
            // assert for a potential casting
            const (tpe, prop, _end) = eval_cast(ctxt, exp.tpe, end)?;
            exp.tpe = tpe;
            exp.prop = prop;
            end = _end;
            return (exp, end, false);
        case symbol::LFT_SQUARE =>
            const (arr, _end) = eval_array_lit(ctxt, at, possible)?;
            end = _end;
            memb.tpe = arr.tpe;
            memb.val = arr;
        case =>
            return (void, at, true);
        };
    case let oper: operator =>
        if(!first && (oper == operator::PLS || oper == operator::MIN)){
            move_ptr(ctxt, tk);
            const arg = strtoken(oper);
            defer free(arg);
            return error(ctxt,
                "cannot use %b{}%r as an %yunary operator%r on the middle of an expression",
                arg);
        };
        const (res, _end, inv) = eval_member(ctxt, at + 1, hint, hint, false)?;
        match(res){
        case let m: *member_meta =>
            assert_unary(ctxt, _end, oper, m.tpe)?;
            m.pre = oper;
            if(oper == operator::LENGTH){
                m.tpe = quick_t(primitive::U64);
            };
        case let e: *expr_meta =>
            assert_unary(ctxt, _end, oper, e.tpe)?;
            e.pre = oper;
            if(oper == operator::LENGTH){
                e.tpe = quick_t(primitive::U64);
            };
        };
        return (res, _end, inv);
    case let num: size =>
        const (val, _end) = eval_constant(ctxt, at, hint)?;
        end = _end;
        memb.tpe = quick_t(primitive::NUMBER);
        memb.val = val;
    case let flt: f64 =>
        const (val, _end) = eval_constant(ctxt, at, hint)?;
        end = _end;
        memb.tpe = quick_t(primitive::RATIO);
        memb.val = val;
    case let txt: str =>
        const (val, _end) = eval_constant(ctxt, at, hint)?;
        end = _end;
        memb.tpe = quick_t(primitive::STR);
        memb.val = val;
    case let kwd: keyword =>
        switch(kwd){
        case keyword::TRUE =>
            memb.tpe = quick_t(primitive::BOOL);
            memb.val = kwd;
            end = at + 1;
        case keyword::FALSE =>
            memb.tpe = quick_t(primitive::BOOL);
            memb.val = kwd;
            end = at + 1;
        case keyword::FAIL, keyword::NOMEM =>
            if(untyped(possible)){
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "value %bfail%r not assignable to %yuntyped expression");
            };
            end = at + 1;
            memb.tpe = possible;
            memb.tpe.fail = true;
            memb.val = kwd;
        case =>
            return (void, at, true);
        };
    case let nm: namespace =>
        match(get_def(ctxt, nm, ctxt.scp)){
        case let fun_def: *fun_meta =>
            tk = next_tk(ctxt, end + 1,
                "expected %bexpression continuation%r or %bend of line%r, but got %y{}")?;
            // funcall
            if(comp_tk(tk.val, symbol::LFT_PAR)){    
                const (call, _end) = eval_funcall(ctxt, fun_def, end + 1)?;
                end = _end;
                memb.tpe = call.tpe;
                memb.val = call;
            // function pointer
            } else {
                todo("function as values");
            };
        case let decl: *decl_meta =>
            memb.tpe = decl.var.nm.tpe;
            memb.val = alloc(*decl.var)!;
            end = at + 1;
            tk = next_tk(ctxt, end,
                "expected %bexpression continuation%r or %bend of line%r, but got %y{}")?;
            if(comp_tk(tk.val, symbol::LFT_PAR)){
                move_ptr(ctxt, tk);
                return error(ctxt, "attempt to call on non-function namespace %b{}",
                    decl.var.nm.name);
            };
        case let tpe: *type_meta =>
            memb.tpe = tpe.self;
            match(tpe.self.base){
            case let rec: *record =>
                const (lit, _end) = eval_record_lit(ctxt, end, tpe.self)?;
                end = _end;
                memb.val = lit;
            case let uni: *enum_t =>
                todo("enum field access");
            case =>
                move_ptr(ctxt, tk);
                const arg = strtype(tpe.self);
                defer free(arg);
                return error(ctxt,
                    "type %b{}%r cannot be used as a %yliteral nor has any variants", arg);
            };
        case let module: *module_meta =>
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bmodule field access%r or %bexpression continuation%r, but got %y{}")?;
            if(comp_tk(tk.val, symbol::FIELD)){
                end += 1;
                tk = next_tk(ctxt, end,
                    "expected %bmodule field access%r or %bexpression continuation%r, but got %y{}")?;
                if(!(tk.val is namespace)){
                    move_ptr(ctxt, tk);
                    const arg = strtoken(tk.val);
                    defer free(arg);
                    return error(ctxt,
                        "expected %bvalid field name%r, but gor %y{}",
                        arg);
                };
                move_ptr(ctxt, tk);
                const field = tk.val as namespace;
                end += 1;
                let found = false;
                for(let mod_def .. module.ctxt.global.defs){
                    match(mod_def){
                    case let fun_def: *fun_meta =>
                        if(fun_def.fun.name != field.name){
                            continue;
                        };
                        if(!fun_def.fun.pub){
                            return error(ctxt,
                                "the function %b{}::{}()%r exists, but it's %ynot public",
                                module.name, fun_def.fun.name);
                        };
                        found = true;
                        tk = next_tk(ctxt, end,
                            "expected %bexpression continuation%r or %bend of line%r, but got %y{}")?;
                        // funcall
                        if(comp_tk(tk.val, symbol::LFT_PAR)){
                            const (call, _end) = eval_funcall(ctxt, fun_def, end)?;
                            end = _end;
                            memb.tpe = call.tpe;
                            memb.val = call;
                        // function pointer
                        } else {
                            todo("function as values");
                        };
                    case let decl: *decl_meta =>
                        if(decl.var.nm.name != field.name){
                            continue;
                        };
                        if(!decl.var.nm.pub){
                            return error(ctxt,
                                "the function %b{}::{}%r exists, but it's %ynot public",
                                module.name, decl.var.nm.name);
                        };
                        memb.tpe = decl.var.nm.tpe;
                        memb.val = alloc(*decl.var)!;
                        found = true;
                        tk = next_tk(ctxt, end,
                            "expected %bexpression continuation%r or %bend of line%r, but got %y{}")?;
                        if(comp_tk(tk.val, symbol::LFT_PAR)){
                            move_ptr(ctxt, tk);
                            return error(ctxt, "attempt to call on non-function namespace %b{}",
                                decl.var.nm.name);
                        };
                    case let module: *module_meta =>
                        todo("recursive modules");
                    };
                };
                if(!found){
                    return error(ctxt,
                        "no field named %b{}%r is defined on %b{}",
                        field.name, module.name);
                };
            } else {
                todo("first class modules");
            };
        case =>
            // fetch missing symbol possible hint
            const hint =
                if(comp_tk(ctxt.tokens[end + 1].val, symbol::FIELD)){
                    yield fmt::asprintf(
                        "\n%gtry using:\n\n"
                        "\t%d{0} mod = use \"std/{0}.lim\";\n"
                        "\n%gat global scope\n", nm.name)!;
                } else if(comp_tk(ctxt.tokens[end + 1].val, symbol::LFT_PAR)){
                    const fn_help = undef_tip(nm.name);
                    yield if(fn_help != ""){
                        yield strings::dup(fn_help)!;
                    } else {
                        yield "";
                    };
                } else {
                    yield "";
                };
            move_ptr(ctxt, tk);
            if(hint != ""){
                return error_hint(ctxt, hint,
                    "namespace %b{}%r undefined at this point", nm.name);
            } else {
                return error(ctxt,
                    "namespace %b{}%r undefined at this point", nm.name);
            };
        };
    case =>
        return (void, at, true);
    };

    // assert for a potential casting
    const (tpe, prop, _end) = eval_cast(ctxt, memb.tpe, end)?;
    memb.tpe = tpe;
    memb.prop = prop;
    end = _end;
    assert(!comp_type(memb.tpe, primitive::ANY));

    tk = next_tk(ctxt, end,
        "expected %bexpression continuation%r or %bend of line%r, but got %y{}")?;

    // assert for record field acces
    if(comp_tk(tk.val, symbol::DOT)){
        tk = next_tk(ctxt, end,
            "expected %bfield access%r or %bexpression continuation%r, but got %y{}")!;
        if(!memb.tpe.fail && memb.tpe.base is *record){
            let before: nullable *field_meta = null;
            let access: nullable *field_meta = null;
            let last_tpe = memb.tpe;
            let last_prop = memb.prop;
            for(comp_tk(tk.val, symbol::DOT)){
                end += 1;
                tk = next_tk(ctxt, end,
                    "expected valid %bfield name%r, but got %y{}")?;
                if(!(tk.val is namespace)){
                    move_ptr(ctxt, tk);
                    const arg = strtoken(tk.val);
                    defer free(arg);
                    return error(ctxt,
                        "expected valid %bfield name%r, but got %y{}", arg);
                };
                end += 1;
                memb.pos = end;
                const field_name = tk.val as namespace;
                let found = false;
                if(last_tpe.base is *record){
                    const rec = last_tpe.base as *record;
                    for(let field .. rec.fields){
                        if(field.1.var.nm.name == field_name.name){
                            const (tpe, prop, _end) = eval_cast(ctxt,
                                field.1.var.nm.tpe, end)?;
                            end = _end;
                            const meta = field_meta {
                                before = before,
                                field = field.1,
                                base = null,
                                pos = end,
                                tpe = field.1.var.nm.tpe,
                                prop = prop,
                                from_tpe = last_tpe,
                            };
                            last_tpe = meta.tpe;
                            last_prop = meta.prop;
                            // assign base of chain
                            if(before == null) meta.base = alloc(memb)!;
                            access = alloc(meta)!;
                            before = access;
                            found = true;
                        };
                    };
                };
                if(!found){
                    move_ptr(ctxt, tk);
                    if(before == null){
                        const name = strtype(memb.tpe);
                        defer free(name);
                        return error(ctxt, "object of %b{}%r has %yno field named \"{}\"",
                            name, field_name.name);
                    } else {
                        const bf = before as *field_meta;
                        const name = strtype(bf.tpe);
                        defer free(name);
                        return error(ctxt, "field %b{}%r of %b{}%r has %yno field named \"{}\"",
                            bf.field.var.nm.name, name, field_name.name);
                    };
                };
                tk = next_tk(ctxt, end,
                    "expected valid %bfield access%r or %bexpression continuation%r, but got %y{}")?;
            };
            const final = access as *field_meta;
            memb.tpe = last_tpe;
            memb.val = final;
            memb.prop = void;
        } else if(memb.tpe.fail && memb.tpe.base is *record){
            move_ptr(ctxt, tk);
            const name = strtype(memb.tpe);
            defer free(name);
            return error_hint(ctxt,
                "\n%gtry bubbling the error with %d?%g or asserting it with %d!",
                "cannot access field of %b{}%r", name);
        } else {
            move_ptr(ctxt, tk);
            const name = strtype(memb.tpe);
            defer free(name);
            return error(ctxt, "object of %b{}%r has %yno fields", name);
        };
    };
    return (alloc(memb)!, end, false);
};

fn eval_array_lit(
    ctxt: *context,
    at: size,
    hint: lichen_t,
) ((*array_lit_meta, size) | ERROR) = {
    // assert correct position
    assert(comp_tk(ctxt.tokens[at].val, symbol::LFT_SQUARE));

    let end = at + 1;
    let tk = next_tk(ctxt, end,
        "expected %barray item%r or %bend of array%r, but got %y{}")?;

    // assure expression type is an array and extract
    // array item type for further parsing
    let (tpe, itm_tpe) = wrap_array(hint);
    let spreads_at: (void | size) = void;

    const items: []*expr_meta = [];
    const as_arr = tpe.base as *array;
    // iterate until end of array
    for(!comp_tk(tk.val, symbol::RGT_SQUARE)){
        const begin = end;
        const (itm, _end) = eval_expression(ctxt, end,
            quick_t(primitive::ANY))?;
        end = _end;
        tk = next_tk(ctxt, end,
            "expected %bnext array item%r or %bend of array%r, but got %y{}")?;

        // value is actually the array length
        if(comp_tk(tk.val, symbol::EOL)){
            move_ptr(ctxt, ctxt.tokens[begin]);
            // assert it's a valid length type
            if(!is_subtype(itm.tpe, primitive::U64)){
                const arg1 = strtype(quick_t(primitive::U64));
                defer free(arg1);
                const arg2 = strtype(itm.tpe);
                defer free(arg2);
                return error(ctxt,
                    "expected %btype {}%r as array length, but got %ytype {}",
                    arg1, arg2);
            };
            // assert if the array length is not set
            if(as_arr.length is void){
                // extract expression root and assert for its kind
                const root = extract_root(itm);
                // if it's a number literal
                if(root is *const_meta){
                    const val = root as *const_meta;
                    as_arr.length = val.val as size;
                // something else
                } else {
                    return error(ctxt, "expected %bu64 literal number%r for length");
                };
            } else {
                return error(ctxt, "array length %yset multiple times");
            };
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bnext array item%r or %bend of array%r, but got %y{}")?;
            continue;
        } else if(comp_tk(tk.val, operator::SPREAD)){
            if(as_arr.length is void){
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "cannot %bfill items%r with array of %yundefined size");
            } else {
                assert_hint(ctxt, ctxt.tokens[begin], itm.tpe, itm_tpe)?;
                if(untyped(itm_tpe)) itm_tpe = itm.tpe;
                spreads_at = len(items);
                for(let i = len(items); i < as_arr.length as size; i += 1){
                    append(items, itm)!;
                };
            };
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bnext array item%r or %bend of array%r, but got %y{}")?;
        } else {
            assert_hint(ctxt, ctxt.tokens[begin], itm.tpe, itm_tpe)?;
            if(untyped(itm_tpe)) itm_tpe = itm.tpe;
            // assert for array length
            if(as_arr.length is size && len(items) == as_arr.length as size){
                move_ptr(ctxt, ctxt.tokens[begin]);
                return error(ctxt, "too many items in array of %blength {}",
                    as_arr.length as size);
            };
            append(items, itm)!;
        };

        if(comp_tk(tk.val, symbol::RGT_SQUARE)) break;
        end += 1;
        if(!comp_tk(tk.val, symbol::COMMA)){
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %bcomma%r, bug got %y{}", arg);
        };
        tk = next_tk(ctxt, end,
            "expected %barray item%r or %bend of array%r, but got %y{}")?;
    };
    // assert for array length
    if(as_arr.length is size && len(items) > as_arr.length as size){
        move_ptr(ctxt, tk);
        return error(ctxt, "too many items in array of %blength {}",
            as_arr.length as size);
    };
    end = pop_assert(ctxt, end, symbol::RGT_SQUARE,
        "expected %bend of array%r, but got %y{}")?;

    const (cast, prop, _end) = eval_cast(ctxt, itm_tpe, end)?;
    as_arr.base = cast;
    if(untyped(as_arr.base)){
        move_ptr(ctxt, ctxt.tokens[at]);
        return error(ctxt, "cannot deduce array type");
    };
    if(prop is propagation){
        move_ptr(ctxt, ctxt.tokens[end]);
        return error(ctxt, "cannot %ypropagate%r array items' %yerror state");
    };
    end = _end;
    const out = array_lit_meta {
        tpe = tpe,
        items = items,
        spreads_at = spreads_at,
    };
    return (alloc(out)!, end);
};

fn eval_record_lit(
    ctxt: *context,
    at: size,
    tpe: lichen_t,
) ((*record_lit_meta, size) | ERROR) = {
    const rec = tpe.base as *record;
    let end = pop_assert(ctxt, at + 1, symbol::LFT_CURLY,
        "expected start of %brecord litaral fields%r, but got %y{}")?;
    let tk = next_tk(ctxt, end,
        "expected %bfield assignment%r or %bfield auto fill%r, but got %y{}")?;

    let field_count = 0z;
    const values: [](str, *expr_meta) = [];
    for(!comp_tk(tk.val, symbol::RGT_CURLY)){
        // end of fields
        if(field_count >= len(rec.fields)){
            move_ptr(ctxt, tk);
            return error(ctxt, "no fields are left to be assigned");
        };
        tk = next_tk(ctxt, end,
            "expected %bfield namespace%r, but got %y{}")?;
        end += 1;
        if(!(tk.val is namespace)){
            move_ptr(ctxt, tk);
            const pre = tk;
            tk = next_tk(ctxt, end,
                "expected %bfield namespace%r, but got %y{}")?;
            const hint =
                if(tk.val is namespace && comp_tk(pre.val, symbol::DOT)){
                    const field = strtoken(tk.val as namespace);
                    defer free(field);
                    yield fmt::asprintf("try this:\n\n\t{} {{ {} = ... }}",
                        rec.name.name, field)!;
                };
            const arg = strtoken(pre.val);
            defer free(arg);
            if(hint is str){
                defer free(hint as str);
                return error_hint(ctxt, hint as str,
                    "expected %bfield namespace%r, but got %y{}", arg);
            } else {
                return error(ctxt,
                    "expected %bfield namespace%r, but got %y{}", arg);
            };
        };
        const field_name = tk.val as namespace;
        end = pop_assert(ctxt, end, operator::ASG,
            "expected %bfield assignment%r, but got %y{}")?;

        const (val, _end) = eval_expression(ctxt, end, rec.fields[len(values)].1.var.nm.tpe)?;
        append(values, (field_name.name, val))!;
        field_count += 1;
        end = _end;

        tk = next_tk(ctxt, end,
            "expected %bfield namespace%r, but got %y{}")?;

        if(comp_tk(tk.val, symbol::RGT_CURLY)) break;
        // not a valid trailing token
        if(comp_tk(tk.val, symbol::COMMA)){
            end += 1;    
            tk = next_tk(ctxt, end,
                "expected %bfield assignment%r or %bend of field assignment list%r, but got %y{}")?;
        } else if(!comp_tk(tk.val, symbol::RGT_CURLY)){
            move_ptr(ctxt, tk);
            return error(ctxt, 
                "expected %bcomma%r or %bend of field assignment list%r, but got %y{}");
        };
    };
    if(field_count > len(rec.fields)){
        move_ptr(ctxt, tk);
        return error(ctxt, "no fields are left to be assigned");
    };
    end = pop_assert(ctxt, end, symbol::RGT_CURLY,
        "expected %bend of field assignment list%r, but got %y{}")?;

    const lit = record_lit_meta {
        tpe = tpe,
        values = values,
    };
    return (alloc(lit)!, end);
};

fn eval_ternary(
    ctxt: *context,
    at: size,
    begin: size,
    pos_val: hand_t,
) ((*expr_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, keyword::IF));
    let end = at + 1;
    const (cond, _end) = eval_expression(ctxt, end, quick_t(primitive::BOOL),
        true)?;
    end = _end;
    const tpe = extract_hand_type(pos_val);
    const (neg_val, _end) = eval_expression(ctxt, end + 1, tpe)?;
    end = _end;
    const ternary = ternary_meta {
        pos = begin,
        tpe = tpe,
        positive = pos_val,
        negative = neg_val,
        condition = cond,
    };
    const exp = expr_meta {
        pos = begin,
        tpe = tpe,
        pre = void,
        val = alloc(ternary)!,
        prop = void,
    };
    return (alloc(exp)!, end);
};

fn eval_funcall(
    ctxt: *context,
    fun: *fun_meta,
    at: size,
) ((*funcall_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, symbol::LFT_PAR));
    // validade function effect tags
    validate_efx(ctxt, fun, at)?;
    fun.used = true;

    let tk = next_tk(ctxt, at + 1,
        "expected %bnext argument%r or %bend of argument list%r, but got %y{}")?;
    let end = at + 1;
    let arg_count = 0z;
    let arg_list: []*expr_meta = [];
    const max = len(fun.params);
    for(!comp_tk(tk.val, symbol::RGT_PAR)){
        if(arg_count >= max || max == 0){
            move_ptr(ctxt, tk);
            const hint = fmt::asprintf("\n%gthe function %b{} takes {} {}",
                fun.fun.name, max, fix_plural("parameters", max))!;
            defer free(hint);
            return error_hint(ctxt, hint, "too many arguments in function call");
        };
        const (arg, _end) = eval_expression(ctxt, end,
            fun.params[arg_count].var.nm.tpe)?;
        // assert for mutability matching
        if(arg.val is hand_t && extract_root(arg) is *var_meta){
            const var = extract_root(arg) as *var_meta;
            if(fun.params[arg_count].var.nm.mut && !var.nm.mut){
                move_ptr(ctxt, ctxt.tokens[end]);
                return error(ctxt,
                "function takes a %bmutable reference%r, but variable %b{}%r is not mutable",
                var.nm.name);
            };
        };
        end = _end;

        append(arg_list, arg)!;
        arg_count += 1;

        tk = next_tk(ctxt, end,
            "expected %bcomma%r or %bend of argument list%r, but got %y{}")?;

        if(comp_tk(tk.val, symbol::COMMA)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bcomma%r or %bend of argument list%r, but got %y{}")?;
        } else if(!comp_tk(tk.val, symbol::RGT_PAR)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "expected %bcomma%r or %bend of argument list%r, but got %y{}");
        };
    };
    if(arg_count > max){
        move_ptr(ctxt, tk);
        const hint = fmt::asprintf("\n%gthe function %b{} takes {} {}",
            fun.fun.name, max, fix_plural("parameters", max))!;
        defer free(hint);
        return error_hint(ctxt, hint, "too many arguments in function call");
    };

    end = pop_assert(ctxt, end, symbol::RGT_PAR,
        "expected %bclosing parenthesis%r, but got %y{}")?;

    const call = funcall_meta {
        fun = fun,
        tpe = fun.fun.tpe,
        pos = at,
        args = arg_list,
    };
    return (alloc(call)!, end);
};

// validades effects for a given called function and a caller set of tags
fn validate_efx(
    ctxt: *context,
    called: *fun_meta,
    pos: size,
) (void | ERROR) = {
    assert(ctxt.host_fun != null);
    move_ptr(ctxt, ctxt.tokens[pos - 1]);

    const caller = ctxt.host_fun: *fun_meta;
    if(len(caller.effect) > 0 && caller.effect[0] == "do"){
        if(len(called.effect) > 0 && called.effect[0] == "do"){
            return error(ctxt,
                "functions tagged with %bdo effect%r cannot call another function also tagged with %bdo");
        };
        return;
    };
    if(called.origin == ctxt.file){
        for(let ld_tag .. called.effect){
            let found = false;
            for(let lr_tag .. caller.effect){
                if(comp_tk(ld_tag, lr_tag)){
                    found = true;
                    break;
                };
            };
            if(!found){
                const help = fmt::asprintf(
                    "\n%gtry doing %p\"%d= %b{} %y{{%p\"%g in the function scope definition",
                    ld_tag)!;
                defer free(help);
                return error_hint(ctxt, help,
                    "the function %b{}%r implements the effect %g{}%r, but the caller function doesn't",
                    called.fun.name, ld_tag);
            };
        };
    } else {
        const default = strings::rcut(
            strings::rcut(called.origin, "/").1, ".").0;
        for(let lr_tag .. caller.effect){
            const bind =
                match(get_def(ctxt, dummy_nm(lr_tag), ctxt.scp)){
                case let mod: *module_meta => yield mod.ctxt.file;
                case => yield lr_tag;
                };
            if(bind == called.origin) return;
        };
        const help = fmt::asprintf(
            "\n%gtry doing %p\"%d= %b{} %y{{%p\""
            "%g in the function scope definition",
            default)!;
        defer free(help);
        return error_hint(ctxt, help,
            "the function %b{}%r, from the module "
            "%g{}%r, is %yimpure%r, but the caller function doesn't "
            "implement its effect tag",
            called.fun.name, default);
    };
};

// evaluates a field or parameter declaration
fn eval_declaration(ctxt: *context, at: size) ((*decl_meta, size) | ERROR) = {
    let end = at;
    let tk = next_tk(ctxt, end,
        "expected %bdeclaration namespace%r, but got %y{}")?;
    end += 1;
    // validate namespace
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt,
            "expected %bdeclaration namespace%r, but got %y{}", arg);
    };
    const name = tk.val as namespace;
    // fetch type notation
    const (tpe, _end) = eval_type(ctxt, end)?;
    end = _end;

    name.tpe = tpe;
    const var = var_meta {
        nm = name,
        owner = ctxt,
        pos = at,
    };
    const meta = decl_meta {
        var = alloc(var)!,
        val = void,  
    };
    return (alloc(meta)!, end);
};

// guarantees a given type is always represented as lichen_t
fn wrap_primitive(tpe: (primitive | lichen_t)) lichen_t =
    match(tpe){
    case let prim: primitive => return quick_t(prim);
    case let tp: lichen_t => return tp;
    };

let allocs: []*array = [];

// helper function for anonymous array types
fn alloc_array(arr: array) *array = {
    for(let a ..& allocs){
        if(((a.length is void && arr.length is void) ||
            (a.length is void && arr.length is size) ||
            (a.length is size && arr.length is size &&
            a.length as size == arr.length as size)) &&
            comp_type(a.base, arr.base)){
            return a;
        };
    };
    const res = alloc(arr)!;
    append(allocs, res)!;
    return res;
};

fn free_arrays() void = {
    for(let tpe .. allocs){
        free(tpe);
    };
    free(allocs);
};

// guarantees a given type is always a  
fn wrap_array(_tpe: (primitive | lichen_t)) (lichen_t, lichen_t) = {
    const tpe = wrap_primitive(_tpe);
    match(tpe.base){
    case let arr: *array =>
        return (tpe, arr.base);
    case =>
        const arr = lichen_t {
            fail = false,
            base = alloc_array(array {
                length = void,
                base = tpe,
            }),
        };
        return (arr, tpe);
    };
};

// assert for any type casting and if it's a valid cast
// returns `current` if no cast was found
let logging = false;
fn eval_cast(
    ctxt: *context,
    current: lichen_t,
    at: size,
) ((lichen_t, (void | propagation), size) | ERROR) = {
    let tpe = current;
    let end = at;
    if(!comp_tk(ctxt.tokens[end].val, symbol::EOL) &&
        !comp_tk(ctxt.tokens[end].val, symbol::COMMA) &&
        !comp_tk(ctxt.tokens[end].val, symbol::RGT_PAR))
        match(eval_type(ctxt, end)){
        case let some: (lichen_t, size) =>
            assert_cast(ctxt, ctxt.tokens[end], current, some.0)?;
            tpe = some.0;
            end = some.1;
        case => void;
        };
    let tk = next_tk(ctxt, end,
        "expected %bpropagation operator%r, %bexpression continuation%r or %bend of line%r, but gor %y{}")?;
    
    const after = next_tk(ctxt, end + 1,
        "expected %berror assertion piping%r, %bexpression continuation%r or %bend of line%r, but gor %y{}")?;
    const prop: (void | propagation) =
        if(comp_tk(tk.val, operator::BANG) ||
            comp_tk(tk.val, operator::BUBBLE)){
            end += 1;
            move_ptr(ctxt, tk);
            if(!tpe.fail){
                const arg = strtype(tpe);
                defer free(arg);
                return error(ctxt,
                    "cannot bubble or assert fail state from %b{}",
                    arg);
            } else if(comp_type(tpe, quick_t(primitive::VOID, true))){
                return error_hint(ctxt,
                    "\n%gno value is returned from a (partial) primitive void type",
                    "cannot bubble or assert a void type's fail state");
            };
            const caller = ctxt.host_fun as *fun_meta;
            if(!caller.fun.tpe.fail &&
                comp_tk(tk.val, operator::BUBBLE) &&
                !comp_tk(after.val, keyword::OR)){
                const arg1 = strtype(caller.fun.tpe);
                defer free(arg1);
                const arg2 = strtype(tpe);
                defer free(arg2);
                return error(ctxt,
                    "caller function of type %b{}%r cannot bubble up fail state from %b{}",
                    arg1, arg2);
            } else if(comp_type(caller.fun.tpe, quick_t(primitive::VOID, true))){
                return error_hint(ctxt,
                    "\n%gno value can be returned from a (partial) primitive void type",
                    "cannot bubble up from void type");
            };
            const op = tk.val as operator;
            tpe.fail = false;

            const exp: (void | path_meta) =
                if(comp_tk(after.val, keyword::OR)){
                    end += 1;
                    yield if(op == operator::BUBBLE){
                        const (exp, _end) = eval_expression(ctxt, end, tpe)?;
                        end = _end;
                        yield exp;
                    } else {
                        logging = true;
                        const (stt, _end) = eval_statement(ctxt, end)?;
                        end = _end - 1;
                        yield stt;
                    };
                };
            yield (op, exp);
        };
    return (tpe, prop, end);
};

// evaluates a type notation
fn eval_type(
    ctxt: *context,
    at: size,
    named: (void | namespace) = void,
) ((lichen_t, size) | ERROR) = {
    let tk = next_tk(ctxt, at,
        "expected %btype notation%r, but got %y{}")?;
    let end = at + 1;
    const fail =
        if(comp_tk(tk.val, operator::BANG)){
            tk = next_tk(ctxt, end,
                "expected %btype notation%r, but got %y{}")?;
            end += 1;
            yield true;
        } else {
            yield false;
        };
    match(tk.val){
    case let prim: primitive => return (quick_t(prim, fail), end);
    case let name: namespace =>
        move_ptr(ctxt, tk);
        match(get_def(ctxt, name, ctxt.scp)){
        case let tpe: *type_meta =>
            const res = tpe.self;
            res.fail = fail;
            return (res, end);
        case *fun_meta =>
            return error(ctxt,
                "the namespace %b{}%r is currently defined as a %bfunction%r, not a %ytype",
                name.name);
        case *decl_meta =>
            return error(ctxt,
                "the namespace %b{}%r is currently defined as a %bvariable%r, not a %ytype",
                name.name);
        case *module_meta =>
            return error(ctxt,
                "the namespace %b{}%r is currently defined as a %bmodule binding%r, not a %ytype",
                name.name);
        case void =>
            return error(ctxt,
                "no type by the name %b{}%r is currently defined", name.name);
        };
    case let kwd: keyword =>
        if(named is void){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "anonymous %bcomposed types%r disallowed %youtside type definitions");
        };
        switch(kwd){
        case keyword::RECORD =>
            end = pop_assert(ctxt, end, symbol::LFT_CURLY,
                "expceted %brecord fields declaration%r, but got %y{}")?;
            tk = next_tk(ctxt, end, "expected %brecord field%r, but got %y{}")?;
            let fields: [](bool, *decl_meta) = [];
            for(!comp_tk(tk.val, symbol::RGT_CURLY)){
                tk = next_tk(ctxt, end,
                    "expected %brecord field%r or %bend of fields declaration%r, but got %y{}")?;
                const use_set =
                    if(comp_tk(tk.val, keyword::USE)){
                        end += 1;
                        yield true;
                    } else {
                        yield false;
                    };
                const (field, _end) = eval_declaration(ctxt, end)?;

                for(let f .. fields){
                    if(f.1.var.nm.name == field.var.nm.name){
                        move_ptr(ctxt, ctxt.tokens[f.1.var.pos]);
                        const arg1 = gen_pos(ctxt);
                        defer free(arg1);
                        move_ptr(ctxt, tk);
                        return error(ctxt, "the field %b{}%r was already defined at %y{}",
                            f.1.var.nm.name, arg1);
                    };
                };
                append(fields, (use_set, field))!;

                end = pop_assert(ctxt, _end, symbol::EOL,
                    "expected %bend of line%r, bur got %y{}")?;
                tk = next_tk(ctxt, end,
                    "expected %bnext field%r or %bend of fields declaration%r, but got %y{}")?;

                if(comp_tk(tk.val, symbol::RGT_CURLY)) break;
            };
            end = pop_assert(ctxt, end, symbol::RGT_CURLY,
                "expected %bend of fields declaration%r, but got %y{}")?;

            const fix_name = strings::replace(
                (named as namespace).name, "'", ".q")!;
            defer free(fix_name);
            const rec = record {
                name = named as namespace,
                export_name = fmt::asprintf(":{}", fix_name)!,
                fields = fields,
                defaults = [],
            };
            const out = lichen_t {
                fail = fail,
                base = alloc(rec)!,
            };
            return (out, end);
        case keyword::ENUM => todo("enums");
        case =>
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %btype notation%r, but got %y{}", arg);
        };
    case let sym: symbol =>
        switch(sym){
        case symbol::LFT_SQUARE =>
            tk = next_tk(ctxt, end,
                "expected %bconstant%r or %bclosing brackets%r, but got %y{}")?;
            const length =
                if(tk.val is size){
                    end += 1;
                    yield tk.val as size;
                };
            tk = next_tk(ctxt, end,
                "expected %bclosing brackets%r, but got %y{}")?;
            end += 1;
            if(!comp_tk(tk.val, symbol::RGT_SQUARE)){
                move_ptr(ctxt, tk);
                const arg = strtoken(tk.val);
                defer free(arg);
                return error_hint(ctxt,
                    "\n%gthe syntax for arrays is%d [ %boptional constant%d ]%btype",
                    "expected %bconstant%r or %bclosing brackets%r, but got %y{}",
                    arg);
            };
            const (sub, _end) = eval_type(ctxt, end)?;
            const tpe = lichen_t {
                fail = fail,
                base = alloc(array {
                    length = length,
                    base = sub,
                })!,
            };
            return (tpe, _end);
        case symbol::LFT_PAR =>
            tk = next_tk(ctxt, end,
                "expected %btuple variant%r, but got %y{}")?;
            let memb: []lichen_t = [];
            for(!comp_tk(tk.val, symbol::RGT_PAR)){
                const (m, _end) = eval_type(ctxt, end)?;
                end = _end;
                append(memb, m)!;
                tk = next_tk(ctxt, end,
                    "expected %bcomma%r or %bend of tuple%r, but got %y{}")?;
                end += 1;
                if(comp_tk(tk.val, symbol::COMMA)){
                    tk = next_tk(ctxt, end,
                        "expected %bnext type%r or %bend of tuple%r, but got %y{}")?;
                    end += 1;
                };
            };
            if(!comp_tk(tk.val, symbol::RGT_PAR)){
                move_ptr(ctxt, tk);
                const arg = strtoken(tk.val);
                defer free(arg);
                return error_hint(ctxt,
                    "\n%gthe syntax for tuples is%d ( type %b(, type)%d )",
                    "expected %bclosing parenthesis%r, but got %y{}",
                    arg);
            };
            if(len(memb) < 0){
                move_ptr(ctxt, tk);
                return error(ctxt, "tuple type has %binvalid size%r of %yzero members");
            };
            const tpe = lichen_t {
                fail = fail,
                base = alloc(tuple {
                    members = memb,
                })!,
            };
            return (tpe, end);
        case =>
            move_ptr(ctxt, tk);
            const arg = strtoken(sym);
            defer free(arg);
            return error(ctxt,
                "expected valid %btype notation%r, but got %y{}", arg);
        };
    case =>
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt,
            "expected valid %btype notation%r, but got %y{}", arg);
    };
};

fn assert_unary(ctxt: *context, pos: size, oper: operator, tpe: lichen_t) (void | ERROR) = {
    move_ptr(ctxt, ctxt.tokens[pos]);
    if(!is_unary_op(oper)){
        return error(ctxt, "invalid unary operator");
    };
    if(comp_tk(oper, operator::PLS) || comp_tk(oper, operator::MIN) ||
        comp_tk(oper, operator::NOT) || comp_tk(oper, operator::BANG)){
        assert_hint(ctxt, ctxt.tokens[pos], tpe, primitive::NUMBER)?;
    } else if(comp_tk(oper, operator::LENGTH)){
        assert_hint(ctxt, ctxt.tokens[pos], tpe, primitive::STR)?;
    } else {
        assert(false, "assert_unary: unreachable");
    };
};

// compares two types
fn comp_type(
    _this: (primitive | lichen_t),
    _that: (primitive | lichen_t),
) bool = {
    const this = wrap_primitive(_this);
    const that = wrap_primitive(_that);
    if(this.fail != that.fail) return false;
    if(this.base is primitive && that.base is primitive){
        return this.base as primitive == that.base as primitive;
    } else if(this.base is *record && that.base is *record){
        return this.base as *record == that.base as *record;
    } else if(this.base is *array && that.base is *array){
        return this.base as *array == that.base as *array;
    } else if(this.base is *enum_t && that.base is *enum_t){
        return this.base as *enum_t == that.base as *enum_t;
    } else {
        return false;
    };
};

// checks if a given type is a subset of another
fn is_subtype(
    _this: (primitive | lichen_t),
    _that: (primitive | lichen_t),
) bool = {
    const this = wrap_primitive(_this);
    const that = wrap_primitive(_that);
    return _is_subtype(this, that);
};

fn _is_subtype(_this: lichen_t, _that: lichen_t) bool = {
    // any is a subtype of anything
    if(comp_type(_this, primitive::ANY) ||
        comp_type(_that, primitive::ANY)) return true;
    // an optional type cannot be a subtype of a solid type
    if(!untyped(_this) && !untyped(_that) &&
        _this.fail && !_that.fail) return false;
    // primitive comparison
    if(_this.base is primitive && _that.base is primitive){
        const this = _this.base as primitive;
        const that = _that.base as primitive;
        switch(that){
        case primitive::U8, primitive::U16, primitive::U32,
            primitive::U64 =>
            return (this <= that && this >= primitive::U8) ||
                this == primitive::NUMBER;
        case primitive::I8, primitive::I16, primitive::I32,
            primitive::I64 =>
            return (this <= that && this >= primitive::I8) ||
                this == primitive::NUMBER;
        case primitive::F32, primitive::F64 =>
            return (this <= that && this >= primitive::F32) ||
                this == primitive::RATIO || this == primitive::NUMBER;
        case primitive::NUMBER =>
            return this == primitive::NUMBER || is_subtype(that, this);
        case primitive::RATIO =>
            return this == primitive::RATIO || this == primitive::NUMBER ||
                is_subtype(that, this);
        case primitive::VOID =>
            return this == primitive::UNIT || this == primitive::VOID;
        case =>
            return this == that;
        };
    // array comparison
    } else if(_this.base is *array && _that.base is *array){
        const this = _this.base as *array;
        const that = _that.base as *array;
        const size_ok =
            if(this.length is size && that.length is size){
                yield this.length as size <= that.length as size;
            } else {
                yield true;
            };
        return comp_type(this.base, that.base) && size_ok;
    // union comparison
    } else if(_this.base is *enum_t || _that.base is *enum_t){
        if(_this.base is *enum_t && _that.base is *enum_t){
            return _this.base as *enum_t == _that.base as *enum_t;
        } else if(_this.base is *enum_t && _that.base is primitive){
            const ref = _this.base as *enum_t;
            const var = _that.base as primitive;
            return is_subtype(var, ref.base);
        } else if(_this.base is primitive && _that.base is *enum_t){
            const ref = _that.base as *enum_t;
            const var = _this.base as primitive;
            return is_subtype(var, ref.base);
        } else {
            return false;
        };
    // record comparison
    } else if(_this.base is *record && _that.base is *record){
        const this = _this.base as *record;
        const that = _that.base as *record;
        return this == that;
    } else {
        return false;
    };
};

fn castable(
    _this: (primitive | lichen_t),
    _that: (primitive | lichen_t),
) bool = {
    const this = wrap_primitive(_this);
    const that = wrap_primitive(_that);
    return _castable(this, that);
};

fn _castable(_this: lichen_t, _that: lichen_t) bool = {
    // an optional type cannot be a subtype of a solid type
    if(_this.fail && !_that.fail) return false;
    // primitive comparison
    if(_this.base is primitive && _that.base is primitive){
        const this = _this.base as primitive;
        const that = _that.base as primitive;
        assert(that != primitive::ANY);
        switch(that){
        case primitive::U8, primitive::U16, primitive::U32,
            primitive::U64, primitive::I8, primitive::I16,
            primitive::I32, primitive::I64, primitive::F32,
            primitive::F64, primitive::NUMBER, primitive::RATIO =>
            return is_subtype(this, primitive::NUMBER);
        case primitive::UNIT =>
            return this == that;
        case primitive::VOID =>
            return this == primitive::UNIT || this == primitive::VOID;
        case primitive::CSTR =>
            return is_subtype(this, primitive::STR);
        case primitive::BOOL =>
            return this == primitive::BOOL ||
                (is_subtype(this, primitive::NUMBER) &&
                !is_ratio(quick_t(this)));
        case =>
            return this == that;
        };
    // TODO: record subtyping
    // anything else
    } else {
        return is_subtype(_this, _that);
    };
};

fn extract_hand_type(hand: hand_t) lichen_t = {
    match(hand){
    case let meta: *hand_meta =>
        return meta.tpe;
    case let meta: *member_meta =>
        return meta.tpe;
    case let meta: *expr_meta =>
        return meta.tpe;
    case let meta: *ternary_meta =>
        return meta.tpe;
    };
};

fn extract_root(exp: *expr_meta) (void | path_meta) = {
    match(exp.val){
    case let hand: *hand_meta => return hand;
    case let ternary: *ternary_meta => return ternary;
    case let exp: *expr_meta => return extract_root(exp);
    case let memb: *member_meta =>
        match(memb.val){
        case keyword => void;
        case => return memb.val as member_t;
        };
    };
};

// checks if the given operator can operate on two given types
fn valid_exp(oper: operator, lft_t: lichen_t, rgt_t: lichen_t) bool = {
    switch(oper){
    case operator::EQL, operator::NEQ, operator::LEQ, operator::GEQ,
        operator::LST, operator::GTT =>
        if(untyped(lft_t) || untyped(rgt_t)){
            return is_subtype(lft_t, rgt_t);
        } else {
            return comp_type(lft_t, rgt_t);
        };
    case operator::LOR, operator::LAND =>
        return is_subtype(lft_t, primitive::BOOL) &&
            is_subtype(rgt_t, primitive::BOOL);
    case operator::BOR, operator::BAND, operator::SHL, operator::SHR =>
        if(is_ratio(lft_t) || is_ratio(rgt_t)) return false;
        if(untyped(lft_t) || untyped(rgt_t)){
            return is_subtype(lft_t, primitive::NUMBER) &&
                is_subtype(rgt_t, primitive::NUMBER);
        } else {
            return comp_type(lft_t, rgt_t);
        };
    case operator::PLS, operator::MIN,
        operator::MUL, operator::DIV, operator::MOD =>
        if(untyped(lft_t) || untyped(rgt_t)){
            return is_subtype(lft_t, primitive::NUMBER) &&
                is_subtype(rgt_t, primitive::NUMBER);
        } else {
            return comp_type(lft_t, rgt_t);
        };
    case =>
        assert(false, "unreachable");
        return false;
    };
};

fn reduce_exp_t(oper: operator, lft_t: lichen_t, rgt_t: lichen_t) lichen_t = {
    switch(oper){
    case operator::EQL, operator::NEQ, operator::LEQ, operator::GEQ,
        operator::LST, operator::GTT, operator::LOR, operator::LAND =>
        return quick_t(primitive::BOOL);
    case operator::BOR, operator::BAND, operator::SHL, operator::SHR,
        operator::PLS, operator::MIN, operator::MUL, operator::DIV,
        operator::MOD =>
        if(is_ratio(lft_t) && !untyped(lft_t)){
            return lft_t;
        } else if(is_ratio(lft_t) && !untyped(lft_t)){
            return lft_t;
        } else if(is_ratio(rgt_t) && !untyped(rgt_t)){
            return rgt_t;
        } else if(is_ratio(lft_t) && !untyped(rgt_t)){
            return lft_t;
        } else if(is_ratio(rgt_t) && !untyped(lft_t)){
            return rgt_t;
        } else {
            if(!untyped(lft_t)) return lft_t;
            return rgt_t;
        };
    case =>
        fmt::fatal("reduce_exp_t: unreachable");
    };
};

fn is_ratio(tpe: lichen_t) bool =
    is_subtype(tpe, primitive::RATIO) && !comp_type(tpe, primitive::NUMBER);

// checks is a given type is untyped
fn untyped(tpe: lichen_t) bool = {
    return comp_type(tpe, primitive::ANY) ||
        comp_type(tpe, primitive::NUMBER) ||
        comp_type(tpe, primitive::RATIO);
};

fn is_aggregated(tpe: lichen_t) bool = {
    return tpe.fail || is_subtype(tpe, primitive::STR) ||
        is_subtype(tpe, primitive::CSTR) || tpe.base is *record ||
        tpe.base is *array;
};

fn size_known(tpe: lichen_t) bool = {
    match(tpe.base){
    case let prim: primitive =>
        return !is_subtype(prim, primitive::STR) &&
            !is_subtype(prim, primitive::CSTR);
    case let arr: *array =>
        return arr.length is size;
    case =>
        return true;
    };
};

// assert if given type matches type hint
fn assert_hint(
    ctxt: *context,
    pos: token,
    current: (primitive | lichen_t),
    expected: (primitive | lichen_t),
) (void | ERROR) = {
    if(!is_subtype(current, expected)){
        move_ptr(ctxt, pos);
        const lft = wrap_primitive(current);
        const rgt = wrap_primitive(expected);
        const arg1 = strtype(lft);
        defer free(arg1);
        const arg2 = strtype(rgt);
        defer free(arg2);
        return error(ctxt,
            "type mismatch between value type (%b{}%r) and expected type (%b{}%r)",
            arg1, arg2);
    };
};

// assert if given type cast is valid
fn assert_cast(
    ctxt: *context,
    pos: token,
    current: (primitive | lichen_t),
    new: (primitive | lichen_t),
) (void | ERROR) = {
    if(!castable(current, new)){
        move_ptr(ctxt, pos);
        const lft = wrap_primitive(current);
        const rgt = wrap_primitive(new);
        const arg1 = strtype(lft);
        defer free(arg1);
        const arg2 = strtype(rgt);
        defer free(arg2);
        return error(ctxt,
            "invalid cast of %b{}%r to %b{}%r", arg1, arg2);
    };
};

// pulls next token from token array and asserts for buffer overflow/eof
fn next_tk(ctxt: *context, at: size, msg: str) (token | ERROR) = {
    assert(at < len(ctxt.tokens));
    return ctxt.tokens[at];
};

// calls next_tk and asserts if said token is equal to `val`
fn pop_assert(
    ctxt: *context,
    at: size,
    val: tk_val,
    msg: str,
) (size | ERROR) = {
    const tk = next_tk(ctxt, at, msg)?;
    if(!comp_tk(tk.val, val)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt, msg, arg);
    };
    return at + 1;
};

// returns a tip for a given undefined function
fn undef_tip(name: str) str = {
    if(name == "print"){
        return "\n%gtry using the module %yio%g with "
            "%p\"%bio%d::%bprint%d()%p\"";
    } else if(name == "printf"){
        return "\n%gtry using the module %yio%g with "
            "%p\"%bio%d::%bprintf%d()%p\"";
    } else if(name == "println"){
        return "\n%gtry using the module %yio%g with "
            "%p\"%bio%d::%bprintln%d()%p\"";
    } else if(name == "scan"){
        return "\n%gtry using the module %yio%g with "
            "%p\"%bio%d::%bscan%d()%p\"";
    } else if(name == "scanf"){
        return "\n%gtry using the module %yio%g with "
            "%p\"%bio%d::%bscan%d()%p\"";
    } else {
        return "";
    };
};
