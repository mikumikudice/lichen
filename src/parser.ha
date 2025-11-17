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

// checks if given operator is a binary one
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

// checks if given operator is an unary one
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
fn new_tk(ctxt: *context, val: tk_val) token = {
    return token {
        pos = ctxt.ptr,
        begin = ctxt.begin,
        val = val,
    };
};

// returns the given token as a human-readable string
fn strtoken(tok: tk_val, skip_pre: bool = false) str = {
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
        case primitive::MEM =>
            if(skip_pre) return strings::dup("mem")!;
            return strings::dup("memory arena")!;
        case =>
            if(skip_pre) return strings::dup(prim_value[prim])!;
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

type strtype_mode = enum { NORMAL, SKIP, DEF };

// returns the given lichen type as a human-readable string on NORMAL mode,
// as type notation on SKIP mode and as qbe IR symbol on DEF mode
fn strtype(tpe: lichen_t, mode: strtype_mode = strtype_mode::NORMAL) str = {
    match(tpe.base){
    case let prim: primitive =>
        if(tpe.partial){
            const temp = strtoken(prim, mode != strtype_mode::NORMAL);
            defer free(temp);
            if(mode == strtype_mode::DEF){
                return fmt::asprintf(":{}.opt", temp)!;
            } else {
                return fmt::asprintf("partial !{}", temp)!;
            };
        } else {
            return strtoken(prim, mode != strtype_mode::NORMAL);
        };
    case let rec: *record =>
        if(tpe.partial){
            if(mode == strtype_mode::DEF){
                return fmt::asprintf(":{}.opt", rec.name.name)!;
            } else {
                return fmt::asprintf("partial record type !{}", rec.name.name)!;
            };
        } else if(mode == strtype_mode::DEF){
            return fmt::asprintf("{}", rec.name.name)!;
        } else {
            return fmt::asprintf("record type {}", rec.name.name)!;
        };
    case let arr: *array =>
        const base =
            if(mode != strtype_mode::DEF) strtype(arr.base, strtype_mode::SKIP)
            else strtype(arr.base, mode);
        defer free(base);
        if(mode == strtype_mode::DEF){
            const item_tpe =
                if(strings::hasprefix(base, ":")) strings::sub(base, 1)
                else base;
            const length =
                if(arr.length is size){
                    yield fmt::asprint(arr.length as size)!;
                } else {
                    yield strings::dup("dynamic")!;
                };
            defer free(length);
            if(tpe.partial){
                return fmt::asprintf(":arr.{}.{}.opt", item_tpe, length)!;
            } else {
                return fmt::asprintf(":arr.{}.{}", item_tpe, length)!;
            };
        };
        if(arr.length is void){
            if(tpe.partial){
                if(mode == strtype_mode::SKIP){
                    return fmt::asprintf("![]{}", base)!;
                } else {
                    return fmt::asprintf("partial type ![]{}", base)!;
                };
            } else if(mode == strtype_mode::SKIP){
                return fmt::asprintf("[]{}", base)!;
            } else {
                return fmt::asprintf("type []{}", base)!;
            };
        } else {
            const base = strtype(arr.base, strtype_mode::SKIP);
            defer free(base);
            if(tpe.partial){
                if(mode == strtype_mode::SKIP){
                    return fmt::asprintf("![{}]{}",
                        arr.length as size, base)!;
                } else {
                    return fmt::asprintf("partial type ![{}]{}",
                        arr.length as size, base)!;
                };
            } else if(mode == strtype_mode::SKIP){
                return fmt::asprintf("[{}]{}",
                    arr.length as size, base)!;
            } else {
                return fmt::asprintf("type [{}]{}",
                    arr.length as size, base)!;
            };
        };
    case let ptr: *fun_ptr =>
        const params = memio::dynamic();
        defer io::close(&params)!;
        if(mode == strtype_mode::DEF){
            if(tpe.partial){
                return strings::dup(":fn.ptr.opt")!;
            } else {
                return strings::dup(":fn.ptr")!;
            };
        };
        for(let p = 0z; p < len(ptr.params); p += 1){
            const param = strtype(ptr.params[p].1, strtype_mode::SKIP);
            if(p == 0){
                if(ptr.params[p].0){
                    fmt::fprintf(&params, "mut {}", param)!;
                } else {
                    fmt::fprint(&params, param)!;
                };
            } else {
                if(ptr.params[p].0){
                    fmt::fprintf(&params, ", mut {}", param)!;
                } else {
                    fmt::fprintf(&params, ", {}", param)!;
                };
            };
        };
        const rets = strtype(ptr.returns, strtype_mode::SKIP);
        defer free(rets);

        const efx_list = memio::dynamic();
        defer io::close(&efx_list)!;
        let first = true;
        for(let e .. ptr.efxtags){
            if(first){
                fmt::fprintf(&efx_list, " {}", e)!;
                first = false;
            } else {
                fmt::fprintf(&efx_list, " & {}", e)!;
            };
        };
        const efx = memio::string(&efx_list)!;
        if(tpe.partial){
            return fmt::asprintf("partial function fn({}) {}{}",
                memio::string(&params)!, rets, efx)!;
        } else {
            return fmt::asprintf("function fn({}) {}{}",
                memio::string(&params)!, rets, efx)!;
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
        move_ptr(fun_def.fun.owner, fun_def.fun.owner.tokens[fun_def.pos]);
        const dup_pos = gen_pos(fun_def.fun.owner);
        defer free(dup_pos);
        move_ptr(ctxt, pos);
        return error(ctxt,
            "a function defined at %b{}%r is already using the namespace %y{}",
            dup_pos, nm.name);
    case let decl: *decl_meta =>
        move_ptr(decl.var.nm.owner, decl.var.nm.owner.tokens[decl.var.pos]);
        const dup_pos = gen_pos(decl.var.nm.owner);
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
    case let efx: *effect_t =>
        move_ptr(efx.owner, efx.owner.tokens[efx.pos]);
        const dup_pos = gen_pos(efx.owner);
        defer free(dup_pos);
        move_ptr(ctxt, pos);
        return error(ctxt,
            "an effect tag defined at %b{}%r is already using the namespace %y{}",
            dup_pos, efx.name);
    case void => void;
    };
};

// pushes given function definition to the given context. returns an
// error if the function namespace is already in use.
fn push_def(
    ctxt: *context,
    pos: token,
    name: namespace,
    meta: (*fun_meta | *decl_meta | *type_meta | *module_meta | *effect_t),
) (void | ERROR) = {
    // disallow global empty assignments
    if(name.name == "_" && (name.kind != nm_kind::VAR || name.glob)){
        move_ptr(ctxt, pos);
        return error(ctxt, "invalid name for declaration");
    };
    // assert for dups
    if(name.name != "_"){
        check_shadowing(ctxt, pos, name)?;
        append(ctxt.scp.defs, meta)!;
    };
};

// fetches the corresponding function definition of `name` from the
// current scope. returns void if no match is found.
fn get_def(
    ctxt: *context,
    nm: namespace,
    scp: *scope,
) ((*fun_meta | *decl_meta | *type_meta| *module_meta | *effect_t) | void) = {
    for(let d = len(scp.defs); d > 0; d -= 1){
        const meta = scp.defs[d - 1];
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
        case let efx: *effect_t =>
            if(efx.name == nm.name){
                return efx;
            };
        };
    };
    if(scp.upper is *scope){
        return get_def(ctxt, nm, scp.upper as *scope);
    };
};

// pushes a string literal to the current context
// returns an index for later IR emission
fn push_lit(ctxt: *context, new: str) size = {
    const max = len(ctxt.literals);
    for(let lit = 0z; lit < max; lit += 1){
        if(ctxt.literals[lit] == new) return lit;
    };
    append(ctxt.literals, new)!;
    return max;
};

// converts a primitive type to a lichen type wrapper
fn quick_t(tpe: primitive, partial: bool = false) lichen_t = {
    return lichen_t {
        partial = partial,
        base = tpe,
    };
};

// returns a dummy namespace from a given string
fn dummy_nm(ctxt: *context, val: str) namespace = namespace {
    name = val,
    ffi = void,
    owner = ctxt,
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
    types: (*[]*type_meta | void) = void,
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
    const ctxt = alloc(context {
        file = filename,
        path = stdlib_path,
        main = has_main,
        branching = false,
        allocating = false,
        loop_pos = void,
        iterating_on = [],
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
        lifetime = void,
        re_emit = false,
        global = glob,
        types = if(types is *[]*type_meta){
                yield types as *[]*type_meta;
            } else {
                yield alloc([]: []*type_meta)!;
            },
        free_on_ret = [],
        defer_stack = [],
        on_defer = false,
        scp = glob,
    })!;
    // tokenize
    let max = len(src);
    for(ctxt.ptr < max){
        ctxt.last = ctxt.ptr;
        // skip whitespace
        for(ctxt.ptr < max && is_whitespace(ctxt.src[ctxt.ptr])) inc_ptr(ctxt);
        if(ctxt.ptr >= max) break;

        // remove comments
        if(ctxt.src[ctxt.ptr] == '/' && ctxt.ptr < max - 1){
            if(strings::fromutf8(
                ctxt.src[ctxt.ptr .. ctxt.ptr + 2])! == "//"){
                for(ctxt.ptr < max && ctxt.src[ctxt.ptr] != '\n')
                    inc_ptr(ctxt);
            };
        };
        let end = ctxt.ptr;
        // find the last non-whitespace character
        for(end < max && !is_whitespace(ctxt.src[end])) end += 1;
        if(end >= max) break;
        if(end == ctxt.ptr){
            inc_ptr(ctxt);
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
                    inc_ptr(ctxt, end - ctxt.ptr);
                    continue;
                case strconv::overflow =>
                    return error(ctxt, "64-bit floating point literal overflow");
                case =>
                    return error(ctxt, "invalid floating point literal");
                };
            };
            const unalias = strings::fromutf8(path)!;
            const num = strings::replace(unalias, "_", "")!;
            defer free(num);

            // hex literal
            if(strings::hasprefix(unalias, "0x")){
                match(strconv::stou64(strings::sub(num, 2),
                strconv::base::HEX)){
                case let n: u64 =>
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(ctxt, "64-bit hexadecimal literal overflow");
                case =>
                    return error(ctxt, "invalid hexadecimal literal");
                };
            // oct literal
            } else if(strings::hasprefix(unalias, "0o")){
                match(strconv::stou64(strings::sub(num, 2),
                strconv::base::OCT)){
                case let n: u64 =>
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(ctxt, "64-bit octal literal overflow");
                case =>
                    return error(ctxt, "invalid hexadecimal literal");
                };
            // bin literal
            } else if(strings::hasprefix(unalias, "0b")){
                match(strconv::stou64(strings::sub(num, 2),
                strconv::base::BIN)){
                case let n: u64 =>
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(ctxt, "64-bit binary literal overflow");
                case =>
                    return error(ctxt, "invalid binary literal");
                };
            // dec literal
            } else {
                match(strconv::stou64(num)){
                case let n: u64 =>
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(ctxt,
                        "64-bit literal overflow");
                case =>
                    return error(ctxt, "invalid numeric literal %y\"{}\"", num);
                };
            };
            inc_ptr(ctxt, end - ctxt.ptr);
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
                inc_ptr(ctxt, end - ctxt.ptr);
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
                inc_ptr(ctxt, end - ctxt.ptr);
                continue;
            };
            // it's a namespace
            for(end < max && ctxt.src[end] == '\'') end += 1;
            append(ctxt.tokens, new_tk(ctxt, namespace {
                pub = false,
                mut = false,
                glob = false,
                kind = nm_kind::UNKNOWN,
                name = strings::fromutf8(ctxt.src[ctxt.ptr..end])!,
                ffi = void,
                owner = ctxt,
                tpe = quick_t(primitive::ANY),
            }))!;
            inc_ptr(ctxt, end - ctxt.ptr);
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
                        return error(ctxt, "invalid escape sequence %y\"\\{}\"",
                            ctxt.src[finish]: rune);
                    };
                };
            };
            if(!closed) return error(ctxt, "unclosed string found here");
            finish -= 1;
            assert(!escape);
            append(ctxt.tokens, new_tk(ctxt,
                strings::fromutf8(ctxt.src[start..finish])!))!;
            // advance to the end of the string
            inc_ptr(ctxt, finish - ctxt.ptr + 1);
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
                        return error(ctxt, "invalid escape sequence");
                    };
                    finish += 2;
                } else {
                    return error(ctxt, "invalid escape sequence");
                };
            case =>
                val = ctxt.src[start];
                finish += 1;
            };
            if(ctxt.src[finish] != '\''){
                inc_ptr(ctxt, finish - ctxt.ptr);
                return error(ctxt, "unclosed character literal");
            };
            finish += 1;
            append(ctxt.tokens, new_tk(ctxt, val: size))!;
            inc_ptr(ctxt, finish - ctxt.ptr);
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
                inc_ptr(ctxt);
            case ',' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::COMMA))!;
                start += 1;
                inc_ptr(ctxt);
            case '(' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::LFT_PAR))!;
                start += 1;
                inc_ptr(ctxt);
            case ')' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::RGT_PAR))!;
                start += 1;
                inc_ptr(ctxt);
            case '{' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::LFT_CURLY))!;
                start += 1;
                inc_ptr(ctxt);
            case '}' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::RGT_CURLY))!;
                start += 1;
                inc_ptr(ctxt);
            case '[' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::LFT_SQUARE))!;
                start += 1;
                inc_ptr(ctxt);
            case ']' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::RGT_SQUARE))!;
                start += 1;
                inc_ptr(ctxt);
            case '#' =>
                append(ctxt.tokens, new_tk(ctxt, operator::LENGTH))!;
                start += 1;
                inc_ptr(ctxt);
            case '@' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::AT))!;
                start += 1;
                inc_ptr(ctxt);
            case '.' =>
                if(start < end - 2 && ctxt.src[start + 1] == '.' &&
                    ctxt.src[start + 2] == '.'){
                    append(ctxt.tokens, new_tk(ctxt, operator::SPREAD))!;
                    start += 3;
                    inc_ptr(ctxt, 3);
                } else if(start < end - 1 && ctxt.src[start + 1] == '.'){
                    append(ctxt.tokens, new_tk(ctxt, operator::RANGE))!;
                    start += 2;
                    inc_ptr(ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, symbol::DOT))!;
                    start += 1;
                    inc_ptr(ctxt);
                };
            case '=' =>
                if(start < end - 1 && ctxt.src[start + 1] == '='){
                    append(ctxt.tokens, new_tk(ctxt, operator::EQL))!;
                    start += 2;
                    inc_ptr(ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::ASG))!;
                    start += 1;
                    inc_ptr(ctxt);
                };
            case '<' =>
                if(start < end - 1){
                    if(ctxt.src[start + 1] == '='){
                        append(ctxt.tokens, new_tk(ctxt, operator::LEQ))!;
                        start += 2;
                        inc_ptr(ctxt, 2);
                        continue;
                    } else if(ctxt.src[start + 1] == '<'){
                        append(ctxt.tokens, new_tk(ctxt, operator::SHL))!;
                        start += 2;
                        inc_ptr(ctxt, 2);
                        continue;
                    };
                };
                append(ctxt.tokens, new_tk(ctxt, operator::LST))!;
                start += 1;
                inc_ptr(ctxt);
            case '>' =>
                if(start < end - 1){
                    if(ctxt.src[start + 1] == '='){
                        append(ctxt.tokens, new_tk(ctxt, operator::GEQ))!;
                        start += 2;
                        inc_ptr(ctxt, 2);
                        continue;
                    } else if(ctxt.src[start + 1] == '>'){
                        append(ctxt.tokens, new_tk(ctxt, operator::SHR))!;
                        start += 2;
                        inc_ptr(ctxt, 2);
                        continue;
                    };
                };
                append(ctxt.tokens, new_tk(ctxt, operator::GTT))!;
                start += 1;
                inc_ptr(ctxt);
            case '|' =>
                if(start < end - 1 && ctxt.src[start + 1] == '|'){
                    append(ctxt.tokens, new_tk(ctxt, operator::LOR))!;
                    start += 2;
                    inc_ptr(ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::BOR))!;
                    start += 1;
                    inc_ptr(ctxt);
                };
            case '&' =>
                if(start < end - 1 && ctxt.src[start + 1] == '&'){
                    append(ctxt.tokens, new_tk(ctxt, operator::LAND))!;
                    start += 2;
                    inc_ptr(ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::BAND))!;
                    start += 1;
                    inc_ptr(ctxt);
                };
            case ':' =>
                if(start < end - 1 && ctxt.src[start + 1] == ':'){
                    append(ctxt.tokens, new_tk(ctxt, symbol::FIELD))!;
                    start += 2;
                    inc_ptr(ctxt, 2);
                } else {
                    return error(ctxt,
                        "unrecognized symbol found here");
                };
            case '!' =>
                if(start < end - 1 && ctxt.src[start + 1] == '='){
                    append(ctxt.tokens, new_tk(ctxt, operator::NEQ))!;
                    start += 2;
                    inc_ptr(ctxt, 2);
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::BANG))!;
                    start += 1;
                    inc_ptr(ctxt);
                };
            case '~' =>
                append(ctxt.tokens, new_tk(ctxt, operator::NOT))!;
                start += 1;
                inc_ptr(ctxt);
            case '+' =>
                append(ctxt.tokens, new_tk(ctxt, operator::PLS))!;
                start += 1;
                inc_ptr(ctxt);
            case '-' =>
                append(ctxt.tokens, new_tk(ctxt, operator::MIN))!;
                start += 1;
                inc_ptr(ctxt);
            case '*' =>
                append(ctxt.tokens, new_tk(ctxt, operator::MUL))!;
                start += 1;
                inc_ptr(ctxt);
            case '/' =>
                // skip comment
                if(start < end - 1 && ctxt.src[start + 1] == '/'){
                    for(start < max && ctxt.src[start] != '\n'){
                        start += 1;
                        inc_ptr(ctxt);
                    };
                    // drop tokenization if nothing is left
                    if(start >= end) break;
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::DIV))!;
                    inc_ptr(ctxt);
                    start += 1;
                };
            case '%' =>
                append(ctxt.tokens, new_tk(ctxt, operator::MOD))!;
                start += 1;
                inc_ptr(ctxt);
            case '?' =>
                append(ctxt.tokens, new_tk(ctxt, operator::BUBBLE))!;
                start += 1;
                inc_ptr(ctxt);
            // break at string or character literal
            case '\"' =>
                ctxt.ptr = start;
                break;
            case '\'' =>
                ctxt.ptr = start;
                break;
            case =>
                return error(ctxt, "invalid symbol \"{}\"", ctxt.src[start]: rune);
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
    eval_program(ctxt)?;
    // check if it's defined
    const main = get_def(ctxt, dummy_nm(ctxt, "main"), ctxt.global);
    // no main on a main file
    if(main is void && has_main){
        move_ptr(ctxt, ctxt.tokens[len(ctxt.tokens) - 1]);
        const hint = fmt::asprintf("\n%gtry adding:\n\n%d{}", fn_demo)!;
        defer free(hint);
        return error_hint(ctxt, hint, "missing entry point");
    // main function on a module
    } else if(main is *fun_meta && !has_main){
        const fun = main as *fun_meta;
        move_ptr(ctxt, ctxt.tokens[fun.pos]);
        return error(ctxt,
            "modules shall not %yimplement a main function");
    // main is not defined as a function
    } else if(has_main && main is *decl_meta || main is *module_meta){
        const pos =
            match(main){
            case let decl: *decl_meta => yield decl.var.pos;
            case let module: *module_meta => yield module.pos;
            case => fmt::fatal("unreachable");
            };
        move_ptr(ctxt, ctxt.tokens[pos]);
        return error(ctxt,
            "namespace main was not defined as a function");
    // everything is ok
    } else if(main is *fun_meta){
        const fun_def = main as *fun_meta;
        if(!comp_type(fun_def.fun.tpe, primitive::VOID)){
            const arg = strtoken(primitive::VOID);
            defer free(arg);
            return error(ctxt, "main function shall be of %y{}", arg);
        };
        if(len(fun_def.params) != 0){
            return error(ctxt,
                "main function shall %y receive no parameters");
        };
        // mark to be emitted
        fun_def.used = true;
        if(fun_def.fun.ffi is void && fun_def.used){
            // assign current scope host
            ctxt.host_fun = fun_def;
            // evaluate function scope
            let (body, end) = eval_scope(ctxt, fun_def.begins,
                fun_def.params, true)?;
            ctxt.host_fun = null;
            // pop end of line
            end = pop_assert(ctxt, end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            // assign parsed function body
            fun_def.body = body;
        };
    };
    // parse only needed functions
    eval_functions(ctxt, mod_emit)?;
    return ctxt;
};

fn eval_functions(ctxt: *context, mod_emit: bool) (void | ERROR) = {
    ctxt.re_emit = true;
    let modules: []*module_meta = [];
    defer free(modules);
    for(ctxt.re_emit){
        ctxt.re_emit = false;
        for(let meta .. ctxt.global.defs){
            match(meta){
            case let fun_def: *fun_meta =>
                if(fun_def.fun.ffi is void &&
                    (fun_def.used || mod_emit) &&
                    fun_def.fun.name != "main"){
                    // assign current scope host
                    ctxt.host_fun = fun_def;
                    // evaluate function scope
                    let (body, end) = eval_scope(ctxt, fun_def.begins,
                        fun_def.params, true)?;
                    ctxt.host_fun = null;
                    // pop end of line
                    end = pop_assert(ctxt, end, symbol::EOL,
                        "expected %bend of line%r, but got %y{}")?;
                    // assign parsed function body
                    fun_def.body = body;
                };
            case let module: *module_meta => append(modules, module)!;
            case => void;
            };
        };
        let re_emit_mod = true;
        for(re_emit_mod){
            re_emit_mod = false;
            for(let module .. modules){
                if(!module.parsed){
                    re_emit_mod = true;
                    module.parsed = true;
                };
                eval_functions(module.ctxt, mod_emit)?;
            };
        };
    };
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
                        tpe_def.pub = pub;
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
                    } else if(comp_tk(next.val, keyword::EFX)){
                        if(pub){
                            move_ptr(ctxt, ctxt.tokens[n]);
                            return error(ctxt,
                                "\n%beffects are tied to their local module",
                                "cannot declare an effect as public");
                        };
                        const (efx, end) = eval_effect(ctxt, n)?;
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
            } else if(comp_tk(ctxt.tokens[t + 1].val, keyword::EFX)){
                const (efx, end) = eval_effect(ctxt, t)?;
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

// evaluates a constant definition
// assumes `at` is pointing to the expression's namespace
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
                "\n%gFFI syntax:%d\n\n\tmodule mod = use \"path/to/module\";\n",
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
            pos = at,
            lifetime = void,
            allocated = false,
        })!,
        val = out_val,
    })!;
    append(allocd_nodes, out)!;
    append(allocd_nodes, out.var)!;
    out.var.nm.kind = nm_kind::VAR;
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
    const meta = alloc(const_meta {
        pre = void,
        val = val.val,
    })!;
    // unary operator
    if(val.val is operator){
        assert_unary(ctxt, at, val.val as operator, hint)?;
        meta.pre = val.val as operator;
        val = next_tk(ctxt, end,
            "expected %bconstant value%r, but got %y{}")?;
        end += 1;
        meta.val = val.val;
    };
    // assert if it's valid
    validate_const(ctxt, val, hint)?;
    append(allocd_nodes, meta)!;
    return (meta, end);
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
        case keyword::ERROR, keyword::NIL =>
            let as_err = hint;
            as_err.partial = true;
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

// stack of compiling modules
let mod_comp_stack_count = 0;
let mod_comp_stack: []str = [];
let compiled_modules: []*module_meta = [];

// evaluates a module import expression
// assumes `at` is pointing to `keyword::MOD`
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
    for(let meta .. compiled_modules){
        if(meta.ctxt.file == path){
            free(path);
            push_def(ctxt, ctxt.tokens[at], bind, meta)?;
            return (meta, end);
        };
    };
    for(let mod .. mod_comp_stack){
        if(mod == path){
            move_ptr(ctxt, ctxt.tokens[at]);
            return error(ctxt,
                "recursive import of module \"{}\" detected", ctxt.file);
        };
    };
    // create a stack of compilation units to avoid recursive imports
    append(mod_comp_stack, path)!;
    mod_comp_stack_count += 1;
    const mod_ctxt =
        match(compile(path, ctxt.path, false, false,
            ctxt.literals, ctxt.types)){
        case let c: *context => yield c;
        case let e: ERROR =>
            const msg = memio::string(e)!;
            if(strings::index(msg, "failed to load") is size){
                io::close(e)!;
                free(e);
                move_ptr(ctxt, ctxt.tokens[at]);
                return error(ctxt, "could not find module \"{}\"", path);
            } else {
                return e;
            };
        };
    // pop last item from stack
    mod_comp_stack_count -= 1;
    delete(mod_comp_stack[mod_comp_stack_count]);
    if(mod_comp_stack_count == 0) free(mod_comp_stack);

    const module = alloc(module_meta {
        name = bind.name,
        owner = ctxt,
        pos = at,
        pub = false,
        freed = false,
        parsed = false,
        emitted = false,
        ctxt = mod_ctxt,
    })!;
    append(compiled_modules, module)!;
    push_def(ctxt, ctxt.tokens[at], bind, module)?;
    return (module, end);
};

// evaluates an effect declaration expression
// assumes `at` is pointing to `keyword::MOD`
fn eval_effect(ctxt: *context, at: size) ((*effect_t, size) | ERROR) = {
    const bind = ctxt.tokens[at].val as namespace;
    assert(comp_tk(ctxt.tokens[at + 1].val, keyword::EFX));
    const out = alloc(effect_t {
        pos = at,
        name = bind.name,
        owner = ctxt,
        modcalls = [],
        muts = [],
        ffis = [],
        loop = false,
        ffi = false,
        inherits = [],
        polymorphic = false,
    })!;
    append(allocd_nodes, out)!;
    push_def(ctxt, ctxt.tokens[at], bind, out)?;

    let tk = next_tk(ctxt, at + 2,
        "expected %beffect assignment%r or %bend of line%r, but got %y{}")?;
    if(comp_tk(tk.val, symbol::EOL)){
        out.ffi = true;
        return (out, at + 2);
    };
    // pop assignment
    let end = pop_assert(ctxt, at + 2, operator::ASG,
        "expected %bmodule assignment%r, but got %y{}")?;
    // TODO: effect union expressions
    for(!comp_tk(tk.val, symbol::EOL)){
        tk = next_tk(ctxt, end, "expected %beffect literal or alias%r, but got %y{}")?;
        if(tk.val is keyword){
            switch(tk.val as keyword){
            case keyword::MUT =>
                const (tpe, _end) = eval_type(ctxt, end + 1)?;
                if(!is_aggregated(tpe)){
                    move_ptr(ctxt, ctxt.tokens[end + 1]);
                    return error_hint(ctxt,
                        "\n%gonly %yarrays, records and strings%b can mutate its value",
                        "mutability is %bnot applicable%r to %ynon-aggregated types");
                };
                end = _end;
                append(out.muts, tpe)!;
            case keyword::USE =>
                end += 1;
                tk = next_tk(ctxt, end,
                    "expected %bFFI variable name%r, but got %y{}")?;
                end += 1;
                if(!(tk.val is namespace)){
                    move_ptr(ctxt, tk);
                    const arg = strtoken(tk.val);
                    defer free(arg);
                    return error(ctxt,
                        "expected %bFFI variable name%r, but got %y{}", arg);
                };
                const nm = tk.val as namespace;
                match(get_def(ctxt, nm, ctxt.scp)){
                case let decl: *decl_meta =>
                    if(decl.var.nm.ffi is void){
                        return error(ctxt,
                        "the variable %b{}%r is not a FFI symbol", nm.name);
                    };
                    append(out.ffis, decl)!;
                case =>
                    return error(ctxt,
                        "no %bvariable named {}%r, is defined at this point", nm.name);
                };
            case keyword::WHILE =>
                out.loop = true;
                end += 1;
            case =>
                free(out);
                move_ptr(ctxt, tk);
                const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %bvalid effect notation%r, but got %y{}", arg);
            };
        } else if(tk.val is namespace){
            const name = tk.val as namespace;
            match(get_def(ctxt, name, ctxt.scp)){
            case let efx: *effect_t =>
                merge_effect(out, efx);
                end += 1;
            case let module: *module_meta =>
                merge_effect(out, module);
                end += 1;
            case void =>
                return error(ctxt,
                    "effect %y{}%r is not declared at this point", name.name);
            case =>
                return error(ctxt,
                    "namespace %y{}%r is not a valid effect tag", name.name);
            };
        } else {
            free(out);
            const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %bvalid effect notation%r, but got %y{}", arg);
        };
        tk = next_tk(ctxt, end,
            "expected %beffect concatenation%r or %bend of effect declaration%r, but got %y{}")?;
        if(comp_tk(tk.val, operator::BAND)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %beffect concatenation%r or %bend of effect declaration%r, but got %y{}")?;
        } else if(!comp_tk(tk.val, symbol::EOL)){
            break;
        };
    };
    return (out, end);
};

// evaluates a type definition
// assumes `at` is pointing to `keyword::TYPE`
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
        pub = false,
        name = name,
        self = tpe,
    })!;
    append(allocd_nodes, out)!;
    out.name.kind = nm_kind::TYPE;
    push_def(ctxt, ctxt.tokens[at], name, out)?;
    append(ctxt.types, out)!;
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

    // local meta declarations
    if(tk.val is namespace){
        const sub = next_tk(ctxt, end + 1,
            "expected %bfunction parameter%r or %blocal declaration%r, but got %y{}")?;
        // polymorphic effect
        if(comp_tk(sub.val, keyword::EFX)){
            const name = tk.val as namespace;
            const efx = alloc(effect_t {
                pos = end,
                name = name.name,
                owner = ctxt,
                modcalls = [],
                muts = [],
                ffis = [],
                inherits = [],
                polymorphic = true,
                ...
            })!;
            append(allocd_nodes, efx)!;
            push_def(ctxt, tk, name, efx)?;
            end = pop_assert(ctxt, end + 2, symbol::EOL,
                "expected end of local declarations, but got %y{}")?;
            tk = next_tk(ctxt, end,
                "expected %bparameter%r or %bend of parameter list%r, but got %y{}")?;
        };
    };
    let shared: []size = [];
    let all_muts = true;
    let muts_tpe: [](token, lichen_t) = [];
    defer free(muts_tpe);
    let first_mut = 0z;
    const params: []*decl_meta = [];
    // evaluate parameter declarations
    for(!comp_tk(tk.val, symbol::RGT_PAR)){
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
        param.var.nm.kind = nm_kind::PARAM;
        // define generic lifetime
        if(is_subtype(param.var.nm.tpe, quick_t(primitive::MEM, true))){
            param.var.lifetime = 0;
        };
        // assert for FFI aggregated parameters' mutation
        if(is_aggregated(param.var.nm.tpe)){
            if(mut){
                first_mut = end;
                append(muts_tpe, (ctxt.tokens[end], param.var.nm.tpe))!;
            } else if(!size_known(param.var.nm.tpe)){
                all_muts = false;
            };
        // assert for mutable parameters
        } else if(mut){
            move_ptr(ctxt, ctxt.tokens[end - 1]);
            return error_hint(ctxt,
                "\n%gonly %yarrays, records and strings%b can mutate its value",
                "mutability is %bnot applicable%r to %ynon-aggregated types");
        // add inheriting effect source
        } else if(param.var.nm.tpe.base is *fun_ptr){
            const fptr = param.var.nm.tpe.base as *fun_ptr;
            if(fptr.effects is *effect_t &&
                (fptr.effects as *effect_t).polymorphic){
                append(shared, len(params))!;
            };
        };
        end = _end;

        tk = next_tk(ctxt, end,
            "expected %bnext parameter%r or %bend of parameter list%r, but got %y{}")?;

        // append to parameter list
        append(params, param)!;
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

    tk = next_tk(ctxt, end,
        "expected %bfunction assignment%r or %bborrowing declaration%r, but got %y{}")?;
    
    const borrow =
        if(comp_tk(tk.val, symbol::AT)){
            if(!is_aggregated(name.tpe)){
                move_ptr(ctxt, tk);
                const arg = strtype(name.tpe);
                return error_hint(ctxt,
                    "\n%bnon-aggregated type values cannot go invalid",
                    "returned value of %b{}%r has %yno lifetime", arg);
            };
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bborrowing parameter name%r, but got %y{}")?;
            if(!(tk.val is namespace)){
                move_ptr(ctxt, tk);
                const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %bborrowing parameter name%r, but got %y{}", arg);
            };
            end += 1;
            const b = tk.val as namespace;
            let found = true;
            let p = 0z;
            // search for said parameter
            for(p < len(params); p += 1){
                const param = params[p];
                if(param.var.nm.name == b.name){
                    if(!is_aggregated(param.var.nm.tpe)){
                        move_ptr(ctxt, tk);
                        const arg = strtype(param.var.nm.tpe);
                        return error_hint(ctxt,
                            "\n%bnon-aggregated type values cannot go invalid",
                            "borrowed parameter of %b{}%r has %yno lifetime", arg);
                    };
                    found = true;
                    break;
                };
            };
            if(!found){
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "cannot borrow from %yunknown parameter {}", b.name);
            };
            yield p;
        };
    end = pop_assert(ctxt, end, operator::ASG,
        "expected %bfunction assignment%r, but got %y{}")?;

    // eval effect tags
    const (tags, efx, _end) = eval_efx(ctxt, end)?;
    if(len(shared) > 0){
        append((efx as *effect_t).inherits, shared...)!;
    };
    end = _end;

    // assert mutability
    for(let t .. muts_tpe){
        require_efx(ctxt, t.0, efx, keyword::MUT, t.1)?;
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
                "\n%gcompiler cannot guarantee this foreign function won't mutate aggregated parameters",
                "this function is declared as foreign, but not all of its aggregated-typed parameters are declared as mutable");
        };
        if(efx is void){
            move_ptr(ctxt, tk);
            return error_hint(ctxt,
                "\n%gcompiler cannot guarantee this foreign function won't produce any side effect",
                "this function is declared as foreign, but no effect tag is defined");
        } else if(!(efx as *effect_t).ffi){
            move_ptr(ctxt, tk);
            return error_hint(ctxt,
                "\n%gcompiler cannot guarantee this foreign function won't produce any side effect",
                "this function is declared as foreign, but no such effect is declared");
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
    const out = alloc(fun_meta {
        fun = name,
        pos = pos,
        begins = begins,
        origin = ctxt.file,
        body = null,
        params = params,
        efxtags = tags,
        effects = efx,
        used = false,
        recursive = false,
        borrows = borrow,
    })!;
    append(allocd_nodes, out)!;
    // reserve namespace
    out.fun.kind = nm_kind::FUNC;
    push_def(ctxt, ctxt.tokens[pos], name, out)?;
    return (out, end);
};

// evaluates a list of effect tags
// if ptr == false then parses a function tag list
// if ptr == true then parses a function pointer tag list
// returns a list of tag names, the final effect, the end parser pointer and if
// the single effect tag is shared (only valid if ptr == true)
fn eval_efx(
    ctxt: *context,
    at: size,
) (([]str, effect_tag, size) | ERROR) = {
    let end = at;
    let tags: []str = [];
    let efx: effect_tag = void;
    let tk = next_tk(ctxt, end,
        "expected %beffect tag%r or %bscope definition%r, but got %y{}")?;
    // single do effect
    if(comp_tk(tk.val, keyword::DO)){
        append(tags, "do")!;
        efx = do_effect;
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
    } else if(tk.val is namespace || comp_tk(tk.val, operator::LENGTH)){
        end += 1;
        // loop until start of declaration
        for(!comp_tk(tk.val, symbol::LFT_CURLY) &&
            !comp_tk(tk.val, keyword::USE)){
            move_ptr(ctxt, tk);
            if(!(tk.val is namespace)){
                const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %beffect tag%r, but got %y{}", arg);
            };
            const tag = tk.val as namespace;
            append(tags, tag.name)!;
            match(get_def(ctxt, tag, ctxt.scp)){
            case let e: *effect_t =>
                if(efx is void){
                    efx = alloc(effect_t { // TODO: save this for cleanup
                        pos = end,
                        name = "",
                        owner = ctxt,
                        modcalls = [],
                        muts = [],
                        ffis = [],
                        ffi = false,
                        loop = false,
                        inherits = [],
                        polymorphic = false,
                    })!;
                };
                merge_effect(efx as *effect_t, e);
            case let module: *module_meta =>
                if(efx is void){
                    efx = alloc(effect_t { // TODO: save this for cleanup
                        pos = end,
                        name = "",
                        owner = ctxt,
                        modcalls = [],
                        muts = [],
                        ffis = [],
                        ffi = false,
                        loop = false,
                        inherits = [],
                        polymorphic = false,
                    })!;
                };
                merge_effect(efx as *effect_t, module);
            case void =>
                return error(ctxt, "effect %y{}%r is not declared at this point",
                    tag.name);
            case =>
                return error(ctxt,
                    "namespace %y{}%r is not a valid effect tag",
                    tag.name);
            };
            // address following code
            tk = next_tk(ctxt, end,
                "expected %beffect tag list continuation%r, %bscope "
                "definition%r or %bFFI symbol%r, but got %y{}")?;
            // break at end of list
            if(comp_tk(tk.val, symbol::LFT_CURLY) ||
                comp_tk(tk.val, symbol::COMMA) ||
                comp_tk(tk.val, symbol::RGT_PAR) ||
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
                const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %beffect tag list continuation%r or "
                    "%bscope definition%r, but got %y{}", arg);
            };
        };
    };
    return (tags, efx, end);
};

// merges two effects onto base
fn merge_effect(base: *effect_t, incoming: (*effect_t | *module_meta)) void = {
    if(incoming is *effect_t){
        const incoming = incoming as *effect_t;
        if(incoming.polymorphic) base.polymorphic = true;
        if(incoming.loop) base.loop = true;
        if(incoming.ffi) base.ffi = true;
        for(let i_mod .. incoming.modcalls){
            if(len(base.modcalls) == 0){
                append(base.modcalls, i_mod)!;
            } else {
                let dup = false;
                for(let b_mod .. base.modcalls){
                    if(i_mod == b_mod){
                        dup = true;
                        break;
                    };
                    if(!dup){
                        append(base.modcalls, i_mod)!;
                    };
                };
            };
        };
        for(let i_mut .. incoming.muts){
            if(len(base.muts) == 0){
                append(base.muts, i_mut)!;
            } else {
                let dup = false;
                for(let b_mut .. base.muts){
                    if(comp_type(i_mut, b_mut)){
                        dup = true;
                        break;
                    };
                    if(!dup){
                        append(base.muts, i_mut)!;
                    };
                };
            };
        };
        for(let i_ffi .. incoming.ffis){
            if(len(base.ffis) == 0){
                append(base.ffis, i_ffi)!;
            } else {
                let dup = false;
                for(let b_ffi .. base.ffis){
                    if(i_ffi == b_ffi){
                        dup = true;
                        break;
                    };
                    if(!dup){
                        append(base.ffis, i_ffi)!;
                    };
                };
            };
        };
    } else {
        const module = incoming as *module_meta;
        if(len(base.modcalls) == 0){
            append(base.modcalls, module.name)!;
        } else {
            let dup = false;
            for(let mod .. base.modcalls){
                if(module.name == mod){
                    dup = true;
                    break;
                };
                if(!dup){
                    append(base.modcalls, module.name)!;
                };
            };
        };
    };
};

fn require_efx(
    ctxt: *context,
    pos: token,
    efx: effect_tag,
    kind: keyword,
    val: (*decl_meta | lichen_t | void) = void,
) (void | ERROR) = {
    move_ptr(ctxt, pos);
    if(efx is do_effect) return;
    switch(kind){
    case keyword::MUT =>
        if(efx is *effect_t){
            const efx = efx as *effect_t;
            for(let t .. efx.muts){
                if(comp_type(t, val as lichen_t)) return;
            };
            const arg = strtype(val as lichen_t);
            defer free(arg);
            return error_hint(ctxt,
                "\n%ga mutable reference may mutate the data it carries, generating side-effects",
                "this function %bmutates {} references%r, but does not %yimplement this effect",
                arg);
        } else {
            return error_hint(ctxt,
                "\n%ga mutable reference may mutate the data it carries, generating side-effects",
                "this function %btakes mutable references%r of values, but it %ydeclares no effects");
        };
    case keyword::USE =>
        if(efx is *effect_t){
            const efx = efx as *effect_t;
            for(let d .. efx.ffis){
                if(d == val as *decl_meta) return;
            };
            return error_hint(ctxt,
                "\n%gthe iteraction of an external symbol is not guaranteed to be pure",
                "this function interacts with the %bFFI variable {} ({})%r, but does not %yimplement an effect for it",
                (val as *decl_meta).var.nm.name, (val as *decl_meta).var.nm.ffi as str);
        } else {
            return error_hint(ctxt,
                "\n%ga mutable reference may mutate the data it carries, generating side-effects",
                "this function interacts with the %bFFI variable {} ({})%r, but it %ydeclares no effects",
                (val as *decl_meta).var.nm.name, (val as *decl_meta).var.nm.ffi as str);
        };
    case keyword::WHILE =>
        if(efx is *effect_t && !(efx as *effect_t).loop){
            return error_hint(ctxt,
                "\n%gwhile loops may become infinite loops, "
                "which keeps the program from halting",
                "this function does not implement a %ywhile loop effect");
        } else if(efx is void){
            return error_hint(ctxt,
                "\n%gwhile loops may become infinite loops, "
                "which keeps the program from halting",
                "%bpure functions%r may not use %ywhile loops");
        };
    case => assert(false, "unreachable");
    };
};

fn is_efx_pure(efx: effect_tag) bool = {
    if(efx is void) return true;
    if(efx is do_effect) return false;
    let this = efx as *effect_t;

    if(len(this.modcalls) > 0) return false;
    if(len(this.muts) > 0) return false;
    if(len(this.ffis) > 0) return false;
    return !this.ffi && !this.loop;
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
    func_body: bool = false,
) ((*scope_meta, size) | ERROR) = {
    const upper = ctxt.scp;
    // assign inner scope to context
    ctxt.scp = &scope {
        defs = [], upper = upper,
    };
    // instantiate scope definitions
    for(let param ..& params){
        if(param.var.nm.tpe.base is *fun_ptr){
            const as_fun = param.var.nm.tpe.base as *fun_ptr;
            const ptr = alloc(fun_meta {
                fun = param.var.nm,
                pos = param.var.pos,
                begins = 0,
                origin = ctxt.file,
                body = null,
                params = [],
                efxtags = alloc(as_fun.efxtags...)!,
                effects = as_fun.effects,
                used = true,
                recursive = false,
                borrows = void,
            })!;
            append(allocd_nodes, ptr)!;
            for(let p_tpe .. as_fun.params){
                const p = alloc(decl_meta {
                    var = alloc(var_meta {
                        nm = dummy_nm(ctxt, "unamed"),
                        lifetime = void,
                        allocated = false,
                        pos = 0,
                    })!,
                    val = void,
                })!;
                p.var.nm.tpe = p_tpe.1;
                p.var.nm.mut = p_tpe.0;
                append(allocd_nodes, p)!;
                append(allocd_nodes, p.var)!;
                append(ptr.params, p)!;
            };
            ptr.fun.tpe = as_fun.returns;
            const base = strings::replace(param.var.nm.name, "'", ".q")!;
            defer free(base);
            ptr.fun.ffi = fmt::asprintf("%{}", base)!;
            append(ctxt.scp.defs, ptr)!;
        } else {
            append(ctxt.scp.defs, param)!;
        };
    };
    // initialize a new defer stack and save the previous one
    const prev_stack = ctxt.defer_stack;
    ctxt.defer_stack = [];
    // scope parameters
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
        if(is_terminal(last_tpe)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "no additional code shall fallow %yvoid expressions%r or %yreturn statements");
        };
        const (stt, _end) = eval_statement(ctxt, end)?;
        append(stt_list, stt)!;
        // assert for returns and expression types
        const (_tpe, lst, _rets) =
            assert_ret_state(ctxt, tk, stt, host, tpe, rets)?;
        tpe = _tpe;
        last_tpe = lst;
        rets = _rets;
        end = _end;
        tk = next_tk(ctxt, end,
            "expected %bstatement%r, but got %y{}")?;
    };
    // assign default value to scope
    if(untyped(tpe)) tpe = quick_t(primitive::UNIT);
    // assert for return type mismatch
    if(!func_body && !is_subtype(tpe, primitive::VOID)){
        assert_hint(ctxt, ctxt.tokens[at], tpe, host.fun.tpe)?;
        tpe = host.fun.tpe;
    } else if(func_body){
        assert_hint(ctxt, ctxt.tokens[at], tpe, host.fun.tpe)?;
        tpe = host.fun.tpe;
    };
    free(ctxt.scp.defs); 
    const out = alloc(scope_meta {
        pos = at,
        stt = stt_list,
        defer_stack = ctxt.defer_stack,
        tpe = tpe,
        rets = rets,
    })!;
    append(allocd_nodes, out)!;
    // restore previous defer stack
    ctxt.defer_stack = prev_stack;
    // restore to upper scope
    ctxt.scp = upper;
    return (out, end + 1);
};

fn fetch_stt_type(stt: path_meta) lichen_t = {
    match(stt){
        case let ret: *return_meta =>
        return quick_t(primitive::VOID);
    case *test_meta =>
        return quick_t(primitive::UNIT);
    case let loop: *for_meta =>
        if(loop.rets || is_terminal(loop.tpe)){
            return quick_t(primitive::VOID);
        } else {
            return quick_t(primitive::UNIT);
        };
    case let swtch: *switch_meta =>
        if(swtch.rets || is_terminal(swtch.tpe)){
            return quick_t(primitive::VOID);
        } else {
            return quick_t(primitive::UNIT);
        };
    case let arena: *arena_meta =>
        if(arena.body.rets || is_terminal(arena.body.tpe)){
            return quick_t(primitive::VOID);
        } else {
            return quick_t(primitive::UNIT);
        };
    case let decl: *decl_meta =>
        return decl.var.nm.tpe;
    case let exp: *expr_meta =>
        return exp.tpe;
    case let asg: *assign_meta =>
        return asg.val.tpe;
    case let branch: *branch_meta =>
        if(branch.rets){
            return quick_t(primitive::VOID);
        } else {
            return quick_t(primitive::UNIT);
        };
    case unreachable =>
        return quick_t(primitive::VOID);
    };
};

fn fetch_ret_state(
    ctxt: *context,
    tpe: lichen_t,
    rets: bool,
    stt: path_meta,
) (lichen_t, lichen_t, bool) = {
    const host = ctxt.host_fun as *fun_meta;
    let last_tpe = tpe;
    match(stt){
    case let ret: *return_meta =>
        last_tpe = quick_t(primitive::VOID);
        tpe = ret.val.tpe;
        rets = true;
    case *test_meta =>
        last_tpe = quick_t(primitive::UNIT);
    case let loop: *for_meta =>
        if(loop.rets){
            tpe = loop.tpe;
            last_tpe = quick_t(primitive::VOID);
            rets = true;
        } else {
            last_tpe = loop.tpe;
        };
    case let loop: *while_meta =>
        if(loop.rets){
            tpe = loop.tpe;
            last_tpe = quick_t(primitive::VOID);
            rets = true;
        } else {
            last_tpe = loop.tpe;
        };
    case let swtch: *switch_meta =>
        if(swtch.rets){
            tpe = swtch.tpe;
            last_tpe = quick_t(primitive::VOID);
            rets = true;
        } else {
            last_tpe = swtch.tpe;
        };
    case let arena: *arena_meta =>
        if(arena.body.rets){
            last_tpe = quick_t(primitive::VOID);
            tpe = arena.body.tpe;
            rets = true;
        } else {
            last_tpe = arena.self.var.nm.tpe;
        };
    case let decl: *decl_meta =>
        last_tpe = quick_t(primitive::UNIT);
    case let exp: *expr_meta =>
        const root = extract_root(exp);
        if(root is *funcall_meta){
            const call = root as *funcall_meta;
            if(call.tailcall){
                last_tpe = quick_t(primitive::VOID);
            } else {
                last_tpe = exp.tpe;
            };
        } else {
            last_tpe = exp.tpe;
        };
    case let asg: *assign_meta =>
        last_tpe = quick_t(primitive::UNIT);
    case let branch: *branch_meta =>
        if(branch.rets){
            last_tpe = quick_t(primitive::VOID);
            tpe = host.fun.tpe;
            rets = true;
        } else {
            last_tpe = branch.tpe;
        };
    case loop_break =>
        last_tpe = quick_t(primitive::VOID);
        tpe = last_tpe;
    case loop_next =>
        last_tpe = quick_t(primitive::VOID);
        tpe = last_tpe;
    case *defer_meta =>
        last_tpe = quick_t(primitive::UNIT);
    case unreachable =>
        last_tpe = quick_t(primitive::VOID);
        tpe = last_tpe;
    };
    return (tpe, last_tpe, rets);
};

fn assert_ret_state(
    ctxt: *context,
    tk: token,
    stt: path_meta,
    host: *fun_meta,
    tpe: lichen_t,
    rets: bool,
) ((lichen_t, lichen_t, bool) | ERROR) = {
    const (_tpe, last_tpe, _rets) = fetch_ret_state(ctxt, tpe, rets, stt);
    tpe = _tpe;
    rets = _rets;
    // address for ignored errors
    if(last_tpe.partial && !rets &&
        !comp_type(last_tpe, quick_t(primitive::VOID, true))){
        move_ptr(ctxt, tk);
        return error_hint(ctxt,
            "\n%gtry bubbling the error with %d?%g or asserting it with %d!",
            "cannot %yignore error value%r in here");
    };
    // address for unassigned pure functions and recursion
    if(stt is *expr_meta){
        const root = extract_root(stt as *expr_meta);
        if(root is *funcall_meta){
            const call = root as *funcall_meta;
            if(!is_terminal(call.fun.fun.tpe)){
                if(call.fun.effects is void){
                    move_ptr(ctxt, tk);
                    if(call.fun.origin == ctxt.file){
                        return error_hint(ctxt,
                            "\n%btry assigning it to a variable or using it on an expression",
                            "the function %b{}()%r is %ypure%r, but its value is %ynever used",
                            call.fun.fun.name);
                    } else {
                        const mod = strings::rcut(
                            strings::rcut(call.fun.origin, "/").1, ".").0;
                        return error_hint(ctxt,
                            "\n%btry assigning it to a variable or using it on an expression",
                            "the function %b{}::{}()%r is %ypure%r, but its value is %ynever used",
                            mod, call.fun.fun.name);
                    };
                // effects shared
                } else if(call.fun.effects is *effect_t &&
                    len((call.fun.effects as *effect_t).inherits) > 0){
                    let total_efx: *effect_t = &effect_t {
                        owner = ctxt,
                        ...
                    };
                    for(let a = 0z; a < len(call.args); a += 1){
                        const arg = call.args[a];
                        const efx = call.fun.effects as *effect_t;
                        for(let shared .. efx.inherits){
                            if(a == shared){
                                const ptr = extract_root(arg) as *fn_ptr_meta;
                                // ignore pure inheritage
                                if(ptr.points_to.effects is void) continue;
                                // surely impure
                                if(ptr.points_to.effects is do_effect) return (tpe, last_tpe, rets);
                                merge_effect(total_efx, ptr.points_to.effects as *effect_t);
                            };
                        };
                    };
                    if(is_efx_pure(total_efx)){
                        move_ptr(ctxt, tk);
                        if(call.fun.origin == ctxt.file){
                            return error_hint(ctxt,
                                "\n%btry assigning it to a variable or using it on an expression",
                                "the function %b{}()%r %binherits no effects%r, becoming %ypure%r, but its value is %ynever used",
                                call.fun.fun.name);
                        } else {
                            const mod = strings::rcut(
                                strings::rcut(call.fun.origin, "/").1, ".").0;
                            return error_hint(ctxt,
                                "\n%btry assigning it to a variable or using it on an expression",
                                "the function %b{}::{}()%r %binherits no effects%r, becoming %ypure%r, but its value is %ynever used",
                                mod, call.fun.fun.name);
                        };
                    };
                };
            } else {
                if(call.tailcall){
                    move_ptr(ctxt, tk);
                    return error_hint(ctxt,
                        "\n%ga void function shall halt without recursion",
                        "recursion on void function detected");
                };
            };
        };
    };
    return (tpe, last_tpe, rets);
};

// evaluates a statement
fn eval_statement(ctxt: *context, at: size) ((path_meta, size) | ERROR) = {
    let end = at;
    // fetch first token
    let tk = next_tk(ctxt, end, "expected %bstatement%r, but got %y{}")?;
    match(tk.val){
    case let kwd: keyword =>
        switch(kwd){
        case keyword::TEST =>
            const (test, _end) = eval_test(ctxt, end)?;
            end = _end;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (test, end);
        case keyword::LET =>
            if(ctxt.on_defer){
                move_ptr(ctxt, tk);
                return error_hint(ctxt,
                    "\n%gthis variable would never be used, hence this "
                    "code path would be meaningless",
                    "cannot %bdefine variables%r within %ydefer statement");
            };
            end += 1;
            const (decl, _end) = eval_var_def(ctxt, end)?;
            decl.var.nm.kind = nm_kind::VAR;
            push_def(ctxt, ctxt.tokens[end], decl.var.nm, decl)?;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (decl, end);
        case keyword::NEW =>
            const (arena, _end) = eval_arena(ctxt, end)?;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (arena, end);
        case keyword::IF =>
            const (branch, _end) = eval_ifelse(ctxt, end)?;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (branch, end);
        case keyword::FOR =>
            const (loop, _end) = eval_for_loop(ctxt, end)?;
            end = _end;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (loop, end);
        case keyword::WHILE =>
            const (loop, _end) = eval_while_loop(ctxt, end)?;
            end = _end;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (loop, end);
        case keyword::SWITCH =>
            const (swtch, _end) = eval_switch(ctxt, end)?;
            end = _end;
            return (swtch, end);
        case keyword::RETURN =>
            if(ctxt.on_defer){
                move_ptr(ctxt, tk);
                return error(ctxt, "cannot %bhalt%r within %ydefer statement");
            };
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
                const out = alloc(return_meta {
                    val = alloc(val)!,
                    tpe = host.fun.tpe,
                    pos = at,
                })!;
                append(allocd_nodes, out)!;
                return (out, end);
            };
            const (val, _end) = eval_expression(ctxt, end, host.fun.tpe)?;
            const root = extract_root(val);
            if((root is *var_meta ||
                root is *funcall_meta ||
                root is *array_lit_meta ||
                root is *indexing_meta ||
                root is *record_lit_meta ||
                root is *alloc_meta)
                && is_aggregated(val.tpe)){
                const assign_lifetime =
                    match(root){
                    case let var: *var_meta => yield var.lifetime;
                    case let call: *funcall_meta => yield call.lifetime;
                    case let all: *alloc_meta => yield all.arena.lifetime;
                    case *array_lit_meta => yield void;
                    case *record_lit_meta => yield void;
                    };
                if(assign_lifetime is size && assign_lifetime as size > 0){
                    move_ptr(ctxt, ctxt.tokens[end]);
                    return error(ctxt, "upper scope outlives variable lifetime");
                } else if(root is *var_meta){
                    const var = root as *var_meta;
                    if(var.allocated && host.borrows is void){
                        move_ptr(ctxt, ctxt.tokens[end]);
                        return error(ctxt, "return value's %ylifetime not specified");
                    };
                } else if(host.borrows is void && root is *alloc_meta){
                    const fun_tpe = strtype(host.fun.tpe, strtype_mode::SKIP);
                    defer free(fun_tpe);
                    const all = root as *alloc_meta;
                    const arena = all.arena.nm.name;
                    const hint = fmt::asprintf(
                        "\n%gtry doing %d`{}(...) {} @ {}`%g on the function declaration",
                        host.fun.name, fun_tpe, arena)!;
                    defer free(hint);
                    move_ptr(ctxt, ctxt.tokens[end]);
                    return error_hint(ctxt, hint,
                        "return value's %ylifetime not specified");
                } else if(host.borrows is void && root is *array_lit_meta){
                    const arr = root as *array_lit_meta;
                    if(arr.has_allocs){
                        move_ptr(ctxt, ctxt.tokens[end]);
                        return error_hint(ctxt,
                            "some items of the array are dynamically allocated",
                            "return value's %ylifetime not specified");
                    };
                } else if(host.borrows is void && root is *record_lit_meta){
                    const rec = root as *record_lit_meta;
                    if(rec.has_allocs){
                        move_ptr(ctxt, ctxt.tokens[end]);
                        return error_hint(ctxt,
                            "some fields of the record are dynamically allocated",
                            "return value's %ylifetime not specified");
                    };
                };
            };
            const out = alloc(return_meta {
                val = val,
                tpe = host.fun.tpe,
                pos = at,
            })!;
            assert_hint(ctxt, tk, out.val.tpe, out.tpe)?;
            if(!(val.tpe.base is primitive)) out.val.tpe = out.tpe;

            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;

            append(allocd_nodes, out)!;
            return (out, end);
        case keyword::BREAK =>
            if(ctxt.loop_pos is void){
                move_ptr(ctxt, tk);
                return error(ctxt, "control statement out of a loop");
            };
            end = pop_assert(ctxt, end + 1, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return ((ctxt.loop_pos as size): loop_break, end);
        case keyword::NEXT =>
            end = pop_assert(ctxt, end + 1, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            if(ctxt.loop_pos is void){
                move_ptr(ctxt, tk);
                return error(ctxt, "control statement out of a loop");
            };
            return ((ctxt.loop_pos as size): loop_next, end);
        case keyword::DEFER =>
            end += 1;
            // set context to be aware we are in a defer
            // state and save the previous state
            const old_defer = ctxt.on_defer;
            ctxt.on_defer = true;
            const (self, _end) = eval_statement(ctxt, end)?;
            // restore previous state
            ctxt.on_defer = old_defer;
            const out = alloc(defer_meta {
                self = self,
                pos = at,
            })!;
            end = _end;
            append(ctxt.defer_stack, self)!;
            append(allocd_nodes, out)!;
            return (out, end);
        case keyword::UNREACHABLE =>
            end = pop_assert(ctxt, end + 1, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (unreachable, end);
        case =>
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt, "unexpected %y{}", arg);
        };
    // assignment
    case let var: namespace =>
        const begin = end;
        tk = next_tk(ctxt, end + 1,
            "expected %bassignment%r or %bexpression continuation%r, but got %y{}")?;
        // variable assignment
        if(comp_tk(tk.val, operator::ASG)){
            const eq = end + 1;
            end += 2;
            match(get_def(ctxt, var, ctxt.scp)){
            case let var_def: *decl_meta =>
                // assert for parameters
                if(var_def.var.nm.kind == nm_kind::PARAM){
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
                for(let i = len(ctxt.iterating_on); i > 0; i -= 1){
                    const iter = ctxt.iterating_on[i - 1];
                    if(iter.nm.name == var_def.var.nm.name){
                        move_ptr(ctxt, ctxt.tokens[eq]);
                        return error(ctxt,
                            "cannot reassign to current for-loop iterator");
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
                if(!size_known(val.tpe)){
                    assert_mutability(ctxt, ctxt.tokens[eq],
                        var_def.var.nm.name, var_def.var.nm.mut,
                        root as path_meta)?;
                };
                // assert for lifetimes
                if(root is *var_meta || root is *funcall_meta ||
                    root is *slicing_meta || root is *field_meta){
                    const pass_lifetime =
                        match(root){
                        case let var: *var_meta => yield var.lifetime;
                        case let call: *funcall_meta => yield call.lifetime;
                        };
                    if(pass_lifetime is size && var_def.var.lifetime is void){
                        move_ptr(ctxt, ctxt.tokens[end]);
                        return error(ctxt,
                            "value has a defined lifetime, but variable doesn't");
                    } else if(pass_lifetime is size &&
                        var_def.var.lifetime is size){
                        if(pass_lifetime as size >
                            var_def.var.lifetime as size){
                            move_ptr(ctxt, ctxt.tokens[end]);
                            return error(ctxt, "variable outlives value lifetime");
                        };
                    };
                // edge case for mutability
                } else if(root is *var_meta && val.tpe.base is *record){
                    const pass = root as *var_meta;
                    const rec = val.tpe.base as *record;
                    if(!rec.copiable && var_def.var.nm.mut != pass.nm.mut){
                        const tpe_name = strtype(val.tpe);
                        defer free(tpe_name);
                        move_ptr(ctxt, ctxt.tokens[eq]);
                        const hint = fmt::asprintf(
                            "\n%bsome fields of {} have unknown size"
                            " at compile time and cannot be copied to the stack"
                            " to avoid mutability breaks", tpe_name)!;
                        defer free(hint);
                        if(var_def.var.nm.mut && !rec.safe_mut){
                            return error_hint(ctxt, hint,
                                "cannot copy this %bimmutable aggregated value%r to %ymutable variable");
                        } else if(!var_def.var.nm.mut){
                            return error_hint(ctxt, hint,
                                "source value is immutable, but destination variable is not");
                        };
                    };
                };
                end = pop_assert(ctxt, _end, symbol::EOL,
                    "expected %bend of line%r, but got %y{}")?;
                const asg = alloc(assign_meta {
                    pos = begin,
                    var = var_def.var,
                    val = val,
                    host = void,
                })!;
                append(allocd_nodes, asg)!;
                return (asg, end);
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
        // expression
        } else {
            const (_exp, _end) = eval_asg_or_exp(ctxt, end, quick_t(primitive::ANY), true)?;
            if(_exp is *expr_meta){
                const exp = _exp as *expr_meta;
                if(is_terminal(exp.tpe) && ctxt.on_defer){
                    move_ptr(ctxt, ctxt.tokens[begin]);
                    return error(ctxt, "cannot %bhalt%r within %ydefer statement");
                };
            };
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            return (_exp, end);
        };
    // expression
    case =>
        const (exp, _end) = eval_expression(ctxt, end, quick_t(primitive::ANY))?;
        if(is_terminal(exp.tpe) && ctxt.on_defer){
            move_ptr(ctxt, tk);
            return error(ctxt, "cannot %bhalt%r within %ydefer statement");
        };
        end = pop_assert(ctxt, _end, symbol::EOL,
            "expected %bend of line%r, but got %y{}")?;
        return (exp, end);
    };
};

fn has_lifetime(val: *expr_meta) bool = {
    const root = extract_root(val);
    if((root is *var_meta ||
        root is *funcall_meta ||
        root is *array_lit_meta ||
        root is *record_lit_meta ||
        root is *alloc_meta)
        && is_aggregated(val.tpe)){
        const assign_lifetime =
            match(root){
            case let var: *var_meta => yield var.lifetime;
            case let call: *funcall_meta => yield call.lifetime;
            case let all: *alloc_meta => yield all.arena.lifetime;
            case *array_lit_meta => yield void;
            case *record_lit_meta => yield void;
            };
        if(assign_lifetime is size){
            return true;
        } else if(root is *var_meta){
            const var = root as *var_meta;
            return var.allocated;
        } else if(root is *alloc_meta){
            return true;
        } else if(root is *array_lit_meta){
            const arr = root as *array_lit_meta;
            return arr.has_allocs;
        } else if(root is *record_lit_meta){
            const rec = root as *record_lit_meta;
            return rec.has_allocs;
        } else {
            return false;
        };
    };
    return false;
};

// evaluates a `test` statement
fn eval_test(ctxt: *context, at: size) ((*test_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, keyword::TEST));
    let end = at + 1;
    let tk = next_tk(ctxt, end,
        "expected %bbubble operator%r or %bcondition%r, but got %y{}")?;

    const props = comp_tk(tk.val, operator::BUBBLE);
    const host_fun = ctxt.host_fun as *fun_meta;
    if(props){
        if(!host_fun.fun.tpe.partial){
            move_ptr(ctxt, tk);
            const arg = strtype(host_fun.fun.tpe);
            defer free(arg);
            return error(ctxt,
                "cannot bubble or assert error state from %b{}", arg);
        };
        end += 1;
    };
    const (exp, _end) = eval_expression(ctxt, end, quick_t(primitive::BOOL))?;
    end = _end;

    tk = next_tk(ctxt, end,
        "expected %bcomma%r or %bend of line%r, but got %y{}")!;

    let message = "";
    if(comp_tk(tk.val, symbol::COMMA)){
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %bassertion message%r or %bend of line%r, but got %y{}")!;
        if(tk.val is str){
            message = tk.val as str;
        } else {
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %bassertion message%r or %bend of line%r, but got %y{}", arg);
        };
        end += 1;
    };
    const buffer = memio::dynamic();
    move_ptr(ctxt, ctxt.tokens[at + 1]);
    const pos = gen_pos(ctxt);
    defer free(pos);

    if(message != ""){
        fmt::fprintf(&buffer, "{}: {}\\n", pos, message)!;
    } else {
        fmt::fprintf(&buffer, "{}: test failed\\n", pos)!;
    };
    const out = alloc(test_meta {
        pos = at,
        cond = exp,
        props = props,
        host_tpe = host_fun.fun.tpe,
        buffer = alloc(buffer)!,
        str_id = push_lit(ctxt, memio::string(&buffer)!),
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

// evaluates a memory arena statement
fn eval_arena(ctxt: *context, at: size) ((*arena_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, keyword::NEW));
    let end = at + 1;
    let tk = next_tk(ctxt, end, "expected %barena name%r, but got %y{}")?;
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        return error(ctxt,
            "expected %barena name%r, but got %y{}", arg);
    };
    const name = tk.val as namespace;
    // assert for namespace shadowing
    check_shadowing(ctxt, tk, name)?;

    name.mut = true;
    name.tpe = quick_t(primitive::MEM, true);
    end = pop_assert(ctxt, end + 1,
        operator::BOR, "expected %b\"%d|%b\"%r, but got %y{}")?;

    const (chunk_size, _end) = eval_expression(ctxt,
        end, quick_t(primitive::U64))?;
    end = _end;
    
    const skip = skip_scope(ctxt, end)?;
    const (tpe, prop, final) = eval_cast(ctxt, name.tpe, skip)?;
    name.tpe = tpe;
    const old_lifetime = ctxt.lifetime;
    if(old_lifetime is size){
        ctxt.lifetime = old_lifetime as size + 1;
    } else {
        ctxt.lifetime = 1;
    };
    const self = alloc(decl_meta {
        var = alloc(var_meta {
            nm = name,
            pos = at + 1,
            lifetime = ctxt.lifetime,
            allocated = false,
        })!,
        val = void,
    })!;
    append(allocd_nodes, self)!;
    append(allocd_nodes, self.var)!;
    const (scope, _end) = eval_scope(ctxt, end, [self])?;
    ctxt.lifetime = old_lifetime;
    end = final;
    const host = ctxt.host_fun as *fun_meta;
    const out = alloc(arena_meta {
        pos = at,
        self = self,
        body = scope,
        prop = prop,
        host = host.fun.tpe,
        length = chunk_size,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
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
    let allocated = false;
    const root = extract_root(val);
    if(root is *alloc_meta){
        allocated = true;
    } else if(root is *record_lit_meta){
        const rec = root as *record_lit_meta;
        if(rec.has_allocs) allocated = true;
    };
    const var = alloc(var_meta {
        nm = name,
        pos = pos,
        lifetime = void,
        allocated = allocated,
    })!;
    append(allocd_nodes, var)!;
    const root = extract_root(val);
    // fetch lifetime
    if(root is *alloc_meta){
        const all = root as *alloc_meta;
        var.lifetime = all.arena.lifetime;
    // assert for immutability dropping
    } else if(!size_known(val.tpe)){
        assert_mutability(ctxt, ctxt.tokens[eq],
            name.name, mut, root as path_meta)?;
    // mutable record
    }  else if(root is *var_meta && val.tpe.base is *record){
        const pass = root as *var_meta;
        const rec = val.tpe.base as *record;
        if(!rec.copiable && mut != pass.nm.mut){
            const tpe_name = strtype(val.tpe);
            defer free(tpe_name);
            move_ptr(ctxt, ctxt.tokens[eq]);
            const hint = fmt::asprintf(
                "\n%bsome fields of {} have unknown size"
                " at compile time and cannot be copied to the stack"
                " to avoid mutability breaks", tpe_name)!;
            defer free(hint);
            if(mut && !rec.safe_mut){
                return error_hint(ctxt, hint,
                    "cannot copy this %bimmutable aggregated value%r to %ymutable variable");
            } else if(!mut){
                return error_hint(ctxt, hint,
                    "source value is immutable, but destination variable is not");
            };
        };
    };
    end = _end;
    var.nm.tpe = val.tpe;
    var.nm.mut = mut;
    // assert for typing
    if(untyped(var.nm.tpe)){
        move_ptr(ctxt, ctxt.tokens[eq]);
        return error(ctxt, "cannot deduce %yexpression type");
    } else if(is_terminal(var.nm.tpe)){
        move_ptr(ctxt, ctxt.tokens[eq]);
        const arg = strtype(var.nm.tpe);
        defer free(arg);
        return error_hint(ctxt, 
            "\n%ga (partial) %bprimitive type void%g never returns",
            "cannot assign %b{}%r to variables", arg);
    } else if(comp_type(var.nm.tpe, quick_t(primitive::UNIT))){
        move_ptr(ctxt, ctxt.tokens[eq]);
        return error_hint(ctxt, 
            "\n%gthe %bprimitive type unit%g is incomplete and has no value",
            "cannot assign %bprimitive type unit%r to variables");
    };
    const out = alloc(decl_meta {
        var = var,
        val = val,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

fn assert_mutability(
    ctxt: *context,
    pos: token,
    dest: str,
    dest_mut: bool,
    src: path_meta,
) (void | ERROR) = {
    move_ptr(ctxt, pos);
    match(src){
    case let pass: *var_meta =>
        if(dest_mut != pass.nm.mut){
            const hint = fmt::asprintf(
                "\n%baggregated types of unknown length at compile time, "
                "such as strings, dynamic arrays and slices, cannot"
                " be copied to the stack to avoid mutability breaks."
                "\ntry using:\n\n\t%dlet mut {} = new ! {} @ arena\n",
                dest, pass.nm.name)!;
            defer free(hint);
            if(dest_mut){
                return error_hint(ctxt, hint,
                    "cannot copy this %bimmutable aggregated value%r to %ymutable variable");
            } else {
                return error_hint(ctxt, hint,
                    "source value is immutable, but destination variable is not");
            };
        };
    case let field: *field_meta =>
        if(dest_mut && !field.mut){
            return error_hint(ctxt,
                "\n%baggregated types of unknown length at compile time,"
                " such as strings, dynamic arrays and slices, cannot"
                " be copied to the stack to avoid mutability breaks",
                "record field {} is immutable and cannot be safely copied",
                field.field.var.nm.name);
        } else if(!dest_mut && field.mut){
            return error_hint(ctxt,
                "\n%baggregated types of unknown length at compile time,"
                " such as strings, dynamic arrays and slices, cannot"
                " be copied to the stack to avoid mutability breaks",
                "record field {} is mutable and cannot be safely copied",
                field.field.var.nm.name);
        };
    case let index: *indexing_meta =>
        if(index.base is *member_meta){
            const source = index.base as *member_meta;
            if(source.val is *var_meta){
                const pass = source.val as *var_meta;
                assert_mutability(ctxt, pos,
                    dest, dest_mut, pass)?;
            };
        } else {
            assert_mutability(ctxt, pos, dest,
                dest_mut, index.before as chain_exp_t)?;
        };
    case let slice: *slicing_meta =>
        if(slice.base is *member_meta){
            const source = slice.base as *member_meta;
            if(source.val is *var_meta){
                const pass = source.val as *var_meta;
                assert_mutability(ctxt, pos, dest, dest_mut, pass)?;
            };
        } else {
            assert_mutability(ctxt, pos, dest,
                dest_mut, slice.before as chain_exp_t)?;
        };
    case => void;
    };
};

fn eval_ifelse(ctxt: *context, at: size) ((*branch_meta, size) | ERROR) = {
    let end = at;
    assert(comp_tk(ctxt.tokens[end].val, keyword::IF));
    let tk = ctxt.tokens[end];
    end += 1;

    const old_branch = ctxt.branching;
    ctxt.branching = true;

    let tpe = quick_t(primitive::ANY);
    let rets = false;
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
                local.var.nm.kind = nm_kind::VAR;
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
            if(!is_terminal(body.tpe)) rets = false;
        } else {
            assert_hint(ctxt, ctxt.tokens[body.pos], tpe, body.tpe)?;
            tpe = body.tpe;
            rets = true;
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
                    local_set = true;
                    local.var.nm.kind = nm_kind::VAR;
                    push_def(ctxt, tk, local.var.nm, local)?;
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
            if(!body.rets){
                if(!is_terminal(body.tpe)) rets = false;
            } else {
                assert_hint(ctxt, ctxt.tokens[body.pos], tpe, body.tpe)?;
                tpe = body.tpe;
                rets = true;
            };
        } else {
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %belse block%r or %bend of line%r, but got %y{}", arg);
        };
    };
    // pop local declarations off
    for(let local .. locals){
        for(let d = len(ctxt.scp.defs); d > 0; d -= 1){
            if(ctxt.scp.defs[d - 1] is *decl_meta){
                const decl = ctxt.scp.defs[d - 1] as *decl_meta;
                if(decl == local){
                    delete(ctxt.scp.defs[d - 1]);
                };
            };
        };
    };
    move_ptr(ctxt, ctxt.tokens[at]);
    ctxt.branching = old_branch;
    const exhaustive = len(conds) < len(bodies);
    if(comp_type(tpe, primitive::ANY) || !exhaustive) tpe = quick_t(primitive::UNIT);
    const out = alloc(branch_meta {
        pos = at,
        tpe = tpe,
        rets = rets && exhaustive,
        nested = ctxt.branching,
        conds = conds,
        bodies = bodies,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

fn eval_for_loop(ctxt: *context, at: size) ((*for_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, keyword::FOR));
    let end = at + 1;
    let tk = next_tk(ctxt, end,
        "expected %biteration variable%r or %blocal declaration%r, but got %y{}")?;
    let ref = tk;
    const mut =
        if(comp_tk(tk.val, keyword::MUT)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %biteration variable%r or %blocal declaration%r, but got %y{}")?;
            yield true;
        } else {
            yield false;
        };
    const defs: []*decl_meta = [];
    defer free(defs);
    let local_def: nullable *decl_meta = null;
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt,
            "expected %biteration variable%r or %blocal declaration%r, but got %y{}", arg);
    };
    const name = tk.val as namespace;
    // namespace not defined suggests an assignment
    tk = next_tk(ctxt, end + 1,
        "expected %bassignment%r or %brange operator%r, but got %y{}")?;
    // local variable
    if(comp_tk(tk.val, operator::ASG)){
        const (local, _end) = eval_var_def(ctxt, end)?;
        local.var.nm.mut = mut;
        local.var.nm.kind = nm_kind::VAR;
        mut = false;
        end = _end;
        end = pop_assert(ctxt, end, symbol::EOL,
            "expected %bend of line%r, but got %y{}")?;
        local_def = local;
        push_def(ctxt, tk, local.var.nm, local)?;
        append(defs, local)!;
    };
    tk = next_tk(ctxt, end,
        "expected %iteration variable%r, but got %y{}")?;
    if(comp_tk(tk.val, keyword::MUT)){
        ref = tk;
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %biteration variable%r or %blocal declaration%r, but got %y{}")?;
        mut = true;
    };
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt,
            "expected %iteration variable%r, but got %y{}", arg);
    };
    end += 1;
    check_shadowing(ctxt, tk, tk.val as namespace)?;
    const iteration = alloc(decl_meta {
        var = alloc(var_meta {
            nm = tk.val as namespace,
            pos = end,
            lifetime = void,
            allocated = false,
        })!,
        val = void,
    })!;
    append(allocd_nodes, iteration)!;
    append(allocd_nodes, iteration.var)!;
    iteration.var.nm.mut = mut;
    append(defs, iteration)!;

    tk = next_tk(ctxt, end,
        "expected %range operator%r or %bindex variable declaration%r, but got %y{}")?;
    
    let indx: nullable *decl_meta = null;
    if(comp_tk(tk.val, symbol::COMMA)){
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %bindex variable declaration%r, but got %y{}")?;
        if(!(tk.val is namespace)){
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %bindex variable declaration%r, but got %y{}", arg);
        };
        check_shadowing(ctxt, tk, tk.val as namespace)?;
        end += 1;
        indx = alloc(decl_meta {
            var = alloc(var_meta {
                nm = tk.val as namespace,
                pos = end,
                lifetime = void,
                allocated = false,
            })!,
            val = void,
        })!;
        const deff = indx as *decl_meta;
        append(allocd_nodes, deff)!;
        append(allocd_nodes, deff.var)!;
        deff.var.nm.tpe = quick_t(primitive::U64);
        append(defs, deff)!;
    };
    end = pop_assert(ctxt, end, operator::RANGE,
        "expected %brange operator%r, but got %y{}")?;

    const (iter, iter_t, item_t, _end) = fetch_iter(ctxt,
        end, ctxt.tokens[end], mut)?;
    iteration.var.nm.tpe = item_t;
    // save previous loop position state
    const old_loop_pos = ctxt.loop_pos;
    // update it
    ctxt.loop_pos = at;
    const (scope, _end) = eval_scope(ctxt, _end, defs)?;
    // restore it
    ctxt.loop_pos = old_loop_pos;
    // pop lock on iterator
    if(iter is *var_meta){
        delete(ctxt.iterating_on[len(ctxt.iterating_on) - 1]);
    };
    // fetch scope type and return state
    const (rets, tpe) = 
        if(scope.rets) (true, scope.tpe) 
        else (false, quick_t(primitive::UNIT));
    // pop local variable off
    if(local_def is *decl_meta){
        for(let d = len(ctxt.scp.defs); d > 0; d -= 1){
            if(ctxt.scp.defs[d - 1] is *decl_meta){
                const decl = ctxt.scp.defs[d - 1] as *decl_meta;
                if(decl == local_def as *decl_meta){
                    delete(ctxt.scp.defs[d - 1]);
                    break;
                };
            };
        };
    };
    end = _end;
    const out = alloc(for_meta {
        pos = at,
        mut = mut,
        tpe = tpe,
        rets = rets,
        indx = indx,
        local = local_def,
        iter = iter as iterator_t,
        iter_t = iter_t,
        item = iteration,
        body = scope,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

fn eval_while_loop(ctxt: *context, at: size) ((*while_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, keyword::WHILE));
    let end = at + 1;
    // assert for non-deterministic branching
    const host = ctxt.host_fun as *fun_meta;
    require_efx(ctxt, ctxt.tokens[at], host.effects, keyword::WHILE)?;
    let tk = next_tk(ctxt, end,
        "expected %belse block%r or %bend of line%r, but got %y{}")!;
    const mut =
        if(comp_tk(tk.val, keyword::MUT)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %biteration variable%r or %blocal declaration%r, but got %y{}")?;
            yield true;
        } else {
            yield false;
        };
    let local_def: nullable *decl_meta = null;
    // local variable
    if(tk.val is namespace){
        const name = tk.val as namespace;
        const decl = get_def(ctxt, name, ctxt.scp);
        // namespace not defined suggests an assignment
        if(decl is void){
            const (local, _end) = eval_var_def(ctxt, end)?;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            local.var.nm.mut = mut;
            local.var.nm.kind = nm_kind::VAR;
            push_def(ctxt, tk, local.var.nm, local)?;
            local_def = local;
        };
    };
    // eval while condition
    const (cond, _end) = eval_expression(ctxt, end,
        quick_t(primitive::BOOL))?;
    end = _end;
    // save previous loop position state
    const old_loop_pos = ctxt.loop_pos;
    // update it
    ctxt.loop_pos = at;
    const (body, _end) = eval_scope(ctxt, end)?;
    // restore it
    ctxt.loop_pos = old_loop_pos;
    // pop local variable off
    if(local_def is *decl_meta){
        for(let d = len(ctxt.scp.defs); d > 0; d -= 1){
            if(ctxt.scp.defs[d - 1] is *decl_meta){
                const decl = ctxt.scp.defs[d - 1] as *decl_meta;
                if(decl == local_def as *decl_meta){
                    delete(ctxt.scp.defs[d - 1]);
                    break;
                };
            };
        };
    };
    end = _end;
    const out = alloc(while_meta {
        pos = at,
        tpe = body.tpe,
        rets = body.rets,
        local = local_def,
        cond = cond,
        body = body,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

fn fetch_iter(
    ctxt: *context,
    at: size,
    ref: token,
    mut: bool = false,
    allow_item: bool = false,
) (((iterator_t | *member_meta), lichen_t, lichen_t, size) | ERROR) = {
    let end = at;
    let tk = next_tk(ctxt, end, "expected %biterator value%r, but got %y{}")?;
    if(comp_tk(tk.val, symbol::LFT_SQUARE)){
        if(mut){
            move_ptr(ctxt, ref);
            return error_hint(ctxt,
                "\n%gmarking an iteration variable as mutable "
                "marks it to reassign to the iteration array",
                "cannot %yreassign to array literal");
        };
        const (lit, end) = eval_array_lit(ctxt, end,
            quick_t(primitive::ANY))?;
        const item_t = unwrap_array(lit.tpe);
        return (lit, lit.tpe, item_t, end);
    } else {
        const (i, _end, invalid) = eval_member(ctxt, end,
            quick_t(primitive::ANY), quick_t(primitive::ANY))?;
        move_ptr(ctxt, ctxt.tokens[end]);
        if(invalid){
            const arg = strtoken(ctxt.tokens[_end].val);
            defer free(arg);
            return error(ctxt,
                "expected %biterator value%r, but got %y{}", arg);
        };
        const memb = i as *member_meta;
        if(!allow_item || memb.tpe.base is *array ||
            comp_type(memb.tpe, primitive::STR)){
            if(!(memb.tpe.base is *array) &&
                !comp_type(memb.tpe, primitive::STR)){
                const arg = strtype(memb.tpe);
                defer free(arg);
                return error(ctxt,
                    "expected valid %biterator%r, but its of %y{}", arg);
            };
            const (iter, tpe) =
                process_iter(ctxt, memb, ref, mut)?;
            return (iter, memb.tpe, tpe, _end);
        } else {
            return (memb, memb.tpe, memb.tpe, _end);
        };
    };
};

fn process_iter(
    ctxt: *context,
    iter: *member_meta,
    pos: token,
    mut: bool,
) ((iterator_t, lichen_t) | ERROR) = {
    move_ptr(ctxt, pos);
    if(iter.tpe.partial){
        const arg = strtype(iter.tpe);
        defer free(arg);
        return error(ctxt, "cannot iterate over {}", arg);
    };
    match(iter.val){
    case let var: *var_meta =>
        if(mut && !var.nm.mut){
            return error_hint(ctxt,
                "\n%gmarking an iteration variable as mutable "
                "marks it to reassign to the iteration array",
                "iterator variable is not mutable");
        };
        append(ctxt.iterating_on, var)!;
        return (var, unwrap_array(var.nm.tpe));
    case let call: *funcall_meta =>
        if(mut){
            return error_hint(ctxt,
                "\n%gmarking an iteration variable as mutable "
                "marks it to reassign to the iteration array",
                "cannot %yreassign to array literal");
        };
        return (call, unwrap_array(call.tpe));
    case let lit: *array_lit_meta =>
        if(mut){
            return error_hint(ctxt,
                "\n%gmarking an iteration variable as mutable "
                "marks it to reassign to the iteration array",
                "cannot %yreassign to array literal");
        };
        return (lit, unwrap_array(lit.tpe));
    case let index: *indexing_meta =>
        const base =
            if(index.base is null) {
                yield match(index.before){
                case let field: *field_meta =>
                    yield field.base as *member_meta;
                case let idx: *indexing_meta =>
                    yield idx.base as *member_meta;
                case let slc: *slicing_meta =>
                    yield slc.base as *member_meta;
                case void =>
                    fmt::fatal("unreachable");
                };
            } else {
                yield index.base as *member_meta;
            };
        if(mut){
            if(base.val is *var_meta){
                const var = base.val as *var_meta;
                if(!var.nm.mut){
                    return error_hint(ctxt,
                        "\n%gmarking an iteration variable as mutable "
                        "marks it to reassign to the iteration array",
                        "iterator variable is not mutable");
                };
            } else {
                return error_hint(ctxt,
                    "\n%gmarking an iteration variable as mutable "
                    "marks it to reassign to the iteration array",
                    "cannot %yreassign to array literal");
            };
        };
        return (index, unwrap_array(index.tpe));
    case let slice: *slicing_meta =>
        const base =
            if(slice.base is null) {
                yield match(slice.before){
                case let fld: *field_meta =>
                    yield fld.base as *member_meta;
                case let idx: *indexing_meta =>
                    yield idx.base as *member_meta;
                case let slc: *slicing_meta =>
                    yield slc.base as *member_meta;
                case void =>
                    fmt::fatal("unreachable");
                };
            } else {
                yield slice.base as *member_meta;
            };
        if(mut){
            if(base.val is *var_meta){
                const var = base.val as *var_meta;
                if(!var.nm.mut){
                    return error_hint(ctxt,
                        "\n%gmarking an iteration variable as mutable "
                        "marks it to reassign to the iteration array",
                        "iterator variable is not mutable");
                };
            } else {
                return error_hint(ctxt,
                    "\n%gmarking an iteration variable as mutable "
                    "marks it to reassign to the iteration array",
                    "cannot %yreassign to array literal");
            };
        };
        return (slice, unwrap_array(slice.tpe));
    case let field: *field_meta =>
        const base =
            if(field.base is null) {
                yield match(field.before){
                case let fld: *field_meta =>
                    yield fld.base as *member_meta;
                case let idx: *indexing_meta =>
                    yield idx.base as *member_meta;
                case let slc: *slicing_meta =>
                    yield slc.base as *member_meta;
                case void =>
                    fmt::fatal("unreachable");
                };
            } else {
                yield field.base as *member_meta;
            };
        if(mut){
            if(base.val is *var_meta){
                const var = base.val as *var_meta;
                if(!var.nm.mut){
                    return error_hint(ctxt,
                        "\n%gmarking an iteration variable as mutable "
                        "marks it to reassign to the iteration array",
                        "iterator variable is not mutable");
                };
            } else {
                return error_hint(ctxt,
                    "\n%gmarking an iteration variable as mutable "
                    "marks it to reassign to the iteration array",
                    "cannot %yreassign to array literal");
            };
        };
        return (field, unwrap_array(field.tpe));
    case let all: *alloc_meta =>
        if(mut){
            return error_hint(ctxt,
                "\n%gmarking an iteration variable as mutable "
                "marks it to reassign to the iteration array",
                "cannot %yreassign to array literal");
        };
        return (all, unwrap_array(all.tpe));
    case let lit: *const_meta =>
        if(mut){
            return error_hint(ctxt,
                "\n%gmarking an iteration variable as mutable "
                "marks it to reassign to the iteration array",
                "cannot %yreassign to string literal");
        };
        return (lit, unwrap_array(iter.tpe));
    };
};

fn eval_switch(ctxt: *context, at: size) ((*switch_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, keyword::SWITCH));
    let end = at + 1;
    let tk = next_tk(ctxt, end,
        "expected %bswitch item%r or %blocal variable%r, but got %y{}")?;
    const mut =
        if(comp_tk(tk.val, keyword::MUT)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %biteration variable%r or %blocal declaration%r, but got %y{}")?;
            yield true;
        } else {
            yield false;
        };
    let local_def: nullable *decl_meta = null;
    // local variable
    if(tk.val is namespace){
        const name = tk.val as namespace;
        const decl = get_def(ctxt, name, ctxt.scp);
        // namespace not defined suggests an assignment
        if(decl is void){
            const (local, _end) = eval_var_def(ctxt, end)?;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            local.var.nm.mut = mut;
            local.var.nm.kind = nm_kind::VAR;
            push_def(ctxt, tk, local.var.nm, local)?;
            local_def = local;
        };
    };
    const (check, _end) = eval_expression(ctxt, end, quick_t(primitive::ANY))?;
    if(check.tpe.partial){
        move_ptr(ctxt, ctxt.tokens[end]);
        return error(ctxt, "cannot switch on partial types");
    };
    end = pop_assert(ctxt, _end, symbol::EOL,
        "expected %bend of line%r, but got %y{}")?;

    let cases: []switch_case = [];
    let case_lits: [](*const_meta, token) = [];
    let exhaustive = false;
    let rets = false;
    let tpe = quick_t(primitive::ANY);
    let else_case: (void | size) = void;
    tk = next_tk(ctxt, end, "expected %bswitch branch%r, but got %y{}")?;
    // TODO: assert for duplicate cases within ranges
    for(comp_tk(tk.val, operator::BOR)){
        end += 1;
        const consts: []*const_meta = [];
        let op: (operator | void) = void;
        tk = next_tk(ctxt, end,
            "expected %bconstant%r or %belse case%r, but got %y{}")?;
        // else case
        if(comp_tk(tk.val, keyword::ELSE)){
            if(else_case is size){
                move_ptr(ctxt, tk);
                return error(ctxt, "%belse%r case defined multiple times");
            };
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bdo keyword%r or %bscope definition%r, but got %y{}")?;
            // single statement
            if(comp_tk(tk.val, keyword::DO)){
                end = pop_assert(ctxt, end, keyword::DO,
                    "expected %bdo keyword%r, but got %y{}")?;
                // parse case statement
                const (stt, _end) = eval_statement(ctxt, end)?;
                // assert for invalid statements
                if(stt is *decl_meta){
                    move_ptr(ctxt, ctxt.tokens[end]);
                    return error(ctxt, "cannot conditionally declare variables");
                };
                // assert for returns
                const (_tpe, _, _rets) = assert_ret_state(ctxt,
                    ctxt.tokens[end], stt,
                    ctxt.host_fun as *fun_meta, tpe, rets)?;
                if(!_rets){
                    if(!is_terminal(_tpe)) rets = false;
                } else {
                    assert_hint(ctxt, ctxt.tokens[end], tpe, _tpe)?;
                    tpe = _tpe;
                    rets = true;
                };
                end = _end;
                append(cases, (void, void, stt): switch_case)!;
            // scope
            } else if(comp_tk(tk.val, symbol::LFT_CURLY)){
                const (body, _end) = eval_scope(ctxt, end)?;
                end = pop_assert(ctxt, _end, symbol::EOL,
                    "expected %bend of line%r, but got %y{}")?;
                if(!body.rets){
                    if(!is_terminal(body.tpe)) rets = false;
                } else {
                    assert_hint(ctxt, ctxt.tokens[body.pos], tpe, body.tpe)?;
                    tpe = body.tpe;
                    rets = true;
                };
                append(cases, (void, void, body): switch_case)!;
            } else {
                move_ptr(ctxt, tk);
                const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %bdo keyword%r or %bscope definition%r, but got %y{}", arg);
            };
            else_case = len(cases) - 1;
            exhaustive = true;
            tk = next_tk(ctxt, end,
                "expected %bnext switch branch%r, but got %y{}")?;
            continue;
        };
        const (c, _end) = eval_constant(ctxt, end, check.tpe)?;
        // assert for duplicated cases
        for(let cnst .. case_lits){
            if(comp_tk(cnst.0.val, c.val)){
                move_ptr(ctxt, cnst.1);
                const pos = gen_pos(ctxt);
                defer free(pos);
                move_ptr(ctxt, ctxt.tokens[end]);
                const hint = fmt::asprintf("\n%gsimilar case at {}", pos)!;
                defer free(hint);
                return error_hint(ctxt, hint, "duplicated switch case");
            };
        };
        append(consts, c)!;
        append(case_lits, (c, ctxt.tokens[end]))!;
        end = _end;
        tk = next_tk(ctxt, end,
            "expected %brange operator%r, %bcomma%r, %bdo keyword%r or %bscope definition%r, but got %y{}")?;
        // range operator
        if(comp_tk(tk.val, operator::RANGE)){
            if(!is_subtype(check.tpe, primitive::I64) &&
                !is_subtype(check.tpe, primitive::U64)){
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "cannot apply range intervals to non-integer values");
            };
            op = tk.val as operator;
            const (c_end, _end) = eval_constant(ctxt, end + 1, check.tpe)?;
            for(let cnst .. case_lits){
                if(comp_tk(cnst.0.val, c_end.val)){
                    move_ptr(ctxt, cnst.1);
                    const pos = gen_pos(ctxt);
                    defer free(pos);
                    move_ptr(ctxt, ctxt.tokens[end]);
                    const hint = fmt::asprintf("\n%gsimilar case at {}", pos)!;
                    defer free(hint);
                    return error_hint(ctxt, hint, "duplicated switch case");
                };
            };
            append(consts, c_end)!;
            append(case_lits, (c_end, ctxt.tokens[end]))!;
            end = _end;
            tk = next_tk(ctxt, end,
                "expected %bdo keyword%r or %bscope definition%r, but got %y{}")?;
        // open range
        } else if(comp_tk(tk.val, operator::SPREAD)){
            if(!is_subtype(check.tpe, primitive::I64) &&
                !is_subtype(check.tpe, primitive::U64)){
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "cannot apply range intervals to non-integer values");
            };
            op = tk.val as operator;
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bdo keyword%r or %bscope definition%r, but got %y{}")?;
        // set of constants
        } else if(comp_tk(tk.val, symbol::COMMA)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bnext constant%r, %bdo keyword%r or %bscope definition%r, but got %y{}")?;
            for(!comp_tk(tk.val, symbol::LFT_CURLY) &&
                !comp_tk(tk.val, keyword::DO)){
                const (othr_c, _end) = eval_constant(ctxt, end, check.tpe)?;
                for(let cnst .. case_lits){
                    if(comp_tk(cnst.0.val, othr_c.val)){
                        move_ptr(ctxt, cnst.1);
                        const pos = gen_pos(ctxt);
                        defer free(pos);
                        move_ptr(ctxt, ctxt.tokens[end]);
                        const hint =
                            fmt::asprintf("\n%gsimilar case at {}", pos)!;
                        defer free(hint);
                        return error_hint(ctxt, hint,
                            "duplicated switch case");
                    };
                };
                append(case_lits, (othr_c, ctxt.tokens[end]))!;
                append(consts, othr_c)!;
                end = _end;
                tk = next_tk(ctxt, end,
                    "expected %bcomma%r, %bdo keyword%r or %bscope definition%r, but got %y{}")?;
                if(comp_tk(tk.val, symbol::COMMA)){
                    end += 1;
                    tk = next_tk(ctxt, end,
                        "expected %bnext constant%r, %bdo keyword%r or %bscope definition%r, but got %y{}")?;
                } else if(comp_tk(tk.val, operator::SPREAD)){
                    if(!is_subtype(check.tpe, primitive::I64)&&
                        !is_subtype(check.tpe, primitive::U64)){
                        move_ptr(ctxt, tk);
                        return error(ctxt,
                            "cannot apply range intervals to non-integer values");
                    };
                    op = tk.val as operator;
                    end += 1;
                    tk = next_tk(ctxt, end,
                        "expected %bdo keyword%r or %bscope definition%r, but got %y{}")?;
                } else if(!comp_tk(tk.val, symbol::LFT_CURLY) &&
                    !comp_tk(tk.val, keyword::DO)){
                    move_ptr(ctxt, tk);
                    const arg = strtoken(tk.val);
                    defer free(arg);
                    return error(ctxt,
                        "expected %bdo keyword%r or %bscope definition%r, but got %y{}", arg);
                };
            };
            tk = next_tk(ctxt, end,
                "expected %bdo keyword%r or %bscope definition%r, but got %y{}")?;
        };
        // single statement
        if(comp_tk(tk.val, keyword::DO)){
            // parse case statement
            const (stt, _end) = eval_statement(ctxt, end + 1)?;
            // assert for invalid statements
            if(stt is *decl_meta){
                move_ptr(ctxt, ctxt.tokens[end + 1]);
                return error(ctxt, "cannot conditionally declare variables");
            };
            // assert for returns
            const (_tpe, _, _rets) = assert_ret_state(ctxt, 
                ctxt.tokens[end + 1], stt,
                ctxt.host_fun as *fun_meta, tpe, rets)?;
            if(!_rets){
                if(!is_terminal(_tpe)) rets = false;
            } else {
                assert_hint(ctxt, ctxt.tokens[end], tpe, _tpe)?;
                tpe = _tpe;
                rets = true;
            };
            end = _end;
            append(cases, (consts, op, stt): switch_case)!;
        // scope
        } else if(comp_tk(tk.val, symbol::LFT_CURLY)){
            const (body, _end) = eval_scope(ctxt, end)?;
            end = pop_assert(ctxt, _end, symbol::EOL,
                "expected %bend of line%r, but got %y{}")?;
            if(!body.rets){
                if(!is_terminal(body.tpe)) rets = false;
            } else {
                assert_hint(ctxt, ctxt.tokens[body.pos], tpe, body.tpe)?;
                tpe = body.tpe;
                rets = false;
            };
            append(cases, (consts, op, body): switch_case)!;
        } else {
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %bdo keyword%r or %bscope definition%r, but got %y{}", arg);
        };
        tk = next_tk(ctxt, end,
            "expected %bnext switch branch%r, but got %y{}")?;
    };
    if(len(cases) == 0 || !exhaustive){
        move_ptr(ctxt, ctxt.tokens[at]);
        return error(ctxt, "switch block %yis not exhaustive");
    };
    if(comp_type(tpe, primitive::ANY) || !rets){
        tpe = quick_t(primitive::UNIT);
    };
    // pop local variable off
    if(local_def is *decl_meta){
        for(let d = len(ctxt.scp.defs); d > 0; d -= 1){
            if(ctxt.scp.defs[d - 1] is *decl_meta){
                const decl = ctxt.scp.defs[d - 1] as *decl_meta;
                if(decl == local_def as *decl_meta){
                    delete(ctxt.scp.defs[d - 1]);
                    break;
                };
            };
        };
    };
    const out = alloc(switch_meta {
        pos = at,
        tpe = tpe,
        rets = rets,
        local = local_def,
        cases = cases,
        check = check,
        else_case = else_case,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

fn eval_expression(
    ctxt: *context,
    at: size,
    hint: lichen_t,
    ternary: bool = false,
) ((*expr_meta, size) | ERROR) = {
    const (exp, end) = eval_asg_or_exp(ctxt, at, hint, false, ternary)?;
    return (exp as *expr_meta, end);
};

// evaluates an expression of members and operators or an assignment
fn eval_asg_or_exp(
    ctxt: *context,
    at: size,
    hint: lichen_t,
    allow_asg: bool = false,
    ternary: bool = false,
) (((*expr_meta | *assign_meta), size) | ERROR) = {
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
    // field assignment
    if(comp_tk(tk.val, operator::ASG)){
        move_ptr(ctxt, tk);
        const begin = _end;
        if(left is *expr_meta){
            return error_hint(ctxt,
                "\n%gcannot assign to expresison",
                "unexpected %yassignment%r found here");
        };
        const dest = left as *member_meta;
        if(!allow_asg){
            const root =
                if(dest.val is chain_exp_t){
                    const chain = dest.val as chain_exp_t;
                    const base = extract_base_from_chain(ctxt, chain)!;
                    yield extract_previous_base(base).val;
                } else {
                    yield dest.val;
                };
            if(root is *record_lit_meta || root is *field_meta){
                if(root is *field_meta){
                    const field = root as *field_meta;
                    if(field.prop is propagation){
                        return error_hint(ctxt,
                            "\n%gcannot assign to fallback expression",
                            "unexpected %yassignment%r found here");
                    };
                };
                return error_hint(ctxt,
                    "\n%gcannot assign to a record literal",
                    "unexpected %yassignment%r found here");
            } else if(root is *array_lit_meta || root is *indexing_meta){
                if(root is *indexing_meta){
                    const index = root as *indexing_meta;
                    if(index.prop is propagation){
                        return error_hint(ctxt,
                            "\n%gcannot assign to fallback expression",
                            "unexpected %yassignment%r found here");
                    };
                };
                return error_hint(ctxt,
                    "\n%gcannot assign to an array literal",
                    "unexpected %yassignment%r found here");
            } else {
                return error(ctxt,
                    "unexpected %yassignment%r found here");
            };
        };
        const (val, finish) = eval_expression(ctxt, _end + 1, dest.tpe)?;
        end = finish;
        const obj = dest.val as chain_exp_t;
        let root = extract_base_from_chain(ctxt, obj, true)?;
        const base =
            match(root){
            case let idx: *indexing_meta =>
                yield idx.base as *member_meta;
            case let fld: *field_meta =>
                yield fld.base as *member_meta;
            case let slc: *slicing_meta =>
                yield slc.base as *member_meta;
            };
        if(base.val is *var_meta){
            const var = base.val as *var_meta;
            if(!var.nm.mut){
                if(var.nm.tpe.base is *record){
                    return error(ctxt,
                        "cannot %breassign to immutable%r record %y{}",
                        var.nm.name);
                } else if(var.nm.tpe.base is *array){
                    return error(ctxt,
                        "cannot %breassign to immutable%r array %y{}",
                        var.nm.name);
                };
            };
        } else if(base.val is *record_lit_meta){
            return error_hint(ctxt,
                "\n%gcannot assign to a record literal",
                "unexpected %yassignment%r found here");
        } else if(base.val is *array_lit_meta){
            return error_hint(ctxt,
                "\n%gcannot assign to an array literal",
                "unexpected %yassignment%r found here");
        } else {
            return error(ctxt,
                "unexpected %yassignment%r found here");
        };
        // assert mutability
        move_ptr(ctxt, ctxt.tokens[begin]);
        match(obj){
        case *slicing_meta => assert(false);
        case let field: *field_meta =>
            if(field.base is null) {
                match(field.before){
                case let fld: *field_meta =>
                    const memb = fld.base as *member_meta;
                    if(!(memb.val is *var_meta)){
                        return error(ctxt, "invalid assignment");
                    };
                case let idx: *indexing_meta =>
                    const memb = idx.base as *member_meta;
                    if(!(memb.val is *var_meta)){
                        return error(ctxt, "invalid assignment");
                    };
                case let slc: *slicing_meta =>
                    const memb = slc.base as *member_meta;
                    if(!(memb.val is *var_meta)){
                        return error(ctxt, "invalid assignment");
                    };
                case void =>
                    fmt::fatal("unreachable");
                };
            } else {
                const memb = field.base as *member_meta;
                if(!(memb.val is *var_meta)){
                    return error(ctxt, "invalid assignment");
                };
            };
            if(!field.field.var.nm.mut){
                return error(ctxt,
                    "field %b{}%r is %yimmutable",
                    field.field.var.nm.name);
            };
            assert_mutability(ctxt, ctxt.tokens[begin],
                field.field.var.nm.name,
                field.field.var.nm.mut, val)?;
            // assert underliving data
            if(val.val is *member_meta){
                const pass = base.val as *var_meta;
                const memb = val.val as *member_meta;
                const lifetime = match(memb.val){
                    case let var: *var_meta => yield var.lifetime;
                    case let all: *alloc_meta => yield all.arena.lifetime;
                    case let cat: *concat_meta => yield cat.arena.lifetime;
                    case => yield void;
                    };
                if(lifetime is size){
                    if(!(pass.lifetime is size)){
                        const hint =
                            fmt::asprintf("\n%gthe variable %y{}%g was not"
                            " dynamically allocated, it may outlive its"
                            " allocated value", pass.nm.name)!;
                        defer free(hint);
                        return error_hint(ctxt, hint,
                            "cannot assign %ballocated value%r to field of variable with %yno lifetime");
                    } else if(lifetime as size > pass.lifetime as size){
                        return error(ctxt,
                            "assigned value underlives variable %b{}%r's lifetime",
                            pass.nm.name);
                    };
                    if(pass.nm.kind == nm_kind::PARAM){
                        return error_hint(ctxt,
                            "the receiver is a parameter with no fixed lifetime",
                            "cannot assign %ballocated value%r to field of variable with %yundefined lifetime");
                    };
                };
            };
            const asg = alloc(assign_meta {
                pos = at,
                var = field.field.var,
                val = val,
                host = obj,
            })!;
            append(allocd_nodes, asg)!;
            return (asg, end);
        case let index: *indexing_meta =>
            if(index.tpe.partial){
                return error_hint(ctxt,
                    "\n%gtry asserting or bubbling the "
                    "indexing before assigning to it",
                    "invalid unsafe array item reassignment");
            };
            const pass =
                if(index.base is null) {
                    yield match(index.before){
                    case let fld: *field_meta =>
                        yield fld.field.var;
                    case let idx: *indexing_meta =>
                        const memb = extract_previous_base(idx);
                        if(!(memb.val is *var_meta)){
                            return error(ctxt, "invalid assignment");
                        };
                        yield memb.val as *var_meta;
                    case let slc: *slicing_meta =>
                        const memb = extract_previous_base(slc);
                        if(!(memb.val is *var_meta)){
                            return error(ctxt, "invalid assignment");
                        };
                        yield memb.val as *var_meta;
                    case void =>
                        fmt::fatal("unreachable");
                    };
                } else {
                    const memb = index.base as *member_meta;
                    if(!(memb.val is *var_meta)){
                        return error(ctxt, "invalid assignment");
                    };
                    yield memb.val as *var_meta;
                };
            if(!pass.nm.mut){
                return error(ctxt,
                    "cannot reassign %yimmutable array {}",
                    pass.nm.name);
            };
            assert_mutability(ctxt, ctxt.tokens[begin],
                pass.nm.name, pass.nm.mut, val)?;
            // assert underliving data
            if(val.val is *member_meta){
                const memb = val.val as *member_meta;
                const lifetime = match(memb.val){
                    case let var: *var_meta => yield var.lifetime;
                    case let all: *alloc_meta => yield all.arena.lifetime;
                    case let cat: *concat_meta => yield cat.arena.lifetime;
                    case => yield void;
                    };
                if(lifetime is size){
                    if(!(pass.lifetime is size)){
                        const hint =
                            fmt::asprintf("\n%gthe variable %y{}%g was not"
                            " dynamically allocated, it may outlive its"
                            " allocated value", pass.nm.name)!;
                        defer free(hint);
                        return error_hint(ctxt, hint,
                            "cannot assign %ballocated value%r to array with %yno lifetime");
                    } else if(lifetime as size > pass.lifetime as size){
                        return error(ctxt,
                            "assigned value underlives variable %b{}%r's lifetime",
                            pass.nm.name);
                    };
                    if(pass.nm.kind == nm_kind::PARAM){
                        return error_hint(ctxt,
                            "the receiver is a parameter with no fixed lifetime",
                            "cannot assign %ballocated value%r to array with %yundefined lifetime");
                    };
                };
            };
            const asg = alloc(assign_meta {
                pos = at,
                var = pass,
                val = val,
                host = obj,
            })!;
            append(allocd_nodes, asg)!;
            return (asg, end);
        };
    };
    // ternary operator
    if(comp_tk(tk.val, keyword::IF) && _end != end){
        free(members);
        const (ternary, finish) = eval_ternary(ctxt, _end, end,
            left as (*member_meta | *expr_meta))?;
        return (ternary, finish);
    };
    let first_t = hint;
    match(left){
    case let exp: *expr_meta =>
        first_t = exp.tpe;
        append(members, exp)!;
    case let memb: *member_meta =>
        first_t = memb.tpe;
        append(members, memb)!;
    case void => assert(false, "unreachable");
    };
    end = _end;
    tk = next_tk(ctxt, end,
        "expected %bexpression member%r, but got %y{}")?;
    let single = true;
    // keep iterating while there's an operator at the right of the member
    for(tk.val is operator){
        single = false;
        const oper = tk.val as operator;
        if(!is_binary_op(oper)){
            // halt on invalid state
            if(comp_tk(oper, operator::RANGE) ||
                comp_tk(oper, operator::SPREAD)) break;
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
            const (ternary, finish) = eval_ternary(ctxt, _end, end, hand)?;
            return (ternary, finish);
        };
        end = _end;
        // break if encountered an invalid path
        if(invalid) break;
        // fetch potential next operator
        tk = next_tk(ctxt, end,
            "expected %bexpression member%r, but got %y{}")?;
    };
    let (val, tpe): (hand_t, lichen_t) =
        if(!single){
            yield reduce_members(ctxt, at, members)?;
        } else {
            free(members);
            yield (left as (*member_meta | *expr_meta), first_t);
        };
    // assign a possible less-untyped type
    if(untyped(tpe) && !comp_type(hint, primitive::ANY) &&
        is_subtype(tpe, hint) && is_subtype(hint, tpe)){
        tpe = hint;
    };
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
    append(allocd_nodes, out)!;
    return (out, end);
};

// parses down a list of expression members to a hand, a member or an
// expression abstraction
fn reduce_members(
    ctxt: *context,
    pos: size,
    members: [](hand_t | operator),
) ((hand_t, lichen_t) | ERROR) = {
    if(len(members) > 1){
        let fix_overlap = 0z;
        for(let pre = 4z; pre > 0; pre -= 1){
            for(let o = 1z; o < len(members); o += 2){
                const oper = members[o] as operator;
                if(get_op_precedence(oper) == pre){
                    const h_pos = pos + o + fix_overlap;
                    fix_overlap += 1;

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
                    const hand = alloc(hand_meta {
                        pos = h_pos,
                        tpe = reduce_exp_t(oper, lft_t, rgt_t),
                        lft = lft_h,
                        opr = oper,
                        rgt = rgt_h,
                    })!;
                    append(allocd_nodes, hand)!;
                    // remove consumed members
                    delete(members[(o - 1)..(o + 2)]);
                    // if it's not the final iteration 
                    if(len(members) > 0){
                        insert(members[o - 1], hand)!;
                        o -= 2;
                    } else {
                        free(members);
                        return (hand, hand.tpe);
                    };
                };
            };
        };
    };
    defer free(members);
    return (members[0] as hand_t, extract_hand_type(members[0] as hand_t));
};

// fetches the a given operator's precedence
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
    const memb = member_meta {
        pos = at,
        tpe = quick_t(primitive::ANY),
        pre = void,
        val = void,
        prop = void,
    };
    let singleton = false;
    match(tk.val){
    case let sym: symbol =>
        switch(sym){
        case symbol::LFT_PAR =>
            const (exp, _end) = eval_expression(ctxt, at + 1,
                quick_t(primitive::ANY))?;

            end = pop_assert(ctxt, _end, symbol::RGT_PAR,
                "expected %bclosing parenthesis%r, but got %y{}")?;
            if(exp.val is *member_meta){
                memb.tpe = exp.tpe;
                memb.val = (exp.val as *member_meta).val;
            } else {
                // assert for a potential casting
                const (tpe, prop, _end) = eval_cast(ctxt, exp.tpe, end)?;
                exp.tpe = tpe;
                exp.prop = prop;
                end = _end;
                return (exp, end, false);
            };
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
            assert_unary(ctxt, at, oper, m.tpe)?;
            m.pre = oper;
            if(oper == operator::LENGTH){
                m.tpe = quick_t(primitive::U64);
            };
        case let e: *expr_meta =>
            assert_unary(ctxt, at, oper, e.tpe)?;
            e.pre = oper;
            if(oper == operator::LENGTH){
                e.tpe = quick_t(primitive::U64);
            };
        case void =>
            return (res, end, inv);
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
        singleton = true;
        switch(kwd){
        case keyword::TRUE =>
            memb.tpe = quick_t(primitive::BOOL);
            memb.val = kwd;
            end = at + 1;
        case keyword::FALSE =>
            memb.tpe = quick_t(primitive::BOOL);
            memb.val = kwd;
            end = at + 1;
        case keyword::ERROR, keyword::NIL =>
            if(untyped(possible)){
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "value %b{}%r not assignable to %yuntyped expression",
                    kwd_value[kwd]);
            };
            end = at + 1;
            memb.tpe = possible;
            memb.tpe.partial = true;
            memb.val = kwd;
        case keyword::NEW =>
            const (all, _end) = eval_alloc(ctxt, at, possible)?;
            end = _end;
            memb.tpe = all.tpe;
            memb.val = all;
        case keyword::CAT =>
            const (cat, _end) = eval_concat(ctxt, at, possible)?;
            end = _end;
            memb.tpe = cat.tpe;
            memb.val = cat;
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
                end += 1;
                fun_def.used = true;
                const fnptr = alloc(fun_ptr {  // TODO: store this for cleanup
                    params = [],
                    returns = fun_def.fun.tpe,
                    efxtags = fun_def.efxtags,
                    effects = fun_def.effects,
                })!;
                for(let param .. fun_def.params){
                    append(fnptr.params,
                        (param.var.nm.mut, param.var.nm.tpe))!;
                };
                memb.tpe = lichen_t {
                    partial = false,
                    base = fnptr,
                };
                memb.val = alloc(fn_ptr_meta {
                    points_to = fun_def,
                })!;
                append(allocd_nodes, memb.val as *fn_ptr_meta)!;
            };
        case let decl: *decl_meta =>
            if(decl.var.nm.ffi is str){
                const host = ctxt.host_fun as *fun_meta;
                if(host.effects is void){
                    return error_hint(ctxt,
                        "\n%gFFI symbols are impure by definition",
                        "pure functions cannot interact FFI variables");
                };
                if(host.effects is *effect_t){
                    const efx = host.effects as *effect_t;
                    let found = false;
                    for(let ffi .. efx.ffis){
                        if(ffi.var.nm.ffi as str == decl.var.nm.ffi as str){
                            found = true;
                            break;
                        };
                    };
                    if(!found){
                        return error_hint(ctxt,
                            "\n%gFFI symbols are impure by definition",
                            "the function %b{}%r is trying to interact with the FFI variable %y{}%r, but it has no effect tag describing it",
                            host.fun.name, decl.var.nm.name);
                    };
                };
            };
            memb.tpe = decl.var.nm.tpe;
            const dup = alloc(*decl.var)!;
            memb.val = dup;
            append(allocd_nodes, dup)!;
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
            case let enu: *enum_t =>
                todo("enum field access");
            case =>
                move_ptr(ctxt, tk);
                const arg = strtype(tpe.self);
                defer free(arg);
                return error(ctxt,
                    "type %b{}%r cannot be used as a %yliteral", arg);
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
                            end += 1;
                            fun_def.used = true;
                            const fnptr = alloc(fun_ptr {  // TODO: store this for cleanup
                                params = [],
                                returns = fun_def.fun.tpe,
                                efxtags = fun_def.efxtags,
                                effects = fun_def.effects,
                            })!;
                            for(let param .. fun_def.params){
                                append(fnptr.params,
                                    (param.var.nm.mut, param.var.nm.tpe))!;
                            };
                            memb.tpe = lichen_t {
                                partial = false,
                                base = fnptr,
                            };
                            memb.val = alloc(fn_ptr_meta {
                                points_to = fun_def,
                            })!;
                            append(allocd_nodes, memb.val as *fn_ptr_meta)!;
                        };
                    case let decl: *decl_meta =>
                        if(decl.var.nm.name != field.name){
                            continue;
                        };
                        if(!decl.var.nm.pub){
                            return error(ctxt,
                                "the variable %b{}::{}%r exists, but it's %ynot public",
                                module.name, decl.var.nm.name);
                        };
                        memb.tpe = decl.var.nm.tpe;
                        const dup = alloc(*decl.var)!;
                        memb.val = dup;
                        append(allocd_nodes, dup)!;
                        found = true;
                        tk = next_tk(ctxt, end,
                            "expected %bexpression continuation%r or %bend of line%r, but got %y{}")?;
                        if(comp_tk(tk.val, symbol::LFT_PAR)){
                            move_ptr(ctxt, tk);
                            return error(ctxt, "attempt to call on non-function namespace %b{}",
                                decl.var.nm.name);
                        };
                    case let tpe: *type_meta =>
                        if(tpe.name.name != field.name){
                            continue;
                        };
                        if(!tpe.pub){
                            return error(ctxt,
                                "the type %b{}::{}%r exists, but it's %ynot public",
                                module.name, tpe.name.name);
                        };
                        found = true;
                        memb.tpe = tpe.self;
                        match(tpe.self.base){
                        case let rec: *record =>
                            const (lit, _end) = eval_record_lit(ctxt, end - 1, tpe.self)?;
                            end = _end;
                            memb.val = lit;
                        case let enu: *enum_t =>
                            todo("enum field access");
                        case =>
                            move_ptr(ctxt, tk);
                            const arg = strtype(tpe.self);
                            defer free(arg);
                            return error(ctxt,
                                "type %b{}::{}%r cannot be used as a %yliteral",
                                module.name, arg);
                        };
                    case let submodule: *module_meta =>
                        if(submodule.name != field.name){
                            continue;
                        };
                        todo("recursive modules");
                    case let effect: *effect_t =>
                        if(effect.name != field.name){
                            continue;
                        };
                        move_ptr(ctxt, tk);
                        return error(ctxt,
                            "effect %b{}::{}%r cannot be used as a %yliteral",
                            module.name, effect.name);
                    };
                };
                if(!found){
                    return error(ctxt,
                        "no field named %b{}%r is defined on %b{}",
                        field.name, module.name);
                };
            } else {
                move_ptr(ctxt, tk);
                const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %bmodule field access%r, but got %y{}", arg);
            };
        case =>
            // fetch missing symbol possible hint
            const hint =
                if(comp_tk(ctxt.tokens[end + 1].val, symbol::FIELD)){
                    yield fmt::asprintf(
                        "\n%gtry using:\n\n"
                        "\t%d{0} mod = use \"std/{0}.lim\";\n"
                        "\n%gat global scope", nm.name)!;
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
    if(singleton && prop is propagation){
        move_ptr(ctxt, ctxt.tokens[end]);
        return error(ctxt, "cannot assert on literals");
    };
    memb.tpe = tpe;
    memb.prop = prop;
    assert(!comp_type(memb.tpe, primitive::ANY));
    const out = alloc(memb)!;
    append(allocd_nodes, out)!;

    end = eval_fields_and_indexes(ctxt, out, _end)?;
    assert_hint(ctxt, tk, out.tpe, hint)?;

    return (out, end, false);
};

fn extract_base_from_chain(
    ctxt: *context,
    obj: chain_exp_t,
    assignment: bool = false,
) (chain_exp_t | ERROR) = {
    let root = match(obj){
        case let idx: *indexing_meta =>
            yield if(idx.before is void){
                yield idx;
            } else {
                yield idx.before;
            };
        case let fld: *field_meta =>
            yield if(fld.before is void){
                yield fld;
            } else {
                yield fld.before;
            };
        case let slc: *slicing_meta =>
            if(assignment){
                return error(ctxt, "cannot assign to %yslicing literal");
            };
            yield if(slc.before is void){
                yield slc;
            } else {
                yield slc.before;
            };
        };
    for(true){
        match(root){
        case let idx: *indexing_meta =>
            if(idx.before is void) break;
            root = idx.before;
        case let fld: *field_meta =>
            if(fld.before is void) break;
            root = fld.before;
        case let slc: *slicing_meta =>
            if(slc.before is void) break;
            root = slc.before;
        };
    };
    return root as chain_exp_t;
};

fn extract_previous_base(obj: chain_exp_t) *member_meta = {
    match(obj){
    case let field: *field_meta =>
        const base = field.base;
        const before = field.before;
        for(base is null){
            match(before as chain_exp_t){
            case let fld: *field_meta =>
                base = fld.base;
                before = fld.before;
            case let idx: *indexing_meta =>
                base = idx.base;
                before = idx.before;
            case let slc: *slicing_meta =>
                base = slc.base;
                before = slc.before;
            };
        };
        return base as *member_meta;
    case let index: *indexing_meta =>
        const base = index.base;
        const before = index.before;
        for(base is null){
            match(before as chain_exp_t){
            case let fld: *field_meta =>
                base = fld.base;
                before = fld.before;
            case let idx: *indexing_meta =>
                base = idx.base;
                before = idx.before;
            case let slc: *slicing_meta =>
                base = slc.base;
                before = slc.before;
            };
        };
        return base as *member_meta;
    case let slice: *slicing_meta =>
        const base = slice.base;
        const before = slice.before;
        for(base is null){
            match(before as chain_exp_t){
            case let fld: *field_meta =>
                base = fld.base;
                before = fld.before;
            case let idx: *indexing_meta =>
                base = idx.base;
                before = idx.before;
            case let slc: *slicing_meta =>
                base = slc.base;
                before = slc.before;
            };
        };
        return base as *member_meta;
    };
};

fn eval_fields_and_indexes(
    ctxt: *context,
    memb: *member_meta,
    at: size,
) (size | ERROR) = {
    let end = at;
    let tk = next_tk(ctxt, end,
        "expected %bexpression continuation%r or %bend of line%r, but got %y{}")?;

    // assert for record field access and array indexing
    if(comp_tk(tk.val, symbol::DOT) || comp_tk(tk.val, symbol::LFT_SQUARE)){
        tk = next_tk(ctxt, end,
            "expected %bfield access%r or %bexpression continuation%r, but got %y{}")!;
        if(!memb.tpe.partial &&
            (memb.tpe.base is *record ||
            memb.tpe.base is *array)){
            let before: (void | ...chain_exp_t) = void;
            let access: (void | ...chain_exp_t) = void;
            let last_tpe = memb.tpe;
            let last_prop = memb.prop;
            for(comp_tk(tk.val, symbol::DOT) || comp_tk(tk.val, symbol::LFT_SQUARE)){
                if(comp_tk(tk.val, symbol::DOT)){
                    const (meta, _end) = eval_record_field(ctxt, end, last_tpe, before)?;
                    end = _end;
                    memb.pos = end;
                    last_tpe = meta.tpe;
                    last_prop = meta.prop;
                    // assign base of chain
                    if(before is void){
                        const dup = alloc(*memb)!;
                        meta.base = dup;
                        append(allocd_nodes, dup)!;
                    };
                    access = meta;
                } else {
                    const (meta, _end) = eval_indexing(ctxt, end, last_tpe, before)?;
                    end = _end;
                    memb.pos = end;
                    match(meta){
                    case let index: *indexing_meta =>
                        last_tpe = index.tpe;
                        last_prop = index.prop;
                        // assign base of chain
                        if(before is void){
                            const dup = alloc(*memb)!;
                            index.base = dup;
                            append(allocd_nodes, dup)!;
                        };
                    case let slice: *slicing_meta =>
                        last_tpe = slice.tpe;
                        last_prop = slice.prop;
                        // assign base of chain
                        if(before is void){
                            const dup = alloc(*memb)!;
                            slice.base = dup;
                            append(allocd_nodes, dup)!;
                        };
                    };
                    access = meta;
                };
                before = access;
                tk = next_tk(ctxt, end,
                    "expected valid %bfield access%r, valid %barray indexing%r or %bexpression continuation%r, but got %y{}")?;
            };
            const final = access as chain_exp_t;
            memb.tpe = last_tpe;
            memb.val = final;
            memb.prop = void;
        } else if(memb.tpe.partial && memb.tpe.base is *record){
            move_ptr(ctxt, tk);
            const name = strtype(memb.tpe);
            defer free(name);
            return error_hint(ctxt,
                "\n%gtry bubbling the error with %d?%g or asserting it with %d!",
                "cannot access field of %b{}%r", name);
         } else if(memb.tpe.partial && memb.tpe.base is *array){
            move_ptr(ctxt, tk);
            const name = strtype(memb.tpe);
            defer free(name);
            return error_hint(ctxt,
                "\n%gtry bubbling the error with %d?%g or asserting it with %d!",
                "cannot index an array of %b{}%r", name);
        } else {
            move_ptr(ctxt, tk);
            const name = strtype(memb.tpe);
            defer free(name);
            return error(ctxt, "object of %b{}%r has %yno fields", name);
        };
    };
    return end;
};

// evaluates an allocation expression
// assumes `at` is pointing to `keyword::NEW`
fn eval_alloc(
    ctxt: *context,
    at: size,
    hint: lichen_t,
) ((*alloc_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, keyword::NEW));

    const old_alloc = ctxt.allocating;
    ctxt.allocating = true;

    let end = at + 1;
    let tk = next_tk(ctxt, end,
        "expected %ballocation object%r or %bpropagation operator%r, but got %y{}")?;
    const host_fun = ctxt.host_fun as *fun_meta;

    const buffer = memio::dynamic();
    move_ptr(ctxt, ctxt.tokens[at + 1]);
    const pos = gen_pos(ctxt);
    defer free(pos);

    fmt::fprintf(&buffer, "{}: allocation failed\\n", pos)!;
    const err_msg_id = push_lit(ctxt, memio::string(&buffer)!);

    const prop: (void | short_prop) =
        if(comp_tk(tk.val, operator::BANG) ||
        comp_tk(tk.val, operator::BUBBLE)){
            if(comp_tk(tk.val, operator::BUBBLE) && !host_fun.fun.tpe.partial){
                move_ptr(ctxt, tk);
                const arg = strtype(host_fun.fun.tpe);
                defer free(arg);
                return error(ctxt,
                    "cannot bubble or assert error state from %b{}", arg);
            };
            end += 1;
            yield (tk.val as operator, err_msg_id, alloc(buffer)!);
        };
    const (_val, _end, invalid) = eval_member(ctxt, end, hint, hint)?;
    move_ptr(ctxt, ctxt.tokens[end]);
    if(invalid){
        return error(ctxt,
            "expected valid %ballocation source object%r, but got %y{}");
    };
    const val = _val as *member_meta;
    if(untyped(val.tpe)){
        return error(ctxt, "cannot allocate %yuntyped value");
    } else if(val.tpe.partial && !(val.val is *array_lit_meta)){
        return error(ctxt, "cannot allocate %ypartial type");
    } else if(!is_aggregated(val.tpe)){
        return error(ctxt, "cannot allocate %ynon-aggregated types");
    } else if(comp_type(val.tpe, primitive::CSTR)){
        return error_hint(ctxt,
            "\n%gC strings do not carry its length alongside its data",
            "cannot allocate %yvalue of unknown size");
    } else if(comp_type(val.tpe, primitive::MEM)){
        return error_hint(ctxt,
            "\n%garenas cannot be deed-duplicated safely",
            "cannot allocate %ymemory arena%r from this statement");
    };
    val.tpe.partial = prop is void;
    end = pop_assert(ctxt, _end, symbol::AT,
        "expected %ballocation location assignment%r, but got %y{}")?;

    tk = next_tk(ctxt, end, "expected %barena name%r, but got %{}")?;
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt, "expected %barena name%r, but got %{}", arg);
    };
    end += 1;
    const name = tk.val as namespace;
    const decl = get_def(ctxt, name, ctxt.scp);
    move_ptr(ctxt, tk);
    if(decl is void){
        return error(ctxt,
            "no memory arena named \"{}\" was declared up to this point",
            name.name);
    };
    const arena = (decl as *decl_meta).var;
    if(!comp_type(arena.nm.tpe, primitive::MEM)){
        const arg = strtype(arena.nm.tpe);
        defer free(arg);
        return error(ctxt,
            "given variable \"{}\" is of {}, not a valid memory arena",
            name.name, arg);
    } else if(!arena.nm.mut){
        return error(ctxt,
            "given arena \"{}\" is not mutable",
            name.name);
    };
    const out = alloc(alloc_meta {
        pos = at,
        val = val,
        tpe = val.tpe,
        prop = prop,
        arena = arena,
        host = host_fun.fun.tpe,
    })!;
    append(allocd_nodes, out)!;

    ctxt.allocating = old_alloc;
    return (out, end);
};

fn eval_concat(
    ctxt: *context,
    at: size,
    tpe: lichen_t
) ((*concat_meta, size) | ERROR) = {
    let end = at + 1;
    let tk = next_tk(ctxt, end,
        "expected %bconcatenation lefthand%r, but got %y{}")?;
    const (lefthand, lft_t, item_t, _end) = fetch_iter(ctxt, end, tk)?;
    const host_fun = ctxt.host_fun as *fun_meta;
    if(lft_t.partial){
        move_ptr(ctxt, ctxt.tokens[at - 1]);
        const arg = strtype(lft_t);
        defer free(arg);
        return error(ctxt, "cannot concatenate %y{}", arg);
    };
    const left_arr =
        if(lft_t.base is *array){
            yield lft_t.base as *array;
        } else {
            const (t, _) = wrap_array(ctxt, lft_t);
            yield t.base as *array;
        };
    const length_known = left_arr.length is size;
    // ignore type length when comparing
    const temp = *left_arr;
    temp.length = void;
    const cat_tpe = new_array_t(ctxt, temp);

    end = pop_assert(ctxt, _end, operator::RANGE,
        "expected %brange operator%r, but got %y{}")?;

    tk = next_tk(ctxt, end,
        "expected %bpropagation operator%r or %bconcatenation righthand%r, but got %y{}")?;
    // optional propagation
    const prop: (void | short_prop) =
        if(comp_tk(tk.val, operator::BANG) ||
            comp_tk(tk.val, operator::BUBBLE)){
            // assert for valid error bubbling
            if(comp_tk(tk.val, operator::BUBBLE) &&
                !host_fun.fun.tpe.partial){
                move_ptr(ctxt, tk);
                const arg = strtype(host_fun.fun.tpe);
                defer free(arg);
                return error(ctxt,
                    "cannot bubble or assert error state from %b{}", arg);
            };
            end += 1;
            const buffer = memio::dynamic();
            move_ptr(ctxt, ctxt.tokens[at + 1]);
            const pos = gen_pos(ctxt);
            defer free(pos);

            fmt::fprintf(&buffer, "{}: concatenation failed\\n", pos)!;
            const err_msg_id = push_lit(ctxt, memio::string(&buffer)!);
            yield (tk.val as operator, err_msg_id, alloc(buffer)!);
        };
    tk = next_tk(ctxt, end,
        "expected %bconcatenation righthand%r, but got %y{}")?;
    
    const (righthand, rgt_t, _, _end) =
        fetch_iter(ctxt, end, tk, false, true)?;

    let type_match = true;
    // assert for length
    if(rgt_t.base is *array){
        const right_arr = rgt_t.base as *array;
        if(length_known && right_arr.length is void){
            type_match = false;
        } else if(!length_known && right_arr.length is size){
            type_match = false;
        } else {
            type_match = is_subtype(rgt_t, cat_tpe);
        };
    } else {
        type_match = comp_type(lft_t, rgt_t);
    };
    if(!type_match && !is_subtype(rgt_t, item_t)){
        move_ptr(ctxt, tk);
        const arg1 = strtype(lft_t);
        defer free(arg1);
        const arg2 = strtype(rgt_t);
        defer free(arg2);
        return error(ctxt,
            "cannot concatenate %blefthand of {}%r with %brighthand of {}",
            arg1, arg2);
    };
    // edge case for single string type item appending
    if(!type_match && righthand is iterator_t){
        const memb = alloc(member_meta {
            pos = end,
            tpe = rgt_t,
            pre = void,
            val = righthand as iterator_t,
            prop = void,
        })!;
        append(allocd_nodes, memb)!;
        righthand = memb;
    };
    const right_length =
        if(rgt_t.base is *array){
            const right_arr = rgt_t.base as *array;
            yield right_arr.length;
        } else {
            yield 1z;
        };
    // make sure the member is typed
    if(righthand is *member_meta){
        const memb = righthand as *member_meta;
        memb.tpe = item_t;
    };
    end = pop_assert(ctxt, _end, symbol::AT,
        "expected %ballocation location assignment%r, but got %y{}")?;

    tk = next_tk(ctxt, end, "expected %barena name%r, but got %{}")?;
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt, "expected %barena name%r, but got %{}", arg);
    };
    end += 1;
    const name = tk.val as namespace;
    const decl = get_def(ctxt, name, ctxt.scp);
    move_ptr(ctxt, tk);
    if(decl is void){
        return error(ctxt,
            "no memory arena named \"{}\" was declared up to this point",
            name.name);
    };
    const arena = (decl as *decl_meta).var;
    if(!comp_type(arena.nm.tpe, primitive::MEM)){
        const arg = strtype(arena.nm.tpe);
        defer free(arg);
        return error(ctxt,
            "given variable \"{}\" is of {}, not a valid memory arena",
            name.name, arg);
    } else if(!arena.nm.mut){
        return error(ctxt,
            "given arena \"{}\" is not mutable",
            name.name);
    };
    cat_tpe.partial = prop is void;
    if(length_known){
        const as_arr = (cat_tpe.base as *array);
        as_arr.length = left_arr.length as size + right_length as size;
    };
    const out = alloc(concat_meta {
        pos = at - 1,
        left = lefthand as iterator_t,
        right = righthand,
        are_slices = !length_known,
        tpe = cat_tpe,
        prop = prop,
        host = host_fun.fun.tpe,
        arena = arena,
    })!;
    return (out, end);
};

// evaluates an array literal
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
    let (tpe, itm_tpe) = wrap_array(ctxt, hint);
    let spreads_at: (void | size) = void;

    let length: (void | *expr_meta) = void;
    let has_allocs = false;
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

        // check if value is dynamically allocated
        const lifetimed = has_lifetime(itm);
        if(lifetimed) has_allocs = true;

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
            if(as_arr.length is void && length is void){
                // extract expression root and assert for its kind
                const root = extract_root(itm);
                // if it's a number literal
                if(root is *const_meta){
                    const val = root as *const_meta;
                    as_arr.length = val.val as size;
                // something else
                } else {
                    if(!ctxt.allocating){
                        move_ptr(ctxt, ctxt.tokens[begin]);
                        const begin = ctxt.tokens[at].pos;
                        const endat = ctxt.tokens[end + 1].pos;
                        const hint =
                            if(!untyped(as_arr.base)){
                                const atype = strtype(as_arr.base, strtype_mode::SKIP);
                                defer free(atype);
                                yield fmt::asprintf(
                                    "\n%gtry doing:%d\n\n\tnew ! {}...] {} @ arena\n",
                                    strings::fromutf8(ctxt.src[begin..endat])!, atype)!;
                            } else {
                                yield fmt::asprintf(
                                    "\n%gtry doing:%d\n\n\tnew ! {}...] @ arena\n",
                                    strings::fromutf8(ctxt.src[begin..endat])!)!;
                            };
                        defer free(hint);
                        return error_hint(ctxt, hint,
                            "cannot dynamically allocate on the stack");
                    };
                    length = itm;
                };
            } else {
                return error(ctxt, "array length %yset multiple times");
            };
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bnext array item%r or %bend of array%r, but got %y{}")?;
            continue;
        } else if(comp_tk(tk.val, operator::SPREAD)){
            // assert for values
            if(as_arr.length is void && length is void){
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "cannot %bfill items%r with array of %yundefined size");
            } else if(as_arr.length is size){
                assert_hint(ctxt, ctxt.tokens[begin], itm.tpe, itm_tpe)?;
                if(untyped(itm_tpe)) itm_tpe = itm.tpe;
                spreads_at = len(items);
                append(items, itm)!;
            } else {
                assert(length is *expr_meta);
                assert_hint(ctxt, ctxt.tokens[begin], itm.tpe, itm_tpe)?;
                if(untyped(itm_tpe)) itm_tpe = itm.tpe;
                spreads_at = len(items);
                append(items, itm)!;
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
    } else if(length is *expr_meta && spreads_at is void){
        move_ptr(ctxt, tk);
        return error_hint(ctxt,
            "\n%gthe array is dynamic, requiring a spread expression at the end",
            "not all items were assigned a value");
    };
    end = pop_assert(ctxt, end, symbol::RGT_SQUARE,
        "expected %bend of array%r, but got %y{}")?;

    // deduce length
    if(as_arr.length is void && length is void){
        as_arr.length = len(items);
    // assert for literal as subtype
    } else if(hint.base is *array && spreads_at is void){
        const hint_arr = hint.base as *array;
        if(hint_arr.length is size && hint_arr.length as size > len(items)){
            as_arr.length = len(items);
        };
    };

    const cast = eval_type(ctxt, end);
    if(cast is (lichen_t, size)){
        const (_tpe, _end) = cast as (lichen_t, size);
        assert_hint(ctxt, ctxt.tokens[end], _tpe, itm_tpe)?;
        as_arr.base = _tpe;
        end = _end;
    } else {
        as_arr.base = itm_tpe;
    };
    tpe.base = as_arr;
    if(untyped(as_arr.base)){
        move_ptr(ctxt, ctxt.tokens[at]);
        return error(ctxt, "cannot deduce array type");
    };
    const out = alloc(array_lit_meta {
        pos = at,
        tpe = tpe,
        items = items,
        length = length,
        spreads_at = spreads_at,
        has_allocs = has_allocs,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

// evaluates an array indexing or slicing expression
fn eval_indexing(
    ctxt: *context,
    at: size,
    base_tpe: lichen_t,
    base: (void | ...chain_exp_t),
) (((*indexing_meta | *slicing_meta), size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, symbol::LFT_SQUARE));
    // assert for partials
    if(base_tpe.partial){
        move_ptr(ctxt, ctxt.tokens[at]);
        const arg = strtype(base_tpe);
        defer free(arg);
        return error(ctxt, "cannot index on {}", arg);
    };
    if(base_tpe.base is *array){
        const arr = base_tpe.base as *array;
        let end = at + 1;
        let tk = next_tk(ctxt, end,
            "expected valid %bindex%r, but got %y{}")?;
        const (index, _end): ((*const_meta | *expr_meta), size) =
            if(tk.val is size){
                const (c, e) = eval_constant(ctxt, end,
                    quick_t(primitive::U64))?;
                yield (c, e);
            } else {
                const (exp, e) = eval_expression(ctxt, end,
                    quick_t(primitive::U64))?;
                yield (exp, e);
            };
        // assert if indexing is safe or partial
        let known = index is *const_meta && arr.length is size;
        // assert for indexing out of bounds
        if(known){
            const idx = (index as *const_meta).val as size;
            if(idx >= arr.length as size){
                move_ptr(ctxt, tk);
                const hint = fmt::asprintf(
                    "\n%gthe index is {}, but the array length is {}",
                    idx, arr.length as size)!;
                defer free(hint);
                return error_hint(ctxt, hint, "indexing out of bounds");
            };
        };
        end = _end;
        tk = next_tk(ctxt, end,
            "expected %bend of indexing%r or %brange operator%r, but got %y{}")?;
        end += 1;
        if(comp_tk(tk.val, symbol::RGT_SQUARE)){
            // failure assertion and casting
            const (tpe, prop, _end) = eval_cast(ctxt,
                unwrap_array(base_tpe, !known), end)?;
            end = _end;
            const out = alloc(indexing_meta {
                before = base,
                index = index,
                base = null,
                pos = at,
                tpe = tpe,
                prop = prop,
                from_tpe = base_tpe,
            })!;
            append(allocd_nodes, out)!;
            return (out, end);
        } else if(comp_tk(tk.val, operator::RANGE)){
            tk = next_tk(ctxt, end,
                "expected valid %bindex%r, but got %y{}")?;
            const (end_idx, _end): ((*const_meta | *expr_meta), size) =
                if(tk.val is size){
                    const (c, e) = eval_constant(ctxt, end,
                        quick_t(primitive::U64))?;
                    yield (c, e);
                } else {
                    const (exp, e) = eval_expression(ctxt, end,
                        quick_t(primitive::U64))?;
                    yield (exp, e);
                };
            end = pop_assert(ctxt, _end, symbol::RGT_SQUARE,
                "expected %bend of indexing%r, but got %y{}")?;

            const up_known = end_idx is *const_meta && arr.length is size;
            if(up_known){
                const idx = (end_idx as *const_meta).val as size;
                if(idx >= arr.length as size + 1){
                    move_ptr(ctxt, tk);
                    const hint = fmt::asprintf(
                        "\n%gthe upper index is {}, but the array length is {}",
                        idx, arr.length as size)!;
                    defer free(hint);
                    return error_hint(ctxt, hint, "indexing out of bounds");
                };
            };
            const slice_t = base_tpe;
            slice_t.base = alloc(*(slice_t.base as *array))!; // TODO: save this for cleanup
            (slice_t.base as *array).length = void;

            if(!known || !up_known){
                slice_t.partial = true;
            };
            // failure assertion and casting
            const (tpe, prop, _end) = eval_cast(ctxt, slice_t, end)?;
            end = _end;
            const out = alloc(slicing_meta {
                before = base,
                begin = index,
                end = end_idx,
                base = null,
                pos = at,
                tpe = tpe,
                safe = known && up_known,
                prop = prop,
            })!;
            append(allocd_nodes, out)!;
            return (out, end);
        } else {
            move_ptr(ctxt, tk);
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %bend of indexing%r or %brange operator%r, but got %y{}",
                arg);
        };
    };
    move_ptr(ctxt, ctxt.tokens[at]);
    if(base is void){
        const name = strtype(base_tpe);
        defer free(name);
        return error(ctxt, "object of %b{}%r is not indexable", name);
    } else {
        const bf = base as *field_meta;
        const name = strtype(bf.tpe);
        defer free(name);
        return error(ctxt, "field %b{}%r of %b{}%r is not indexable",
            bf.field.var.nm.name, name);
    };
};

// evaluates a record literal
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
    let has_allocs = false;
    const values: [](str, size, *expr_meta) = [];
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
                    yield fmt::asprintf("\n%gtry this:\n\n\t{} {{ {} = ... }}",
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
        let field: (void | *decl_meta) = void;
        let fidx = 0z;
        for(fidx < len(rec.fields); fidx += 1){
            const f = rec.fields[fidx];
            if(f.1.var.nm.name == field_name.name){
                field = f.1;
                break;
            };
        };
        if(field is void){
            move_ptr(ctxt, tk);
            return error(ctxt, "no field named %y{}", field_name.name);
        };
        end = pop_assert(ctxt, end, operator::ASG,
            "expected %bfield assignment%r, but got %y{}")?;

        const (val, _end) = eval_expression(ctxt, end, (field as *decl_meta).var.nm.tpe)?;
        if(extract_root(val) is *alloc_meta){
            has_allocs = true;
        };
        append(values, (field_name.name, fidx, val))!;
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
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt, 
                "expected %bcomma%r or %bend of field assignment list%r, but got %y{}", arg);
        };
    };
    if(field_count > len(rec.fields)){
        move_ptr(ctxt, tk);
        return error(ctxt, "no fields are left to be assigned");
    };
    if(field_count < len(rec.fields)){
        move_ptr(ctxt, tk);
        return error(ctxt, "all fields must be assigned");
    };
    end = pop_assert(ctxt, end, symbol::RGT_CURLY,
        "expected %bend of field assignment list%r, but got %y{}")?;

    const out = alloc(record_lit_meta {
        tpe = tpe,
        has_allocs = has_allocs,
        values = values,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

// evaluates a record field access
fn eval_record_field(
    ctxt: *context,
    at: size,
    base_tpe: lichen_t,
    base: (void | ...chain_exp_t),
) ((*field_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, symbol::DOT));
    // assert for partials
    if(base_tpe.partial){
        move_ptr(ctxt, ctxt.tokens[at]);
        const arg = strtype(base_tpe);
        defer free(arg);
        return error(ctxt, "cannot index on {}", arg);
    };
    let end = at + 1;
    let tk = next_tk(ctxt, end,
        "expected valid %bfield name%r, but got %y{}")?;
    if(!(tk.val is namespace)){
        move_ptr(ctxt, tk);
        const arg = strtoken(tk.val);
        defer free(arg);
        return error(ctxt,
            "expected valid %bfield name%r, but got %y{}", arg);
    };
    end += 1;
    const field_name = tk.val as namespace;
    if(base_tpe.base is *record){
        const rec = base_tpe.base as *record;
        for(let field .. rec.fields){
            if(field.1.var.nm.name == field_name.name){
                const (tpe, prop, _end) = eval_cast(ctxt,
                    field.1.var.nm.tpe, end)?;
                end = _end;
                const out = alloc(field_meta {
                    before = base,
                    field = field.1,
                    base = null,
                    mut = if(field.0 is bool) field.0 as bool else true, 
                    pos = at,
                    tpe = tpe,
                    prop = prop,
                    from_tpe = base_tpe,
                })!;
                append(allocd_nodes, out)!;
                return (out, end);
            };
        };
    };
    move_ptr(ctxt, tk);
    if(base is void){
        const name = strtype(base_tpe);
        defer free(name);
        return error(ctxt, "object of %b{}%r has %yno field named \"{}\"",
            name, field_name.name);
    } else {
        const bf = base as *field_meta;
        const name = strtype(bf.tpe);
        defer free(name);
        return error(ctxt, "field %b{}%r of %b{}%r has %yno field named \"{}\"",
            bf.field.var.nm.name, name, field_name.name);
    };
};

// evaluates a ternary ecpression
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
    const ternary = alloc(ternary_meta {
        pos = begin,
        tpe = tpe,
        positive = pos_val,
        negative = neg_val,
        condition = cond,
    })!;
    append(allocd_nodes, ternary)!;
    const out = alloc(expr_meta {
        pos = begin,
        tpe = tpe,
        pre = void,
        val = ternary,
        prop = void,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

// evaluates a function call site
fn eval_funcall(
    ctxt: *context,
    fun: *fun_meta,
    at: size,
) ((*funcall_meta, size) | ERROR) = {
    assert(comp_tk(ctxt.tokens[at].val, symbol::LFT_PAR));
    // mark context for a re_emitting round
    if(!fun.used) ctxt.re_emit = true;
    fun.used = true;

    let tk = next_tk(ctxt, at + 1,
        "expected %bnext argument%r or %bend of argument list%r, but got %y{}")?;
    let end = at + 1;
    let arg_count = 0z;
    let arg_list: []*expr_meta = [];
    let lifetime: (void | size) = void;

    const (borrows, index) =
        if(fun.borrows is size){
            yield (true, fun.borrows as size);
        } else {
            yield (false, 0z);
        };
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
        // assert for shared effects
        if(fun.effects is *effect_t &&
            len((fun.effects as *effect_t).inherits) > 0){
            const host = ctxt.host_fun as *fun_meta;
            const efx = fun.effects as *effect_t;
            for(let shared .. efx.inherits){
                if(shared == arg_count){
                    const ptr = (arg.val as *member_meta).val as *fn_ptr_meta;
                    require_impl_efx(ctxt, host, ptr.points_to.effects, _end)?;
                };
            };
        };
        arg.tpe = fun.params[arg_count].var.nm.tpe;
        // borrow argument lifetime
        if(borrows && arg_count == index){
            const obj = extract_root(arg);
            if(obj is *var_meta){
                lifetime = (obj as *var_meta).lifetime;
            } else if(obj is *funcall_meta){
                lifetime = (obj as *funcall_meta).lifetime;
            };
        };
        // assert for mutability matching
        if(fun.params[arg_count].var.nm.mut){
            assert_argument_mutability(ctxt, ctxt.tokens[end],
                extract_root(arg) as path_meta)?;
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
            const arg = strtoken(tk.val);
            defer free(arg);
            return error(ctxt,
                "expected %bcomma%r or %bend of argument list%r, but got %y{}",
                arg);
        };
    };
    // validade function effect tags
    validate_efx(ctxt, fun, at)?;
    const recursive = fun == ctxt.host_fun as *fun_meta;

    // assert for tailcalls
    if(recursive && (fun.effects is void ||
        (fun.effects is *effect_t && !(fun.effects as *effect_t).loop)) &&
        !ctxt.branching){
        move_ptr(ctxt, ctxt.tokens[at - 1]);
        return error_hint(ctxt,
            "\n%gthis function calls itself unconditionally, "
            "becoming a never-halting function",
            "function does not tags itself for recursion");
    };
    if(arg_count > max){
        move_ptr(ctxt, tk);
        const hint = fmt::asprintf("\n%gthe function %b{} takes {} {}",
            fun.fun.name, max, fix_plural("parameters", max))!;
        defer free(hint);
        return error_hint(ctxt, hint, "too many arguments in function call");
    } else if(arg_count < max){
        move_ptr(ctxt, tk);
        const hint = fmt::asprintf("\n%gthe function %b{} takes {} {}",
            fun.fun.name, max, fix_plural("parameters", max))!;
        defer free(hint);
        return error_hint(ctxt, hint, "too few arguments in function call");
    };

    end = pop_assert(ctxt, end, symbol::RGT_PAR,
        "expected %bclosing parenthesis%r, but got %y{}")?;

    const out = alloc(funcall_meta {
        fun = fun,
        tpe = fun.fun.tpe,
        pos = at,
        args = arg_list,
        lifetime = lifetime,
        tailcall = recursive && !ctxt.branching,
    })!;
    append(allocd_nodes, out)!;
    return (out, end);
};

fn assert_argument_mutability(
    ctxt: *context,
    pos: token,
    root: path_meta,
) (void | ERROR) = {
    move_ptr(ctxt, pos);
    match(root){
    case let var: *var_meta =>
        if(!var.nm.mut){
            return error(ctxt,
                "function takes a %bmutable reference%r, but variable %b{}%r is not mutable",
                var.nm.name);
        };
    case let field: *field_meta =>
        if(!field.mut){
            return error(ctxt,
                "function takes a %bmutable reference%r, but record field %b{}%r is not mutable",
                field.field.var.nm.name);
        };
    case let index: *indexing_meta =>
        if(index.base is *member_meta){
            const source = index.base as *member_meta;
            if(source.val is *var_meta){
                const pass = source.val as *var_meta;
                if(!pass.nm.mut){
                    return error(ctxt,
                    "function takes a %bmutable reference%r, but variable %b{}%r is not mutable",
                    pass.nm.name);
                };
            };
        } else {
            assert_argument_mutability(ctxt, pos,
                index.before as chain_exp_t)?;
        };
    case let slice: *slicing_meta =>
        if(slice.base is *member_meta){
            const source = slice.base as *member_meta;
            if(source.val is *var_meta){
                const pass = source.val as *var_meta;
                if(!pass.nm.mut){
                    return error(ctxt,
                    "function takes a %bmutable reference%r, but variable %b{}%r is not mutable",
                    pass.nm.name);
                };
            };
        } else {
            assert_argument_mutability(ctxt, pos,
                slice.before as chain_exp_t)?;
        };
    case => void;
    };
};

// validades effects for a given called function and a caller set of tags
fn validate_efx(
    ctxt: *context,
    called: *fun_meta,
    pos: size,
) (void | ERROR) = {
    assert(ctxt.host_fun != null);
    move_ptr(ctxt, ctxt.tokens[pos - 1]);
    const host = ctxt.host_fun as *fun_meta;
    // pure calls
    if(called.effects is void) return;

    const caller = ctxt.host_fun: *fun_meta;
    if(caller.effects is do_effect){
        if(called.effects is do_effect){
            return error(ctxt,
                "functions tagged with %bdo effect%r cannot call another function also tagged with %bdo");
        };
        return;
    };
    if(called.origin == ctxt.file){
        if(host.effects is void && called.effects is *effect_t &&
            // polymorphic effects are handled at call site
            !(called.effects as *effect_t).polymorphic){
            return error_hint(ctxt,
                "\n%gtry declaring using the same tags of the called function on the caller declaration",
                "the called function %b{}%r is %yimpure%r, but the caller function {} has no %ydeclared effects",
                called.fun.name, host.fun.name);
        } else if((called.effects as *effect_t).polymorphic){
            return;
        };
        const cefx = called.effects as *effect_t;
        const hefx = host.effects as *effect_t;
        if(cefx.loop && !hefx.loop){
            return error_hint(ctxt,
                "\n%gtry declaring an effect %dloop efx = while;%g"
                " at global scope and using it with %d= loop { ... };%g"
                " in the caller function definition",
                "the called function %b{}%r is %ynon-deterministic%r, but no such effect is declared on caller function %y{}",
                called.fun.name, host.fun.name);
        };
        for(let call .. cefx.modcalls){
            let found = false;
            for(let decl .. hefx.modcalls){
                if(decl == call){
                    found = true;
                    break;
                };
            };
            if(!found){
                const hint = fmt::asprintf(
                    "\n%gtry declaring an using the module binding name with "
                    "%d= {} {{%g in the caller function definition",
                    call)!;
                defer free(hint);
                return error_hint(ctxt, hint,
                    "the called function %b{}%r uses %yimpure%r functions from the %b{}%r module, but no such effect is declared on caller function %y{}",
                    called.fun.name, call, host.fun.name);
            };
        };
        for(let muts .. cefx.muts){
            let found = false;
            for(let decl .. hefx.muts){
                if(comp_type(decl, muts)){
                    found = true;
                    break;
                };
            };
            if(!found){
                const tpe = strtype(muts, strtype_mode::SKIP);
                defer free(tpe);
                const hint = fmt::asprintf(
                    "\n%gtry declaring an effect %dffi efx = mut {};%g"
                    " at global scope and using it with %d= efx {{%g"
                    " in the caller function definition",
                    tpe)!;
                defer free(hint);
                const arg = strtype(muts);
                defer free(arg);
                return error_hint(ctxt, hint,
                    "the called function %b{}%r mutates %y{} parameters%r, but no such effect is declared on caller function %y{}",
                    called.fun.name, arg, host.fun.name);
            };
        };
        for(let used .. cefx.ffis){
            let found = false;
            for(let decl .. hefx.ffis){
                if(decl == used){
                    found = true;
                    break;
                };
            };
            if(!found){
                const hint = fmt::asprintf(
                    "\n%gtry declaring an effect %dffi efx = use {};%g"
                    " at global scope and using it with %d= efx {{ ... }};%g"
                    " in the caller function definition",
                    used.var.nm.name)!;
                defer free(hint);
                return error_hint(ctxt, hint,
                    "the called function %b{}%r interacts with the %yFFI variable {}%r, but no such effect is declared on caller function %y{}",
                    called.fun.name, used.var.nm.name, host.fun.name);
            };
        };
    } else {
        const bind = "";
        for(let defs .. ctxt.global.defs){
            if(defs is *module_meta){
                const mod = defs as *module_meta;
                if(mod.ctxt.file == called.origin){
                    bind = mod.name;
                };
            };
        };
        assert(bind != "");
        if(host.effects is void){
            const help = fmt::asprintf(
                "\n%gtry doing %d\"= %b{}%d {{\""
                "%g in the function scope definition",
                bind)!;
            defer free(help);
            return error_hint(ctxt, help,
                "the function %b{}%r, from the module "
                "%g{}%r, is %yimpure%r, but the caller function doesn't "
                "implement its effect tag",
                called.fun.name, bind);
        };
        if(host.effects is do_effect) return;
        const hefx = host.effects as *effect_t;
        let found = false;
        for(let decl .. hefx.modcalls){
            if(decl == bind){
                found = true;
                break;
            };
        };
        if(!found){
            const help = fmt::asprintf(
                "\n%gtry doing %d\"= %b{}%d {{\""
                "%g in the function scope definition",
                bind)!;
            defer free(help);
            return error_hint(ctxt, help,
                "the function %b{}%r, from the module "
                "%g{}%r, is %yimpure%r, but the caller function doesn't "
                "implement its effect tag",
                called.fun.name, bind);
        };
    };
};

// requires a function to produce the given effects
fn require_impl_efx(
    ctxt: *context,
    fun: *fun_meta,
    req_efx: effect_tag,
    pos: size,
) (void | ERROR) = {
    move_ptr(ctxt, ctxt.tokens[pos - 1]);
    // pure calls
    if(req_efx is void || fun.effects is do_effect) return;
    if(fun.effects is void && req_efx is *effect_t){
        return error(ctxt, // TODO: give some hints
            "the called function %b{}%r implements none of the required effects",
            fun.fun.name);
    } else if(req_efx is do_effect){
        return error_hint(ctxt,
            "\n%gtry declaring the function with %d= do { ... }; %ginstead",
            "the function %b{}%r is required to be tagged with the %ydo%r effect, but it does not",
            fun.fun.name);
    };
    const efx = req_efx as *effect_t;
    const fun_efx = fun.effects as *effect_t;
    if(fun_efx.loop && !efx.loop){
        return error_hint(ctxt,
            "\n%gtry declaring an effect %dloop efx = while;%g"
            " at global scope and using it with %d= loop { ... };%g"
            " in the caller function definition",
            "the function %b{}%r is required to implement a %ynon-deterministic%r effect, but it does not",
            fun.fun.name);
    };
    for(let call .. efx.modcalls){
        let found = false;
        for(let decl .. fun_efx.modcalls){
            if(decl == call){
                found = true;
                break;
            };
        };
        if(!found){
            const hint = fmt::asprintf(
                "\n%gtry declaring an using the module binding name with "
                "%d= {} {{%g in the caller function definition",
                call)!;
            defer free(hint);
            return error_hint(ctxt, hint,
                "the function %b{}%r is required to implement the %b{}%r module effect tag, but it does not",
                fun.fun.name, call);
        };
    };
    for(let muts .. efx.muts){
        let found = false;
        for(let decl .. fun_efx.muts){
            if(comp_type(decl, muts)){
                found = true;
                break;
            };
        };
        if(!found){
            const tpe = strtype(muts, strtype_mode::SKIP);
            defer free(tpe);
            const hint = fmt::asprintf(
                "\n%gtry declaring an effect %dffi efx = mut {};%g"
                " at global scope and using it with %d= efx {{%g"
                " in the caller function definition",
                tpe)!;
            defer free(hint);
            const arg = strtype(muts);
            defer free(arg);
            return error_hint(ctxt, hint,
                "the function %b{}%r is require to implement an effect for mutating %y{} parameters%r, but it does not",
                fun.fun.name, arg);
        };
    };
    for(let used .. efx.ffis){
        let found = false;
        for(let decl .. fun_efx.ffis){
            if(decl == used){
                found = true;
                break;
            };
        };
        if(!found){
            const hint = fmt::asprintf(
                "\n%gtry declaring an effect %dffi efx = use {};%g"
                " at global scope and using it with %d= efx { ... };%g"
                " in the caller function definition",
                used)!;
            defer free(hint);
            return error_hint(ctxt, hint,
                "the function {} is required to implement an effect for iteracting with the %yFFI variable {}%r, but it does not",
                fun.fun.name, used);
        };
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
    if(comp_type(tpe, primitive::UNIT) || comp_type(tpe, primitive::VOID)){
        move_ptr(ctxt, ctxt.tokens[end]);
        const arg = strtype(tpe);
        defer free(arg);
        return error(ctxt,
            "invalid incomplete type %b{}%r for declaration", arg);
    };
    end = _end;

    name.tpe = tpe;
    const var = var_meta {
        nm = name,
        pos = at,
        lifetime = void,
        allocated = false,
    };
    const out = alloc(decl_meta {
        var = alloc(var)!,
        val = void,
    })!;
    append(allocd_nodes, out)!;
    append(allocd_nodes, out.var)!;
    return (out, end);
};

// guarantees a given type is always represented as lichen_t
fn wrap_primitive(tpe: (primitive | lichen_t)) lichen_t =
    match(tpe){
    case let prim: primitive => return quick_t(prim);
    case let tp: lichen_t => return tp;
    };

let tpe_names: []str = [];

const any_arr = array {
    length = void,
    base = lichen_t {
        partial = false,
        base = primitive::ANY,
    },
};
// creates a new anonymous array type
// doesn't instantiate a new type if a similar one was already created
fn new_array_t(ctxt: *context, arr: array, partial: bool = false) lichen_t = {
    if(comp_type(arr.base, primitive::ANY)){
        any_arr.length = arr.length;
        return lichen_t {
            partial = partial,
            base = alloc(any_arr)!, // TODO: save this for cleanup
        };
    };
    const dummy = lichen_t {
        partial = partial,
        base = alloc(arr)!, // TODO: save this for cleanup
    };
    const tpe_name = strtype(dummy, strtype_mode::DEF);
    const tpe = alloc(type_meta {
        owner = ctxt,
        pos = 0,
        pub = false,
        name = dummy_nm(ctxt, tpe_name),
        self = dummy,
    })!;
    for(let d ..& ctxt.global.defs){
        if(d is *type_meta){
            const def_t = d as *type_meta;
            if(comp_type(def_t.self, tpe.self) ||
                def_t.name.name == tpe.name.name){
                free(tpe_name);
                free(tpe);
                return def_t.self;
            };
        };
    };
    append(allocd_nodes, tpe)!;
    append(tpe_names, tpe_name)!;
    append(ctxt.global.defs, tpe)!;
    append(ctxt.types, tpe)!;
    return tpe.self;
};

// helper function to free anonymous array's exporting names
fn free_names() void = {
    for(let name .. tpe_names){
        free(name);  
    };
    free(tpe_names);
};

// guarantees a given type is always a  
fn wrap_array(
    ctxt: *context, 
    _tpe: (primitive | lichen_t),
) (lichen_t, lichen_t) = {
    const tpe = wrap_primitive(_tpe);
    match(tpe.base){
    case let arr: *array =>
        tpe.base = alloc(*(tpe.base as *array))!; // TODO: save this for cleanup
        return (tpe, arr.base);
    case =>
        if(tpe.base is primitive &&
            tpe.base as primitive == primitive::STR){
            const byte = quick_t(primitive::U8);
            const arr = new_array_t(ctxt, array {
                length = void,
                base = byte,
            });
            return (arr, byte);
        };
        const arr = new_array_t(ctxt, array {
            length = void,
            base = tpe,
        });
        return (arr, tpe);
    };
};

// unwraps array type into its base type
fn unwrap_array(tpe: lichen_t, partial: bool = false) lichen_t = {
    if(tpe.base is *array){
        const base = (tpe.base as *array).base;
        base.partial = partial;
        return base;
    } else {
        assert(comp_type(tpe, primitive::STR));
        return quick_t(primitive::U8, partial);
    };
};

// assert for any type casting and if it's a valid cast
// returns `current` if no cast was found
fn eval_cast(
    ctxt: *context,
    current: lichen_t,
    at: size,
) ((lichen_t, (void | propagation), size) | ERROR) = {
    let tpe = current;
    let end = at;
    let tk = next_tk(ctxt, end,
        "expected %bpropagation operator%r, %bexpression continuation%r or %bend of line%r, but gor %y{}")?;
    
    const after = next_tk(ctxt, end + 1,
        "expected %berror assertion piping%r, %bexpression continuation%r or %bend of line%r, but gor %y{}")?;

    const buffer = memio::dynamic();
    move_ptr(ctxt, ctxt.tokens[at]);
    const pos = gen_pos(ctxt);
    defer free(pos);
    const prop: (void | propagation) =
        if(comp_tk(tk.val, operator::BANG) ||
            comp_tk(tk.val, operator::BUBBLE)){
            const op = tk.val as operator;
            end += 1;
            move_ptr(ctxt, tk);
            if(!tpe.partial){
                const arg = strtype(tpe);
                defer free(arg);
                return error(ctxt,
                    "cannot bubble or assert error state of %b{}",
                    arg);
            } else if(comp_type(tpe, quick_t(primitive::VOID, true))){
                return error_hint(ctxt,
                    "\n%gno value is returned from a (partial) primitive void type",
                    "cannot bubble or assert a void type's error state");
            };
            if(op == operator::BUBBLE){
                fmt::fprintf(&buffer, "{}: an error occured\\n", pos)!;
            } else {
                fmt::fprintf(&buffer, "{}: assertion failed\\n", pos)!;
            };
            const err_msg_id = push_lit(ctxt, memio::string(&buffer)!);
            const caller = ctxt.host_fun as *fun_meta;
            // host function's type is not partial
            if(!caller.fun.tpe.partial &&
                comp_tk(tk.val, operator::BUBBLE) &&
                !comp_tk(after.val, keyword::OR)){
                const arg1 = strtype(caller.fun.tpe);
                defer free(arg1);
                const arg2 = strtype(tpe);
                defer free(arg2);
                return error(ctxt,
                    "caller function of type %b{}%r cannot bubble up error state from %b{}",
                    arg1, arg2);
            // host function's type is void
            } else if(comp_tk(tk.val, operator::BUBBLE) &&
                comp_type(caller.fun.tpe, quick_t(primitive::VOID, true))){
                return error_hint(ctxt,
                    "\n%gno value can be returned from a (partial) primitive void type",
                    "cannot bubble up from void type");
            };
            tpe.partial = false;
            // parse piping
            const exp: (void | path_meta) =
                if(comp_tk(after.val, keyword::OR)){
                    end += 1;
                    yield if(op == operator::BUBBLE){
                        const (exp, _end) = eval_expression(ctxt, end, tpe)?;
                        end = _end;
                        yield exp;
                    } else {
                        const (stt, _end) = eval_statement(ctxt, end)?;
                        end = _end - 1;
                        yield stt;
                    };
                };
            yield (op, exp, err_msg_id, alloc(buffer)!);
        };
    if(!comp_tk(ctxt.tokens[end].val, symbol::EOL) &&
        !comp_tk(ctxt.tokens[end].val, symbol::COMMA) &&
        !comp_tk(ctxt.tokens[end].val, symbol::RGT_PAR))
        match(eval_type(ctxt, end)){
        case let some: (lichen_t, size) =>
            assert_cast(ctxt, ctxt.tokens[end], tpe, some.0)?;
            tpe = some.0;
            end = some.1;
        case => void;
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
    const partial =
        if(comp_tk(tk.val, operator::BANG)){
            tk = next_tk(ctxt, end,
                "expected %btype notation%r, but got %y{}")?;
            end += 1;
            yield true;
        } else {
            yield false;
        };
    match(tk.val){
    case let prim: primitive => return (quick_t(prim, partial), end);
    case let name: namespace =>
        move_ptr(ctxt, tk);
        match(get_def(ctxt, name, ctxt.scp)){
        case let tpe: *type_meta =>
            const res = tpe.self;
            res.partial = partial;
            return (res, end);
        case *fun_meta =>
            return error(ctxt,
                "the namespace %b{}%r is currently defined as a %bfunction%r, not a %ytype",
                name.name);
        case *decl_meta =>
            return error(ctxt,
                "the namespace %b{}%r is currently defined as a %bvariable%r, not a %ytype",
                name.name);
        case let module: *module_meta =>
            end = pop_assert(ctxt, end, symbol::FIELD,
                "expected %bmodule field access%r, but got %y{}")?;
            tk = next_tk(ctxt, end,
                "expected %bvalid field name%r, but gor %y{}")?;
            if(!(tk.val is namespace)){
                move_ptr(ctxt, tk);
                const arg = strtoken(tk.val);
                defer free(arg);
                return error(ctxt,
                    "expected %bvalid field name%r, but gor %y{}", arg);
            };
            end += 1;
            const name = tk.val as namespace;
            for(let defs .. module.ctxt.global.defs){
                if(defs is *type_meta){
                    const tpe = defs as *type_meta;
                    if(tpe.name.name != name.name) continue;
                    if(!tpe.pub){
                        return error(ctxt,
                            "the type %b{}::{}%r exists, but it's %ynot public",
                            module.name, tpe.name.name);
                    };
                    return (tpe.self, end);
                };
            };
            return error(ctxt,
                "no field named %b{}%r is defined on %b{}",
                name.name, module.name);
        case void =>
            return error(ctxt,
                "no type by the name %b{}%r is currently defined", name.name);
        };
    case let kwd: keyword =>
        if(named is void && kwd != keyword::FN){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "anonymous %bcomposed types%r disallowed %youtside type definitions");
        };
        switch(kwd){
        case keyword::RECORD =>
            end = pop_assert(ctxt, end, symbol::LFT_CURLY,
                "expected %brecord fields declaration%r, but got %y{}")?;
            tk = next_tk(ctxt, end, "expected %brecord field%r, but got %y{}")?;
            let fields: []((void | bool), *decl_meta) = [];
            let any_mut = false;
            let all_known = true;
            for(!comp_tk(tk.val, symbol::RGT_CURLY)){
                tk = next_tk(ctxt, end,
                    "expected %brecord field%r or %bend of fields declaration%r, but got %y{}")?;
                const mut_field =
                    if(comp_tk(tk.val, keyword::MUT)){
                        end += 1;
                        any_mut = true;
                        yield true;
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
                // assume everything is mutable at first
                field.var.nm.mut = true;
                if(!size_known(field.var.nm.tpe)) all_known = false;
                append(fields, (mut_field, field))!;

                end = pop_assert(ctxt, _end, symbol::EOL,
                    "expected %bend of line%r, bur got %y{}")?;
                tk = next_tk(ctxt, end,
                    "expected %bnext field%r or %bend of fields declaration%r, but got %y{}")?;

                if(comp_tk(tk.val, symbol::RGT_CURLY)) break;
            };
            end = pop_assert(ctxt, end, symbol::RGT_CURLY,
                "expected %bend of fields declaration%r, but got %y{}")?;

            // fix mutability
            let safe_mut = true;
            if(any_mut){
                for(let f = 0z; f < len(fields); f += 1){
                    if(fields[f].0 is void){
                        fields[f].0 = false;
                        safe_mut = false;
                        fields[f].1.var.nm.mut = false;
                    };
                };
            };
            const rec_name = named as namespace;
            rec_name.glob = true;
            rec_name.kind = nm_kind::TYPE;
            const dummy = memio::fixed([]);
            const fix_name = fix_nm(ctxt, &dummy, rec_name);
            const rec = record {
                name = rec_name,
                export_name = fix_name,
                fields = fields,
                defaults = [],
                copiable = all_known,
                safe_mut = safe_mut,
            };
            const out = lichen_t {
                partial = partial,
                base = alloc(rec)!, // TODO: save this for cleanup
            };
            return (out, end);
        case keyword::ENUM => todo("enums");
        case keyword::FN =>
            end = pop_assert(ctxt, end, symbol::LFT_PAR,
                "expected function type %bparameter list%r, but gpt %y{}")?;

            tk = next_tk(ctxt, end,
                "expected %bparameter type%r or %bend of parameter list%r, but got %y{}")?;

            let variadic = false;
            let any_muts = false;
            let first_mut = 0z;
            const params: [](bool, lichen_t) = [];
            for(!comp_tk(tk.val, symbol::RGT_PAR)){
                if(variadic){
                    move_ptr(ctxt, tk);
                    return error(ctxt,
                        "no additional parameters may follow a %yvariadic parameter");
                };
                const mut =
                    if(comp_tk(tk.val, keyword::MUT)){
                        end += 1;
                        tk = next_tk(ctxt, end,
                            "expected %bparameter type%r, but got %y{}")?;
                        yield true;
                    } else {
                        yield false;
                    };
                const (tpe, _end) = eval_type(ctxt, end)?;
                if(is_aggregated(tpe)){
                    if(mut){
                        first_mut = end;
                        any_muts = true;
                    };
                } else if(mut){
                    move_ptr(ctxt, ctxt.tokens[end - 1]);
                    return error_hint(ctxt,
                        "\n%gonly %yarrays, records and strings%b can mutate its value",
                        "mutability is %bnot applicable%r to %ynon-aggregated types");
                };
                let param = tpe;
                end = _end;
                tk = next_tk(ctxt, end,
                    "expected %bnext parameter type%r or %bend of parameter list%r, but got %y{}")?;
                // variadic
                if(comp_tk(tk.val, operator::SPREAD)){
                    const base = param;
                    param = new_array_t(ctxt,
                        array { length = void, base = base });
                    variadic = true;
                    end += 1;
                    tk = next_tk(ctxt, end,
                        "expected %bend of parameter list%r, but got %y{}")?;
                };
                append(params, (mut, tpe))!;
                // end of list
                if(comp_tk(tk.val, symbol::RGT_PAR)) break;
                end += 1;
                // trailing comma?
                if(!comp_tk(tk.val, symbol::COMMA)){
                    move_ptr(ctxt, tk);
                    const arg = strtoken(tk.val);
                    defer free(arg);
                    return error(ctxt,
                        "expected %bcomma%r, bug got %y{}", arg);
                };
                tk = next_tk(ctxt, end,
                    "expected %bnext parameter type%r or %bend of parameter list%r, but got %y{}")?;
            };
            end = pop_assert(ctxt, end, symbol::RGT_PAR,
                "expected %bend of parameter list%r, but got %y{}")?;
            // return type
            const (rets, _end) = eval_type(ctxt, end)?;
            end = _end;
            // effects
            const (tags, efx, _end) = eval_efx(ctxt, end)?;
            // TODO: validate effect
            end = _end;
            const fnptr = fun_ptr {
                params = params,
                returns = rets,
                efxtags = tags,
                effects = efx,
            };
            const out = lichen_t {
                partial = partial,
                base = alloc(fnptr)!, // TODO: save this for cleanup
            };
            return (out, end);
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
            const tpe = new_array_t(ctxt, array {
                length = length,
                base = sub,
            }, partial);
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
                if(comp_tk(tk.val, symbol::COMMA)){
                    end += 1;
                    tk = next_tk(ctxt, end,
                        "expected %bnext type%r or %bend of tuple%r, but got %y{}")?;
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
            end += 1;
            if(len(memb) < 0){
                move_ptr(ctxt, tk);
                return error(ctxt, "tuple type has %binvalid size%r of %yzero members");
            };
            const tpe = lichen_t {
                partial = partial,
                base = alloc(tuple { // TODO: save this for cleanup
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

// asserts if a given operator is a valid unary operator for a given type
fn assert_unary(ctxt: *context, pos: size, oper: operator, tpe: lichen_t) (void | ERROR) = {
    move_ptr(ctxt, ctxt.tokens[pos]);
    if(!is_unary_op(oper)){
        return error(ctxt, "invalid unary operator \"{}\"", oper_value[oper]);
    };
    if(comp_tk(oper, operator::PLS) || comp_tk(oper, operator::MIN) ||
        comp_tk(oper, operator::NOT) || comp_tk(oper, operator::BANG)){
        if(!comp_tk(oper, operator::BANG) || !comp_type(tpe, primitive::BOOL)){
            assert_hint(ctxt, ctxt.tokens[pos], tpe, primitive::NUMBER)?;
        } else {
            assert_hint(ctxt, ctxt.tokens[pos], tpe, primitive::BOOL)?;
        };
    } else if(comp_tk(oper, operator::LENGTH)){
        if(tpe.base is primitive){
            if(!comp_type(tpe, primitive::STR) &&
                !comp_type(tpe, primitive::MEM)){
                const arg = strtype(tpe);
                defer free(arg);
                return error(ctxt, "value of %b{}%r has no length", arg);
            };
        } else if(!(tpe.base is *array)){
            const arg = strtype(tpe);
            defer free(arg);
            return error(ctxt, "value of %b{}%r has no length", arg);
        };
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
    if(this.partial != that.partial) return false;
    if(this.base is primitive && that.base is primitive){
        return this.base as primitive == that.base as primitive;
    } else if(this.base is *record && that.base is *record){
        return this.base as *record == that.base as *record;
    } else if(this.base is *array && that.base is *array){
        const this_arr = this.base as *array;
        const that_arr = that.base as *array;
        const size_ok = (this_arr.length is void && that_arr.length is void) ||
            ((this_arr.length is size && that_arr.length is size) &&
            (this_arr.length as size == that_arr.length as size));
        return comp_type(this_arr.base,
            that_arr.base) && size_ok;
    } else if(this.base is *enum_t && that.base is *enum_t){
        return this.base as *enum_t == that.base as *enum_t;
    } else {
        return false;
    };
};

// checks if a given type is a subset of another
// this function wraps any given type (primitive literal or lichen_t) into
// lichen_t and calls _is_subtype
fn is_subtype(
    _this: (primitive | lichen_t),
    _that: (primitive | lichen_t),
) bool = {
    const this = wrap_primitive(_this);
    const that = wrap_primitive(_that);
    return _is_subtype(this, that);
};

// actual implementation of is_subtype
fn _is_subtype(_this: lichen_t, _that: lichen_t) bool = {
    // any is a subtype of anything
    if(comp_type(_this, primitive::ANY) ||
        comp_type(_that, primitive::ANY)) return true;
    // an optional type cannot be a subtype of a solid type
    if(!untyped(_this) && !untyped(_that) &&
        _this.partial && !_that.partial) return false;
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
            const ref =
                if(this < primitive::I8) this + primitive::I8 else this;
            return (ref <= that && ref >= primitive::I8) ||
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
                yield (this.length is void && that.length is void) ||
                    (this.length is size && that.length is void);
            };
        return (comp_type(this.base, that.base) ||
            comp_type(this.base, primitive::ANY)) && size_ok;
    // enum comparison
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
    // function comparison
    } else if(_this.base is *fun_ptr && _that.base is *fun_ptr){
        const this = _this.base as *fun_ptr;
        const that = _that.base as *fun_ptr;
        // compare return type
        if(!comp_type(this.returns, that.returns)) return false;
        // compare parameters
        if(len(this.params) != len(that.params)) return false;
        for(let p = 0z; p < len(this.params); p += 1){
            if(this.params[p].0 != that.params[p].0) return false;
            if(!comp_type(this.params[p].1, that.params[p].1)) return false;
        };
        // compare effects
        if(this.effects is void && that.effects is void) return true;
        if(!(that.effects is do_effect)){
            if(this.effects is do_effect) return false;

            let that_efx = that.effects as *effect_t;
            if(that_efx.polymorphic) return true;
            let this_efx = this.effects as *effect_t;
            // mod calls
            if(len(this_efx.modcalls) != len(that_efx.modcalls)) return false;
            for(let this_tag .. this_efx.modcalls){
                let found = false;
                for(let that_tag .. that_efx.modcalls){
                    if(this_tag == that_tag){
                        found = true;
                        break;
                    };
                };
                if(!found) return false;
            };
            // mutations
            if(len(this_efx.muts) != len(that_efx.muts)) return false;
            for(let this_tag .. this_efx.muts){
                let found = false;
                for(let that_tag .. that_efx.muts){
                    if(comp_type(this_tag, that_tag)){
                        found = true;
                        break;
                    };
                };
                if(!found) return false;
            };
            // FFIs
            if(len(this_efx.ffis) != len(that_efx.ffis)) return false;
            for(let this_tag .. this_efx.ffis){
                let found = false;
                for(let that_tag .. that_efx.ffis){
                    if(this_tag == that_tag){
                        found = true;
                        break;
                    };
                };
                if(!found) return false;
            };
            if(this_efx.loop != that_efx.loop) return false;
        };
        return true;
    } else {
        return false;
    };
};

// checks whenever a type is catable into another
// this function wraps any given type (primitive literal or lichen_t) into
// lichen_t and calls _castable
fn castable(
    _this: (primitive | lichen_t),
    _that: (primitive | lichen_t),
) bool = {
    const this = wrap_primitive(_this);
    const that = wrap_primitive(_that);
    return _castable(this, that);
};

// actual implementation of castable
fn _castable(_this: lichen_t, _that: lichen_t) bool = {
    // an optional type cannot be a subtype of a solid type
    if(_this.partial && !_that.partial) return false;
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
        // u8[]/i8[] => str/cstr
        if((comp_type(_that, primitive::CSTR) ||
            comp_type(_that, primitive::STR)) && _this.base is *array){
            const as_arr = _this.base as *array;
            return is_subtype(as_arr.base, primitive::I8) &&
                as_arr.length is void;
        // str => u8[]/i8[]
        } else if(comp_type(_this, primitive::STR) && _that.base is *array){
            const as_arr = _that.base as *array;
            return is_subtype(as_arr.base, primitive::I8) &&
                as_arr.length is void;
        };
        return is_subtype(_this, _that);
    };
};

// extracts the type of any variation of hand_t
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

// extracts the final node of a given expression
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
    if(lft_t.partial || rgt_t.partial) return false;
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

// recudes an expression of two given types and an operator into its final type
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

// checks is given type is a ratio type
fn is_ratio(tpe: lichen_t) bool =
    is_subtype(tpe, primitive::RATIO) && !comp_type(tpe, primitive::NUMBER);

// checks is a given type is untyped
fn untyped(tpe: lichen_t) bool = {
    return comp_type(tpe, primitive::ANY) ||
        comp_type(tpe, primitive::NUMBER) ||
        comp_type(tpe, primitive::RATIO);
};

fn is_terminal(tpe: lichen_t) bool = {
    return comp_type(tpe, primitive::VOID) ||
        comp_type(tpe, quick_t(primitive::VOID, true));
};

// checks if given type is aggregated
fn is_aggregated(tpe: lichen_t) bool = {
    return tpe.partial || is_subtype(tpe, primitive::STR) ||
        is_subtype(tpe, primitive::CSTR) ||
        is_subtype(tpe, quick_t(primitive::MEM)) ||
        tpe.base is *record || tpe.base is *array;
};

// checks if type memory size is known at compile time
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
