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

// extracts a formatted version of the current
// parser position in the file
fn gen_pos(ctxt: *context) str = {
    return fmt::asprintf("{}:{}:{}", ctxt.name,
        ctxt.lin + 1, ctxt.cln + 1)!;
};

// function shortcut
fn u8tostr(a: []u8) str = strings::fromutf8(a)!;

// loads the file `fname` and instantiates
// a file parsing object. returns an error
// if such file cannot be opened.
fn load(fname: str, libpath: str) (context | COMPERR) = {
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
        name = fname,
        libpath = libpath,
        lin = 0, cln = 0,
        ptr = 0, lst = 0,
        src = [], scp = void,
        literals = [],
        fun_defs = [],
        modules = [],
        glob = scope {
            effects = [],
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
            "%rthe file \"{}\" is empty%d\n\n%gtry adding:\n\n{}",
            fname, fn_demo);
    };
    return file;
};

// returns the given token as a human-readable string
fn strtoken(tok: tkval) str = {
    match(tok){
    case let idt: ident =>
        return fmt::asprintf("identifier \"{}\"", idt.id)!;
    case let num: size =>
        return fmt::asprintf("numeric literal {}", num)!;
    case let txt: str =>
        return fmt::asprintf("string literal \"{}\"", txt)!;
    case let kwd: keyword =>
        return fmt::asprintf("keyword \"{}\"", kwd_value[kwd])!;
    case let prm: primitive =>
        switch(prm){
        case primitive::NUMBER =>
            return strings::dup("number literal")!;
        case primitive::RATIO =>
            return strings::dup("ratio literal")!;
        case primitive::ANY =>
            return strings::dup("untyped")!;
        case =>
            return fmt::asprintf("primitive type \"{}\"", prm_value[prm])!;
        };
    case let opr: operator =>
        return fmt::asprintf("\"{}\" operator", opr_value[opr: int])!;
    case let sym: symbol =>
        return strings::dup(sym_value[sym])!;
    case eof =>
        return strings::dup("end of file")!;
    };
};

// compare two tokens
fn comp_tk(lft: tkval, rgt: tkval) bool = {
    match(lft){
    case let idt: ident =>
        if(rgt is ident){
            const r = rgt as ident;
            return r.id == idt.id;
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

// returns a new token with given `val` as value at the
// current context position.
fn new_tk(ctxt: *context, val: tkval) token = {
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

// forcefully moves the context to the position of the
// given token.
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
fn next_tk(ctxt: *context, tokens: []token, at: size, msg: str)
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
fn pop_assert(ctxt: *context, tokens: []token, at: size, val: tkval, msg: str)
    (size | COMPERR) = {
    const tk = next_tk(ctxt, tokens, at, msg)?;
    if(!comp_tk(tk.val, val)){
        move_ptr(ctxt, tk);
        return error(ctxt, msg, strtoken(tk.val));
    };
    return at + 1;
};

let count: size = 0;

// allocates a new empty ast node
fn new_node(tokens: []token, at: size) *ast = {
    count += 1;
    return alloc(ast {
        kind = path_t::EOF,
        path = tokens[at..(at + 1)],
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

const defs: []*ast = [];
// frees the given node and all inner nodes, if any
fn free_nodes(_node: nullable *ast) void = {
    assert(count > 0);
    count -= 1;
    const node = _node as *ast;
    match(node.meta){
    case void =>
        void;
    case primitive =>
        void;
    case let meta: *var_meta =>
        defer free(meta);
        if(meta.mod is str) free(meta.mod as str);
        if(node.inner is *ast) free_nodes(node.inner);

        if(node.kind == path_t::CONST_DEF)
            append(defs, node)!;

    case let exp: *expr_meta =>
        defer free(exp);
        for(let m ..& exp.members){
            if(m.kind != path_t::DECL &&
                m.kind != path_t::CONST_DEF){
                free_nodes(m);
            } else if(m.kind == path_t::DECL &&
                node.kind == path_t::SCOPE){
                free_nodes(m);
                append(defs, m)!;
            };
        };
        free(exp.members);

    case let fun: *fn_meta =>
        defer free(fun);
        free(fun.effects);
        free_nodes(fun.params);
        if(fun.mod is str) free(fun.mod as str);
        if(node.inner is *ast) free_nodes(node.inner);

    case let param: *param_meta =>
        defer free(param);
        free(param.names);
        free(param.pos);
        free(param.at);

    case let fncall: *funcall_meta =>
        defer free(fncall);
        for(let arg ..& fncall.args){
            free_nodes(arg);
        };
        free(fncall.args);
    };
    if(node.next is *ast){
        free_nodes(node.next);
    };
    if(node.kind != path_t::DECL &&
        node.kind != path_t::CONST_DEF){
        free(node);
    };
};

// fetches the corresponding definition of `var` from the current
// scope. returns void if no match is found.
fn get_var(scp: *scope, var: ident) (*ast | void) = {
    for(let var_def ..& scp.vars){
        const meta = var_def.meta as *var_meta;
        if(meta.name.id == var.id) return var_def;
    };
    if(scp.upper is *scope)
        return get_var(scp.upper as *scope, var);
};

// fetches the corresponding definition of `var` from the module bound
// to `mod`. returns an error if said module or variable do not exist.
fn get_mod_var(ctxt: *context, mod: token, name: ident) (*ast | COMPERR) = {
    move_ptr(ctxt, mod);
    const modname = mod.val as ident;
    for(let m ..& ctxt.modules){
        if((m.0.val as ident).id  == modname.id)
        for(let var ..& m.1.ctxt.glob.vars){
            const meta = var.meta as *var_meta;
            if(meta.name.id == name.id){
                meta.mod = fmt::asprintf("{}.{}",
                    modname.id, meta.name.id)!;
                return var;
            };
        };
        return error(ctxt,
            "the module %b{} (bound to %g{}%b)%r has no %y{}%r function",
            m.1.ctxt.name, modname.id, name.id);
    };
    return error(ctxt, "module bind %b{0}%r not found. try adding "
        "%p\"%c{0} %d= %puse %y\"{0}.ms\"%d;%p\"", modname.id);
};

// pushes given variable definition to the current scope. returns an
// error if the variable namespace is already in use.
fn push_var(ctxt: *context, var_def: *ast) (void | COMPERR) = {
    const meta = var_def.meta as *var_meta;
    if(meta.name.itype == primitive::VOID){
        if(meta.name.glob && !meta.name.pub){
            move_ptr(ctxt, var_def.path[1]);
        } else {
            move_ptr(ctxt, var_def.path[2]);
        };
        return error(ctxt, "variables cannot be of type %g{}",
            strtoken(primitive::VOID));
    };
    match(get_var(ctxt.scp as *scope, meta.name)){
    case void =>
        const scp = ctxt.scp as *scope;
        append(scp.vars, var_def)!;
    case let dup: *ast =>
        move_ptr(ctxt, dup.path[0]);
        const dup_pos = gen_pos(ctxt);
        move_ptr(ctxt, var_def.path[0]);
        return error(ctxt, "duplicate definition of variable %b{}%r. "
            "previously defined at {}", meta.name.id, dup_pos);
    };
};

// fetches the corresponding function definition of `name` from the
// current scope. returns void if no match is found.
fn get_fun(ctxt: *context, name: ident) (*ast | void) = {
    for(let fun ..& ctxt.fun_defs){
        const meta = fun.meta as *fn_meta;
        if(meta.name.id == name.id) return fun;
    };
};

// fetches the corresponding function definition of `name` from the module
// bound to `mod`. returns an error if said module or variable do not exist.
fn get_mod_fun(ctxt: *context, mod: token, name: ident) (*ast | COMPERR) = {
    move_ptr(ctxt, mod);
    const modname = mod.val as ident;
    for(let m ..& ctxt.modules){
        if((m.0.val as ident).id  == modname.id)
        for(let fun ..& m.1.ctxt.fun_defs){
            const meta = fun.meta as *fn_meta;
            if(meta.name.id == name.id){
                meta.used = true;
                meta.origin = modname.id;
                meta.mod = fmt::asprintf("{}.{}",
                    modname.id, meta.name.id)!;
                return fun;
            };
        };
        const help = undef_tip(name.id);
        return error(ctxt,
            "the module %b{} (bound to %g{}%b)%r has no %y{}%r function{}",
            m.1.ctxt.name, modname.id, name.id, help);
    };
        return error(ctxt, "module bind %b{0}%r not found. try adding "
            "%p\"%c{0} %d= %puse %y\"{0}.ms\"%d;%p\"", modname.id);
};

// pushes given function definition to the given context. returns an
// error if the function namespace is already in use.
fn push_fun(ctxt: *context, fn_def: *ast) (void | COMPERR) = {
    const meta = fn_def.meta as *fn_meta;
    match(get_fun(ctxt, meta.name)){
    case void =>
        append(ctxt.fun_defs, fn_def)!;
    case let dup: *ast =>
        move_ptr(ctxt, fn_def.path[0]);
        const dup_pos = gen_pos(ctxt);
        move_ptr(ctxt, fn_def.path[0]);
        return error(ctxt, "duplicate definition of function %b{}%r. "
            "previously defined at {}", meta.name.id, dup_pos);
    };
};

// pushes a new string literal to the context and returns its index. if given
// literal already exits, it's index is returned instead.
fn push_str(ctxt: *context, lit: str) size = {
    match(finds(ctxt.literals, lit)){
    case let id: size => return id;
    case void =>
        append(ctxt.literals, lit)!;
        return len(ctxt.literals) - 1;
    };
};

// pushes a new module bound to `bind` to the current context. returns an error
// if given bind is already in use.
fn push_module(ctxt: *context, bind: token, module: comp_obj) (void | COMPERR) = {
    const val = (bind.val as ident).id;
    for(let mod .. ctxt.modules){
        if((mod.0.val as ident).id == val){
            move_ptr(ctxt, mod.0);
            const pos = gen_pos(ctxt);
            move_ptr(ctxt, bind);
            return error(ctxt,
                "another module is using the binding %g{}%b\nlast use at %g{}%f",
                val, pos);
        };
    };
    append(ctxt.modules, (bind, module))!;
};

// cleans up all allocated data from an abstract object file.
fn free_module(obj: comp_obj) void = {
    io::close(obj.buffer)!;
    free(obj.buffer);
    free(obj.tokens);

    free_nodes(obj.ast_head);
    for(let mod .. obj.ctxt.modules) free_module(mod.1);

    defer free(obj.ctxt);
    free(obj.ctxt.modules);
    free(obj.ctxt.literals);
    free(obj.ctxt.glob.vars);
    free(obj.ctxt.fun_defs);
    free(obj.ctxt.name);
    free(obj.ctxt.src);

    for(let d = 0z; d < len(defs); d += 1){
        free(defs[d]);
        delete(defs[d]);
    };
};

// qbe_t modes
type mode = enum u8 { REAL, ASSIGN, LOAD };

// returns the qbe equivalent of a given type. changing the mode to
// ASSIGN rounds types smaller than a word to a word, and to LOAD
// adds a sign prefix to the type.
fn qbe_t(tpe: primitive, md: mode = mode::REAL) str = {
    switch(tpe){
    case primitive::U8 =>
        if(md == mode::ASSIGN) return "w";
        if(md == mode::LOAD) return "ub";
        return "b";
    case primitive::I8 =>
        if(md == mode::ASSIGN) return "w";
        if(md == mode::LOAD) return "sb";
        return "b";
    case primitive::U16 =>
        if(md == mode::ASSIGN) return "w";
        if(md == mode::LOAD) return "uh";
        return "h";
    case primitive::I16 =>
        if(md == mode::ASSIGN) return "w";
        if(md == mode::LOAD) return "sh";
        return "h";
    case primitive::U32 =>
        if(md == mode::LOAD) return "uw";
        return "w";
    case primitive::I32 =>
        if(md == mode::LOAD) return "sw";
        return "w";
    case primitive::U64, primitive::I64, primitive::STR,
        primitive::UNIT =>
        return "l";
    case =>
        assert(false);
        color_error("%Runreachable:%r unknown type %y{}", tpe: int);
    };
};

// compiles down a given file to its QBE IR equivalent as a memio stream
// returns a COMPERR if any compilation error occurs.
fn compile(filename: str, libpath: str, buffer: *memio::stream,
    main: bool = false) (comp_obj | COMPERR) = {
    filename = strings::dup(filename)!;
    // load source file
    const _ctxt =
        match(load(filename, libpath)){
        case let c: context => yield c;
        case let e: COMPERR =>
            yield if(!main){
                const file = strings::concat(libpath, filename)!;
                free(filename);
                filename = file;
                yield load(filename, libpath)?;
            } else {
                return e;
            };
        };
    const ctxt = alloc(_ctxt)!;
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
                    move_cln(ctxt);
                };
            };
        };
        // keyword, numeric literal or identifier
        if(is_alnum(ctxt.src[ctxt.ptr]) || ctxt.src[ctxt.ptr] == '_'){
            const start = ctxt.ptr;
            for(ctxt.ptr < max && is_alnum(ctxt.src[ctxt.ptr]) ||
                ctxt.src[ctxt.ptr] == '_'){
                ctxt.ptr += 1;
                move_cln(ctxt);
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
                    append(tokens, new_tk(ctxt, n: size))!;
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
                    append(tokens, new_tk(ctxt, n: size))!;
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
                    append(tokens, new_tk(ctxt, n: size))!;
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
                    append(tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(ctxt,
                        "64-bit literal overflow");
                case =>
                    for(ctxt.ptr < max && ctxt.src[ctxt.ptr] == '\''){
                        ctxt.ptr += 1;
                        move_cln(ctxt);
                    };
                    append(tokens, new_tk(ctxt, ident {
                        pub = false,
                        glob = false,
                        id = path,
                        itype = primitive::ANY
                    }))!;
                };
            };
        // symbol, operator or string/character literal
        } else if(!(is_alnum(ctxt.src[ctxt.ptr]) || is_whitespace(ctxt.src[ctxt.ptr]))){
            move_cln(ctxt);
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
                const dup = ctxt;

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
                        move_cln(ctxt);
                        break;
                    case =>
                        if(escape){
                            dup.cln = start;
                            return error(dup, "invalid escape sequence \"\\{}\"",
                                ctxt.src[ctxt.ptr]: rune);
                        };
                    };
                    ctxt.ptr += 1;
                    move_cln(ctxt);
                };
                if(!closed) return error(dup, "unclosed string found here");
                assert(!escape);
                append(tokens, new_tk(dup,
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
                append(tokens, new_tk(ctxt, val: size))!;
                continue;
            };
            for(start < end) switch(ctxt.src[start]){
            case ';' =>
                append(tokens, new_tk(ctxt, symbol::EOL))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case ',' =>
                append(tokens, new_tk(ctxt, symbol::COMMA))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '(' =>
                append(tokens, new_tk(ctxt, symbol::LFT_PAR))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case ')' =>
                append(tokens, new_tk(ctxt, symbol::RGT_PAR))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '{' =>
                append(tokens, new_tk(ctxt, symbol::LFT_CURLY))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '}' =>
                append(tokens, new_tk(ctxt, symbol::RGT_CURLY))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '[' =>
                append(tokens, new_tk(ctxt, symbol::LFT_SQUARE))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case ']' =>
                append(tokens, new_tk(ctxt, symbol::RGT_SQUARE))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '#' =>
                append(tokens, new_tk(ctxt, operator::LENGTH))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '@' =>
                append(tokens, new_tk(ctxt, operator::HEAP))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '$' =>
                append(tokens, new_tk(ctxt, symbol::FFI))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '.' =>
                if(start < end - 1 && ctxt.src[start + 1] == '.'){
                    append(tokens, new_tk(ctxt, operator::RANGE))!;
                    start += 2;
                    ctxt.ptr += 2;
                    move_cln(ctxt, 2);
                } else {
                    append(tokens, new_tk(ctxt, symbol::DOT))!;
                    start += 1;
                    ctxt.ptr += 1;
                    move_cln(ctxt);
                };
            case '=' =>
                if(start < end - 1 && ctxt.src[start + 1] == '='){
                    append(tokens, new_tk(ctxt, operator::EQL))!;
                    start += 2;
                    ctxt.ptr += 2;
                    move_cln(ctxt, 2);
                } else if(start < end - 1 && ctxt.src[start + 1] == '>'){
                    append(tokens, new_tk(ctxt, operator::MAP))!;
                    start += 2;
                    ctxt.ptr += 2;
                    move_cln(ctxt, 2);
                } else {
                    append(tokens, new_tk(ctxt, operator::ASG))!;
                    start += 1;
                    ctxt.ptr += 1;
                    move_cln(ctxt);
                };
            case '<' =>
                if(start < end - 1){
                    if(ctxt.src[start + 1] == '='){
                        append(tokens, new_tk(ctxt, operator::LEQ))!;
                        start += 2;
                        ctxt.ptr += 2;
                        move_cln(ctxt, 2);
                    } else if(ctxt.src[start + 1] == '>'){
                        append(tokens, new_tk(ctxt, operator::SHL))!;
                        start += 2;
                        ctxt.ptr += 2;
                        move_cln(ctxt, 2);
                    } else {
                        append(tokens, new_tk(ctxt, operator::LST))!;
                        start += 1;
                        ctxt.ptr += 1;
                        move_cln(ctxt);
                    };
                } else {
                    append(tokens, new_tk(ctxt, operator::LST))!;
                    start += 1;
                    ctxt.ptr += 1;
                    move_cln(ctxt);
                };
            case '>' =>
                if(start < end - 1){
                    if(ctxt.src[start + 1] == '='){
                        append(tokens, new_tk(ctxt, operator::GEQ))!;
                        start += 2;
                        ctxt.ptr += 2;
                        move_cln(ctxt, 2);
                    } else if(ctxt.src[start + 1] == '>'){
                        append(tokens, new_tk(ctxt, operator::SHR))!;
                        start += 2;
                        ctxt.ptr += 2;
                        move_cln(ctxt, 2);
                    } else {
                        append(tokens, new_tk(ctxt, operator::GTT))!;
                        start += 1;
                        ctxt.ptr += 1;
                        move_cln(ctxt);
                    };
                } else {
                    append(tokens, new_tk(ctxt, operator::GTT))!;
                    start += 1;
                    ctxt.ptr += 1;
                    move_cln(ctxt);
                };
            case '|' =>
                if(start < end - 1 && ctxt.src[start + 1] == '|'){
                    append(tokens, new_tk(ctxt, operator::LOR))!;
                    start += 2;
                    ctxt.ptr += 2;
                    move_cln(ctxt, 2);
                } else {
                    append(tokens, new_tk(ctxt, operator::BOR))!;
                    start += 1;
                    ctxt.ptr += 1;
                    move_cln(ctxt);
                };
            case '&' =>
                if(start < end - 1 && ctxt.src[start + 1] == '&'){
                    append(tokens, new_tk(ctxt, operator::LAND))!;
                    start += 2;
                    ctxt.ptr += 2;
                    move_cln(ctxt, 2);
                } else {
                    append(tokens, new_tk(ctxt, operator::BAND))!;
                    start += 1;
                    ctxt.ptr += 1;
                    move_cln(ctxt);
                };
            case ':' =>
                if(start < end - 1 && ctxt.src[start + 1] == ':'){
                    append(tokens, new_tk(ctxt, symbol::FIELD))!;
                    start += 2;
                    ctxt.ptr += 2;
                    move_cln(ctxt, 2);
                } else {
                    append(tokens, new_tk(ctxt, operator::FDIV))!;
                    start += 1;
                    ctxt.ptr += 1;
                    move_cln(ctxt);
                };
            case '!' =>
                if(start < end - 1 && ctxt.src[start + 1] == '='){
                    append(tokens, new_tk(ctxt, operator::NEQ))!;
                    start += 2;
                    ctxt.ptr += 2;
                    move_cln(ctxt, 2);
                } else {
                    append(tokens, new_tk(ctxt, operator::BANG))!;
                    start += 1;
                    ctxt.ptr += 1;
                    move_cln(ctxt);
                };
            case '~' =>
                append(tokens, new_tk(ctxt, operator::NOT))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '+' =>
                append(tokens, new_tk(ctxt, operator::PLS))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '-' =>
                append(tokens, new_tk(ctxt, operator::MIN))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '*' =>
                append(tokens, new_tk(ctxt, operator::MUL))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '/' =>
                if(start < end - 1 && ctxt.src[start + 1] == '/'){
                    for(start < max && ctxt.src[start] != '\n'){
                        start += 1;
                        ctxt.ptr += 1;
                        move_cln(ctxt);
                    };
                } else {
                    append(tokens, new_tk(ctxt, operator::IDIV))!;
                    move_cln(ctxt);
                    ctxt.ptr += 1;
                    start += 1;
                };
            case '%' =>
                append(tokens, new_tk(ctxt, operator::MOD))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
            case '?' =>
                append(tokens, new_tk(ctxt, operator::PROP))!;
                start += 1;
                ctxt.ptr += 1;
                move_cln(ctxt);
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
            move_cln(ctxt);
        };
    };
    append(tokens, new_tk(ctxt, eof))!;

    max = len(tokens);
    if(max == 1){
        return error(ctxt, "the file \"{}\" is empty", ctxt.name);
    };
    let node: nullable *ast = null;
    const head: nullable *ast = null;

    for(let t = 0z; t < max){
        match(tokens[t].val){
        case let idt: ident =>
            // const global definition
            const (cdef, end) = eval_c_def(ctxt, tokens, t)?;
            switch(cdef.kind){
            case path_t::CONST_DEF =>
                push_var(ctxt, cdef)?;
            case path_t::IMPORT =>
                void;
            case =>
                assert(false, "unreachable");
            };
            t = end;
            node = push_node(node, cdef);
            if(head is null) head = node;
        case let kwd: keyword =>
            const (pub, i, val): (bool, size, tkval) =
                if(kwd == keyword::PUB){
                    const v = t;
                    t += 1;
                    const k = next_tk(ctxt, tokens, t,
                        "global %bdefinition continuation%r, but got %y{}")?;
                    yield (true, v, k.val); 
                } else {
                    yield (false, t, kwd);
                };
            if(val is keyword){
                switch(val as keyword){
                // type definition
                case keyword::TYPE =>
                    assert(false, "TODO: type_def");
                // function definition
                case keyword::FN =>
                    const (fun, end) = eval_fun_def(ctxt, tokens, t, pub)?;
                    push_fun(ctxt, fun)?;
                    t = end;
                    node = push_node(node, fun);
                    if(head is null) head = node;
                case =>
                    move_ptr(ctxt, tokens[t]);
                    return error(ctxt, "invalid global expression");
                };
            } else {
                const (cdef, end) = eval_c_def(ctxt, tokens, t, pub)?;
                if(cdef.kind == path_t::CONST_DEF){
                    push_var(ctxt, cdef)?;
                    t = end;
                    cdef.path = tokens[i..t];
                } else {
                    assert(cdef.kind == path_t::IMPORT);
                    if(pub){
                        move_ptr(ctxt, tokens[t]);
                        return error(ctxt, "an %guse statement%r cannot be public");
                    };
                    t = end;
                };
                node = push_node(node, cdef);
                if(head is null) head = node;
            };
        case eof => break;
        case =>
            move_ptr(ctxt, tokens[t]);
            return error(ctxt, "unexpected %y{}", strtoken(tokens[t].val));
        };
    };

    fmt::fprintfln(buffer, "# code generated by mmc v{}\ndbgfile \"{}\"\n",
        version, filename)!;

    match(get_fun(ctxt, ident { id = "main", ... })){
    case let fun: *ast =>
        if(!main){
            move_ptr(ctxt, fun.path[0]);
            return error(ctxt, "modules %yshall not implement a main function");
        };
        const meta = fun.meta as *fn_meta;
        if(!meta.name.pub){
            move_ptr(ctxt, fun.path[1]);
            return error(ctxt, "main must be a public function");
        };
        if(meta.fn_type != primitive::VOID){
            move_ptr(ctxt, fun.path[1]);
            return error(ctxt, "main must be of void type");
        };
        const params = (meta.params as *ast).meta as *param_meta;
        if(len(params.names) > 0){
            move_ptr(ctxt, fun.path[1]);
            return error(ctxt, "main must recieve no arguments");
        };
        gen_file(ctxt, tokens, buffer, head)?;
    case void =>
        if(main){
            if(max > 2){
                move_ptr(ctxt, tokens[max - 2]);
            };
            return error(ctxt, "no main function was defined");
        };
    };
    return comp_obj {
        tokens = tokens,
        buffer = buffer,
        ast_head = head,
        ctxt = ctxt,
    };
};

// generates the qbe IR of a given context and ast `head` and writes it to
// `buffer`. returns an error if any compilation error occurs.
fn gen_file(ctxt: *context, tokens: []token, buffer: *memio::stream,
    head: nullable *ast) (void | COMPERR) = {
    for(let node = head; node != null){
        const this = node as *ast;
        switch(this.kind){
        case path_t::CONST_DEF =>
            if(check_for_FFI(ctxt, this.inner as *ast)?){
                node = this.next;
                continue;
            };
            const meta = this.meta as *var_meta;
            if(meta.name.pub){
                fmt::fprintf(buffer, "export ")!;
            };
            fmt::fprintf(buffer, "data ${} = {{ ", meta.name.id)!;

            assert(!untyped(meta.name.itype));
            const tpe = meta.name.itype;
            if(is_subtype(tpe, primitive::STR)){
                const inner = this.inner as *ast;
                let length = 0z;
                let slices = []: []str;
                defer free(slices);
                const max = len(inner.path);
                for(let i = 0z; i < max; i += 1){
                    length += true_size(inner.path[i].val as str);
                    append(slices, inner.path[i].val as str)!;
                    if(i + 1 < max){
                        if(!comp_tk(inner.path[i + 1].val, operator::PLS)){
                            move_ptr(ctxt, inner.path[i + 1]);
                            return error(ctxt, "invalid string operator");
                        };
                        i += 1;
                    };
                };
                fmt::fprintf(buffer, "l {}", length)!;
                for(let slc .. slices){
                    fmt::fprintf(buffer, ", b \"{}\"", slc)!;
                };
                fmt::fprintln(buffer, " }")!;
            } else if(is_subtype(tpe, primitive::NUMBER)){
                const inner = this.inner as *ast;
                let (acc, ini): (size, size) =
                    match(inner.path[0].val){
                    case let n: size => yield (n, 1z);
                    case let o: operator =>
                        yield (inner.path[1].val as size, 2z);
                    };
                const max = len(inner.path);
                for(let i = ini; i < max; i += 2){
                    const num = inner.path[i + 1].val as size;
                    switch(inner.path[i].val as operator){
                    case operator::PLS =>
                        acc += num;
                    case operator::MIN =>
                        acc -= num;
                    case operator::MUL =>
                        acc *= num;
                    case operator::IDIV =>
                        acc /= num;
                    case operator::FDIV =>
                        move_ptr(ctxt, inner.path[i]);
                        return error(ctxt, "invalid float division between integers");
                    case operator::MOD =>
                        acc &= num;
                    case operator::LEQ =>
                        if(acc <= num){
                            acc = 1;
                        } else {
                            acc = 0;
                        };
                    case operator::GEQ =>
                        if(acc >= num){
                            acc = 1;
                        } else {
                            acc = 0;
                        };
                    case operator::LST =>
                        if(acc > num){
                            acc = 1;
                        } else {
                            acc = 0;
                        };
                    case operator::GTT =>
                        if(acc < num){
                            acc = 1;
                        } else {
                            acc = 0;
                        };
                    case operator::EQL =>
                        if(acc == num){
                            acc = 1;
                        } else {
                            acc = 0;
                        };
                    case operator::NEQ =>
                        if(acc != num){
                            acc = 1;
                        } else {
                            acc = 0;
                        };
                    case operator::SHL =>
                        acc <<= num;
                    case operator::SHR =>
                        acc >>= num;
                    case operator::LOR =>
                        acc |= num;
                    case operator::LAND =>
                        acc &= num;
                    case operator::BOR =>
                        if(acc != 0 || num != 0){
                            acc = 1;
                        } else {
                            acc = 0;
                        };
                    case operator::BAND =>
                        if(acc != 0 && num != 0){
                            acc = 1;
                        } else {
                            acc = 0;
                        };
                    case operator::NOT =>
                        if(acc != 0){
                            acc = 0;
                        } else {
                            acc = 1;
                        };
                    case =>
                        assert(false, "unreachable");
                    };
                };
                fmt::fprintfln(buffer, "{} {} }}", qbe_t(tpe), acc)!;
            } else {
                assert(false, "TODO: constant ratios");
            };
        case path_t::FUN_DEF =>
            const meta = this.meta as *fn_meta;
            if(meta.used && meta.ffi is void){
                gen_fun(ctxt, tokens, buffer, this)?;
            };
        case => void;
        };
        node = this.next;
    };
    const lit_c = len(ctxt.literals);
    for(let lit = 0z; lit < lit_c; lit += 1){
        fmt::fprintfln(buffer, "data $lit.{} = {{ l {}, b \"{}\" }}", 
            lit, true_size(ctxt.literals[lit]), ctxt.literals[lit])!;
    };
};

// checks if a given definition is an FFI symbol
fn check_for_FFI(ctxt: *context, node: *ast) (bool | COMPERR) = {
    if(!comp_tk(node.path[0].val, symbol::FFI)){
        return false;
    };
    if(len(node.path) > 2){
        move_ptr(ctxt, node.path[2]);
        return error(ctxt, "cannot operate on FFI symbols");
    };
    return true;
};

// generates the qbe IR for a function definition
fn gen_fun(ctxt: *context, tokens: []token, buffer: *memio::stream,
    this: *ast) (void | COMPERR) = {
    const meta = this.meta as *fn_meta;
    const local_scp = scope {
        vars = [],
        upper = &ctxt.glob,
        effects = meta.effects,
    };
    defer free(local_scp.vars);

    const param_l = (meta.params as *ast).meta as *param_meta;
    const p_max = len(param_l.names);
    
    const params = []: []*ast;
    defer free(params);
    defer for(let var ..& params) free_nodes(var);

    for(let p = 0z; p < p_max; p += 1){
        const pdef = new_node(tokens, param_l.at[p]);
        pdef.kind = path_t::DECL;
        pdef.meta = alloc(var_meta {
            lin = param_l.pos[p].lin,
            cln = param_l.pos[p].cln,
            ffi = void,
            mod = void,
            glob = false,
            name = param_l.names[p],
        })!;
        append(local_scp.vars, pdef)!;
        append(params, pdef)!;
    };
    ctxt.scp = &local_scp;
    const (body, _) = eval_scope(ctxt, tokens, meta.scope_begin, meta.fn_type)?;
    const scp_tpe = (body.meta as *expr_meta).tpe;

    if(!is_subtype(scp_tpe, meta.fn_type)){
        move_ptr(ctxt, body.path[len(body.path) - 1]);
        return error(ctxt, "mismatch between %bfunction return type (%g{}%b)%r "
            "and %bscope evaluation type (%g{}%b)",
            strtoken(meta.fn_type), strtoken(scp_tpe));
    };
    ctxt.scp = &ctxt.glob;
    this.inner = body;

    if(meta.name.pub){
        fmt::fprintf(buffer, "export ")!;
    };
    fmt::fprintf(buffer, "function ")!;
    if(meta.fn_type == primitive::VOID ||
        meta.fn_type == primitive::UNIT){
        fmt::fprintf(buffer, "${}(", fix_global(meta))!;
    } else {
        fmt::fprintf(buffer, "{} ${}(", qbe_t(meta.fn_type),
            fix_global(meta))!;
    };
    for(let p = 0z; p < p_max; p += 1){
        fmt::fprintf(buffer, "{} %{}, ", qbe_t(param_l.names[p].itype),
            param_l.names[p].id)!;
    };
    fmt::fprint(buffer, "){\n@start")!;
    gen_scope(ctxt, buffer, body)?;

    const end = len(this.path) - 2;
    if(meta.fn_type == primitive::VOID){
        fmt::fprintln(buffer, "\n\tcall $rt_exit(w 0)\n\thlt\n}")!;
    } else if(meta.fn_type == primitive::UNIT){
        fmt::fprintln(buffer, "\n\tret\n}")!;
    } else {
        fmt::fprintln(buffer, "}")!;
    };
};

// generates the qbe IR for a given scope
fn gen_scope(ctxt: *context, buffer: *memio::stream, node: nullable *ast) (void | COMPERR) = {
    const node = node as *ast;
    const scp_meta = node.meta as *expr_meta;
    const list = scp_meta.members;
    const scp = scp_meta.scp as *scope;
    
    const safe = ctxt.scp;
    ctxt.scp = scp;
    for(let this ..& list){
        switch(this.kind){
        case path_t::DECL, path_t::CONST_DEF =>
            const meta = this.meta as *var_meta;
            fmt::fprintfln(buffer, "\n\tdbgloc {}, {}",
                this.path[0].lin + 1, this.path[0].cln + 1)!;

            gen_exp(ctxt, buffer, this.inner as *ast, meta.name.id, meta.name.itype);
        case path_t::EXPR =>
            const meta = this.meta as *expr_meta;
            const dest = fmt::asprintf("exp.{}", qbe_t(meta.tpe))!;
            defer free(dest);

            fmt::fprintfln(buffer, "\n\tdbgloc {}, {}",
                this.path[0].lin + 1, this.path[0].cln + 1)!;

            gen_exp(ctxt, buffer, this, dest, meta.tpe);
        case path_t::FUN_CALL =>
            fmt::fprintfln(buffer, "\n\tdbgloc {}, {}",
                this.path[0].lin + 1, this.path[0].cln + 1)!;
            gen_funcall(ctxt, buffer, this);
        case =>
            assert(false, fmt::asprintf("TODO: {}", this.kind: int)!);
        };
    };
    ctxt.scp = safe;
};

// generates the qbe IR for a given expression
fn gen_exp(ctxt: *context, buffer: *memio::stream, exp: *ast,
    dest: str, exp_type: primitive) void = {
    const exp_t = qbe_t(exp_type, mode::ASSIGN);
    // TODO: exp.mea is *var_meta
    const exp_meta = exp.meta as *expr_meta;
    const members = exp_meta.members;

    let begin = 1z;
    switch(members[0].kind){
    case path_t::OPERATOR =>
        const temp = memio::dynamic();
        defer io::close(&temp)!;

        fmt::fprintf(&temp, "\t%{} ={} ", dest, exp_t)!;
        begin = 2z;
        switch(members[0].path[0].val as operator){
        case operator::PLS =>
            gen_member(ctxt, buffer, &temp, members[0], exp_type);
            fmt::fprintln(buffer, memio::string(&temp)!)!;
        case operator::MIN =>
            fmt::fprint(&temp, "neg ")!;
            gen_member(ctxt, buffer, &temp, members[0], exp_type);
            fmt::fprintln(buffer, memio::string(&temp)!)!;
        case operator::NOT =>
            fmt::fprint(&temp, "xor ")!;
            gen_member(ctxt, buffer, &temp, members[0], exp_type);
            fmt::fprintfln(buffer, "{}, 18446744073709551615",
                memio::string(&temp)!)!;
        case operator::MAP =>
            assert(false, "TODO");
        case operator::BANG =>
            assert(false, "TODO");
        case =>
            assert(false, "unreachable");
        };
    case path_t::MEMBER =>
        const temp = memio::dynamic();
        defer io::close(&temp)!;

        fmt::fprintf(&temp, "\t%{} ={} ", dest, exp_t)!;
        gen_member(ctxt, buffer, &temp, members[0], exp_type);
        fmt::fprintln(buffer, memio::string(&temp)!)!;
    case path_t::DECL, path_t::CONST_DEF =>
        const temp = memio::dynamic();
        const meta = members[0].meta as *var_meta;
        fmt::fprintf(&temp, "\t%{} ={} ", dest, exp_t)!;

        if(meta.name.glob){
            const name =
                match(meta.ffi){
                case let some: str => yield some;
                case void => yield meta.name.id;
                };
            if(meta.name.itype != primitive::STR){
                fmt::fprintfln(buffer, "\t%{} ={} load{} ${}",
                    meta.name.id, qbe_t(meta.name.itype, mode::ASSIGN),
                    qbe_t(meta.name.itype, mode::LOAD), name)!;
            } else {
                fmt::fprintfln(buffer, "\t%{} =l copy ${}",
                    meta.name.id, name)!;
            };
        };
        if(meta.name.itype == exp_type){
            fmt::fprintfln(&temp, "copy %{}", meta.name.id)!;
        } else if(is_subtype(meta.name.itype, primitive::U64)){
            fmt::fprintfln(&temp, "ext{} %{}",
                qbe_t(meta.name.itype, mode::LOAD), meta.name.id)!;
        } else {
            fmt::fprintfln(&temp, "ext{} %{}",
                qbe_t(meta.name.itype, mode::LOAD), meta.name.id)!;
        };
        fmt::fprint(buffer, memio::string(&temp)!)!;
    case path_t::EXPR =>
        const meta = members[0].meta as *expr_meta;
        const sub_t = meta.tpe;
        const wrap = fmt::asprintf("exp.{}", qbe_t(sub_t))!;
        defer free(wrap);
        gen_exp(ctxt, buffer, members[0], wrap, sub_t);

        fmt::fprintf(buffer, "\t%{} ={} ", dest, exp_t)!;
        if(sub_t == exp_type){
            fmt::fprintfln(buffer, "copy %{}", wrap)!;
        } else if(is_subtype(sub_t, primitive::U64)){
            const new = fmt::asprintf("%{}.{}", dest, qbe_t(sub_t))!;
            defer free(new);
            fmt::fprintfln(buffer, "\t{} ={} extu{} %{}",
                new, exp_t, qbe_t(sub_t), wrap)!;
        } else {
            const new = fmt::asprintf("%{}.{}", dest, qbe_t(sub_t))!;
            defer free(new);

            fmt::fprintfln(buffer, "\t{} ={} exts{} %{}",
                new, exp_t, qbe_t(sub_t), wrap)!;
        };
    case path_t::FUN_CALL =>
        gen_funcall(ctxt, buffer, members[0], dest);
        fmt::fprintln(buffer)!;
    case =>
        assert(false, "unreachable");
    };
    const max = len(members);
    if(is_subtype(exp_type, primitive::STR)){
        for(let i = begin; i < max; i += 2){
            assert(false, "TODO");
        };
    } else if(is_subtype(exp_type, primitive::NUMBER)){
        for(let i = begin; i < max; i += 2)
        switch(members[i].path[0].val as operator){
        case operator::PLS, operator::MIN, operator::MUL, operator::IDIV =>
            const memb: str =
                match(members[i + 1].meta){
                case let var: *var_meta =>
                    if(var.name.glob){
                        const name =
                            match(var.ffi){
                            case let some: str => yield some;
                            case void => yield var.name.id;
                            };
                        if(is_subtype(var.name.itype, primitive::NUMBER)){
                            fmt::fprintfln(buffer, "\t%{} ={} load{} ${}",
                                var.name.id, qbe_t(var.name.itype, mode::ASSIGN),
                                qbe_t(var.name.itype, mode::LOAD), name)!;
                        } else {
                            fmt::fprintfln(buffer, "\t%{} =l copy ${}",
                                var.name.id, name)!;
                        };
                    };
                    yield
                    if(var.name.itype == exp_type){
                        yield fmt::asprintf("%{}", var.name.id)!;
                    } else if(is_subtype(var.name.itype, primitive::U64)){
                        const wrap = fmt::asprintf("%{}.{}", var.name.id, exp_t)!;
                        fmt::fprintfln(buffer, "\t{} ={} extu{} %{}",
                            wrap, exp_t, qbe_t(var.name.itype), var.name.id)!;
                        yield wrap;
                    } else {
                        const wrap = fmt::asprintf("%{}.{}", var.name.id, exp_t)!;
                        fmt::fprintfln(buffer, "\t{} ={} exts{} %{}",
                            wrap, exp_t, qbe_t(var.name.itype), var.name.id)!;
                        yield wrap;
                    };
                case let call: *funcall_meta =>
                    const f_meta = call.fun.meta as *fn_meta;
                    const f_dest = fmt::asprintf("{}.{}", f_meta.name.id,
                        qbe_t(f_meta.fn_type))!;
                    let wrap = strings::concat("%", f_dest)!;
                    gen_funcall(ctxt, buffer, members[i + 1], f_dest);

                    yield if(f_meta.fn_type == exp_type){
                        fmt::fprintln(buffer, "")!;
                        yield wrap;
                    } else if(is_subtype(f_meta.fn_type, primitive::U64)){
                        const old = wrap;
                        wrap = fmt::asprintf("%{}.{}", f_meta.name.id, exp_t)!;
                        fmt::fprintfln(buffer, "\t{} ={} extu{} %{}",
                            wrap, exp_t, qbe_t(f_meta.fn_type), old)!;
                        free(old);
                        yield wrap;
                    } else {
                        const old = wrap;
                        wrap = fmt::asprintf("%{}.{}", f_meta.name.id, exp_t)!;
                        fmt::fprintfln(buffer, "\t{} ={} exts{} %{}",
                            wrap, exp_t, qbe_t(f_meta.fn_type), old)!;
                        free(old);
                        yield wrap;
                    };
                case let exp: *expr_meta =>
                    let wrap = fmt::asprintf("%exp.{}", qbe_t(exp.tpe))!;
                    gen_exp(ctxt, buffer, members[i + 1], dest, exp_type);

                    yield if(exp.tpe == exp_type){
                        yield wrap;
                    } else if(is_subtype(exp.tpe, primitive::U64)){
                        const old = wrap;
                        wrap = fmt::asprintf("%exp.{}", exp_t)!;
                        fmt::fprintfln(buffer, "\t{} ={} extu{} %{}",
                            wrap, exp_t, qbe_t(exp.tpe), old)!;
                        free(old);
                        yield wrap;
                    } else {
                        const old = wrap;
                        wrap = fmt::asprintf("%exp.{}", exp_t)!;
                        fmt::fprintfln(buffer, "\t{} ={} exts{} %{}",
                            wrap, exp_t, qbe_t(exp.tpe), old)!;
                        free(old);
                        yield wrap;
                    };
                case =>
                    yield match(members[i + 1].path[0].val){
                    case let num: size =>
                        yield fmt::asprint(num)!;
                    case let txt: str =>
                        yield fmt::asprintf("$lit.{}", push_str(ctxt, txt))!;
                    case let kwd: keyword =>
                        yield switch(kwd){
                        case keyword::TODO =>
                            yield
                            if(is_subtype(exp_type, primitive::STR)){
                                yield strings::dup("0")!;
                            } else {
                                yield strings::dup("$empty.str")!;
                            };
                        case keyword::FAIL =>
                            assert(false, "TODO: error types");
                            yield "";
                        case =>
                            assert(false, "unreachable");
                            yield "";
                        };
                    case =>
                        assert(false, strtoken(members[i + 1].path[0].val));
                        yield "";
                    };
                };
            defer free(memb);
            const inst =
                switch(members[i].path[0].val as operator){
                case operator::PLS => yield "add";
                case operator::MIN => yield "sub";
                case operator::MUL => yield "mul";
                case operator::IDIV =>
                    yield if(is_subtype(exp_type, primitive::U64)){
                        yield "udiv";
                    } else {
                        yield "div";
                    };
                case =>
                    assert(false);
                    yield "";
                };
            fmt::fprintfln(buffer, "\t%{0} ={1} {2} %{0}, {3}",
                dest, exp_t, inst, memb)!;
        case =>
            assert(false, "TODO");
        };
    } else if(is_subtype(exp_type, primitive::RATIO)){
        assert(false, "TODO");
    };
    if(exp_meta.rets){
        fmt::fprintfln(buffer, "\tret %{}", dest)!;
    };
};

// generates the qbeIR for a given funcall. if `dest` is set, the return value
// is assigned to it. `dest` shall not have qbe temporaries prefix.
fn gen_funcall(ctxt: *context, buffer: *memio::stream,
    this: *ast, dest: (void | str) = void) void = {
    const meta = this.meta as *funcall_meta;
    const temp = memio::dynamic();
    defer io::close(&temp)!;

    const fun = meta.fun;
    const f_meta = fun.meta as *fn_meta;
    const tpe = f_meta.fn_type;
    const exp_t = qbe_t(tpe);
    const p_meta = (f_meta.params as *ast).meta as *param_meta;
    match(dest){
    case let wrap: str =>
        if(tpe != primitive::UNIT){
            fmt::fprintf(&temp, "\t%{} ={} call ${}(",
                wrap, exp_t, fix_global(f_meta))!;
        } else {
            fmt::fprintf(&temp, "\tcall ${}(",
                fix_global(f_meta))!;    
        };
    case void =>
        fmt::fprintf(&temp, "\tcall ${}(",
            fix_global(f_meta))!;
    };
    const max = len(p_meta.names);
    assert(len(meta.args) == max);
    for(let a = 0z; a < max; a += 1){
        const arg = meta.args[a];
        const arg_t = qbe_t(p_meta.names[a].itype);
        match(arg.meta){
        case let expr: *expr_meta =>
            const wrap = fmt::asprintf("arg.{}.{}", arg_t, a)!;
            defer free(wrap);

            gen_exp(ctxt, buffer, arg, wrap, p_meta.names[a].itype);
            fmt::fprintf(&temp, "{} %{}, ", arg_t, wrap)!;
        case let prim: primitive =>
            match(arg.path[0].val){
            case let num: size => 
                fmt::fprintf(&temp, "{} {}, ", arg_t, num)!;
            case let txt: str =>
                fmt::fprintf(&temp, "{} $lit.{}, ", arg_t,
                    push_str(ctxt, txt))!;
            case let idt: ident =>
                fmt::fprintf(&temp, "{} %{}, ", arg_t, idt.id)!;
            case =>
                assert(false, "unreachable");
            };
        };
    };
    fmt::fprintf(buffer, "{})", memio::string(&temp)!)!;
};

// generates the coresponding move instruction for a given member and fixes any
// casting for the given member type and expected `tpe` type.
fn gen_member(ctxt: *context, header: *memio::stream,
    buffer: *memio::stream, member: *ast, tpe: primitive) void = {
    match(member.path[0].val){
    case let idt: ident =>
        const var =
            match(get_var(ctxt.scp as *scope, idt)){
            case let var: *ast =>
                yield var;
            case void =>
                yield get_mod_var(ctxt, member.path[0],
                    member.path[2].val as ident)!;
            };
        const meta = var.meta as *var_meta;
        if(is_subtype(meta.name.itype, primitive::NUMBER)){
            if(meta.glob){
                const name =
                    match(meta.ffi){
                    case let id: str => yield id;
                    case void => yield idt.id;
                    };
                fmt::fprintfln(header, "\t%{} ={} load{} ${}",
                    meta.name.id, qbe_t(meta.name.itype, mode::ASSIGN),
                    qbe_t(meta.name.itype, mode::LOAD), name)!;
            };
            if(meta.name.itype == tpe){
                fmt::fprintf(buffer, "copy %{}", meta.name.id)!;
            } else if(is_subtype(meta.name.itype, primitive::U64)){
                fmt::fprintf(buffer, "extu{} %{}",
                    qbe_t(meta.name.itype), meta.name.id)!;
            } else {
                fmt::fprintf(buffer, "exts{} %{}",
                    qbe_t(meta.name.itype), meta.name.id)!;
            };
        } else if(meta.name.itype == primitive::STR){
            if(meta.glob){
                fmt::fprintf(buffer, "copy ${}", meta.name.id)!;
            } else {
                fmt::fprintf(buffer, "copy %{}", meta.name.id)!;
            };
        };
    case let kwd: keyword =>
        switch(kwd){
        case keyword::TODO =>
            if(is_subtype(tpe, primitive::STR)){
                fmt::fprint(buffer, "copy $empty.str")!;
            } else {
                fmt::fprint(buffer, "copy 0")!;
            };
        case keyword::FAIL =>
            assert(false, "TODO: error types");
        case =>
            assert(false, "unreachable");
        };
    case let num: size =>
        fmt::fprintf(buffer, "copy {}", num)!;
    case let txt: str =>
        fmt::fprintf(buffer, "copy $lit.{}", push_str(ctxt, txt))!;
    case =>
        assert(false, "unreachable");
    };
};

// evaluates a constant definition. assumes `at` is pointing to the expression's namespace
fn eval_c_def(ctxt: *context, tokens: []token, at: size, pub: bool = false)
    ((*ast, size) | COMPERR) = {
    const max = len(tokens);
    const begin = at;
    let end = at;
    const name = tokens[end].val as ident;

    end += 1;
    let tk = next_tk(ctxt, tokens, end,
        "expected %btype notation%r, but got %y{}")?;
    const tpe = tk;

    if(comp_tk(tk.val, operator::ASG)){
        tk = next_tk(ctxt, tokens, end + 1,
            "expected %buse statement%r, but got %y{}")?;
        if(comp_tk(tk.val, keyword::USE)){
            return eval_use(ctxt, tokens, begin);
        };
    };
    if(!(tpe.val is primitive)){
        move_ptr(ctxt, tpe);
        return error(ctxt,
            "expected %bvalid type notation%r, but got %y{}",
            strtoken(tpe.val));
    };
    end += 1;
    name.pub = pub;
    name.glob = true;
    name.itype = tpe.val as primitive;

    // assignment operator
    end = pop_assert(ctxt, tokens, end, operator::ASG,
        "expected %bconstant definition assignment%r, but got %y{}")?;

    tk = next_tk(ctxt, tokens, end,
        "expected %bconstant expression%r or "
        "%buse statement%r, but got %y{}")?;

    const (val, _end) = eval_c_exp(ctxt, tokens, end, name.itype)?;
    end = pop_assert(ctxt, tokens, _end, symbol::EOL,
        "expectend %bend of line%r, but got %y{}")?;

    const ffi: (void | str) =
        if(comp_tk(val.path[0].val, symbol::FFI)){
            yield (val.path[1].val as ident).id;
        };
    const node = new_node(tokens, begin);
    node.kind = path_t::CONST_DEF;
    node.meta = alloc(var_meta {
        lin = tokens[begin].lin,
        cln = tokens[begin].cln,
        ffi = ffi,
        mod = void,
        glob = true,
        name = name,
    })!;
    node.inner = val;
    node.path = tokens[begin..end];
    return (node, end);
};

// evaluates an "use" statement
fn eval_use(ctxt: *context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, tokens, begin,
        "expected %bmodule binding%r, but got %y{}")?;
    if(!(tk.val is ident)){
        move_ptr(ctxt, tk);
        return error(ctxt,
            "expected %bmodule binding%r, but got %y{}",
            strtoken(tk.val));
    };
    const bind = tk;
    if(get_var(ctxt.scp as *scope, bind.val as ident) is *ast){
        const name = bind.val as ident;
        move_ptr(ctxt, bind);
        return error(ctxt, "namespace %g{}%r already in use", name.id);
    };
    if(get_fun(ctxt, bind.val as ident) is *ast){
        const name = bind.val as ident;
        move_ptr(ctxt, bind);
        return error(ctxt, "namespace %g{}%r already in use", name.id);
    };
    end = pop_assert(ctxt, tokens, end + 1, operator::ASG,
        "expected %bmodule binding assignment%r, but got %y{}")?;
    end = pop_assert(ctxt, tokens, end, keyword::USE,
        "expected %bkeyword \"use\"%r, but got %y{}")?;

    tk = next_tk(ctxt, tokens, end,
        "expected %bmodule path%r, but got %y{}")?;
    if(!(tk.val is str)){
        move_ptr(ctxt, tk);
        return error(ctxt,
            "expected %bmodule path%r, but got %y{}",
            strtoken(tk.val));
    };
    end = pop_assert(ctxt, tokens, end + 1, symbol::EOL,
        "expected %bend of line%r, but got %y{}")?;

    const path = tk.val as str;
    const stdpath = strings::concat(ctxt.libpath, path)!;
    defer free(stdpath);
    const file =
        if(os::exists(stdpath)){
            yield stdpath;
        } else {
            yield path;
        };
    const module = compile(file, ctxt.libpath,
        alloc(memio::dynamic())!)?;
    push_module(ctxt, bind, module)?;
    const node = new_node(tokens, begin);
    node.kind = path_t::IMPORT;
    node.path = tokens[begin..end];

    return (node, end);
};

// evaluates a constant expression
fn eval_c_exp(ctxt: *context, tokens: []token, at: size, hint: primitive)
    ((*ast, size) | COMPERR) = {
    const max = len(tokens);
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, tokens, end,
        "expected %bcontant value%r, but got %y{}")?;

    const node = new_node(tokens, begin);
    node.kind = path_t::CONST_EXP;
    
    if(tk.val is operator){
        const oper = tk.val as operator;
        end += 1;
        if(!is_unary(oper)){
            move_ptr(ctxt, tk);
            return error(ctxt, "invalid use of operator");
        };
        tk = next_tk(ctxt, tokens, end,
            "expected %bcontant value%r, but got %y{}")?;
        end += 1;
        if(oper == operator::LENGTH && !(tk.val is str || tk.val is ident)){
            move_ptr(ctxt, tk);
            return error(ctxt, "invalid argument for length operator");
        } else if(oper != operator::LENGTH){
            if(tk.val is ident){
                move_ptr(ctxt, tk);
                return error(ctxt, "cannot evaluate this at compile time");
            } else if(!(tk.val is size)){
                move_ptr(ctxt, tk);
                return error(ctxt, "invalid compile time constant value");
            };
        };
        tk = next_tk(ctxt, tokens, end,
            "expected %bcontant value%r, but got %y{}")?;
    };
    for(!comp_tk(tk.val, symbol::EOL) && end < max){
        end = eval_c_val(ctxt, tokens, end, hint)?;
        tk = next_tk(ctxt, tokens, end,
            "expected %boperator%r or %bend of line%r, but got %y{}")?;
        if(comp_tk(tk.val, symbol::EOL)) break;

        if(!(tk.val is operator)){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %boperator%r or %bend of line%r, but got %y{}",
                strtoken(tk.val));
        } else if(!is_binary(tk.val as operator)){
            move_ptr(ctxt, tk);
            return error(ctxt, "invalid %bbinary operator");
        };
        end += 1;
        end = eval_c_val(ctxt, tokens, end, hint)?;
        tk = next_tk(ctxt, tokens, end,
            "expected %bcontant value%r, but got %y{}")?;
    };
    node.path = tokens[begin..end];
    return (node, end);
};

// evaluates a constant value
fn eval_c_val(ctxt: *context, tokens: []token, at: size, hint: primitive)
    (size | COMPERR) = {
    let tk = tokens[at];
    match(tk.val){
    case size =>
        if(!is_subtype(primitive::NUMBER, hint)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "mismatch of %bdeclaration type%r ({}) and "
                "%bexpression member type%r ({})",
                strtoken(hint), strtoken(primitive::NUMBER));
        };
        return at + 1;
    case str =>
        if(!is_subtype(primitive::STR, hint)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "mismatch of %bdeclaration type%r (%g{}%r) and "
                "%bexpression member type%r (%g{}%r)",
                strtoken(hint), strtoken(primitive::STR));
        };
        return at + 1;
    case let sym: symbol =>
        if(sym == symbol::FFI){
            tk = next_tk(ctxt, tokens, at + 1,
                "expected %blink symbol%r, but got %y{}")?;
            return at + 2;
        } else {
            move_ptr(ctxt, tk);
            return error(ctxt, "unexpected %y{}%r found here", strtoken(sym));
        };
    case let idt: ident =>
        move_ptr(ctxt, tk);
        return error(ctxt, "cannot evaluate {} at compile time", strtoken(idt));
    case =>
        move_ptr(ctxt, tk);
        return error(ctxt, "invalid constant value ({})", strtoken(tk.val));
    };
};

// evaluates a function definition
fn eval_fun_def(ctxt: *context, tokens: []token, at: size, pub: bool = false)
    ((*ast, size) | COMPERR) = {
    const max = len(tokens);
    const begin = at;
    let end = at;
    let tk = tokens[end];

    assert(comp_tk(tk.val, keyword::FN));
    end += 1;

    // function name
    tk = next_tk(ctxt, tokens, end,
        "expected %bvalid function name%d, but got %r{}")?;
    if(!((tk.val) is ident)){
        move_ptr(ctxt, tk);
        return error(ctxt, "expected %bvalid function name%r, but got %y{}",
            strtoken(tk.val));
    };
    const name = tk.val as ident;
    name.pub = pub;
    const (param, _end) = eval_param_l(ctxt, tokens, end + 1)?;
    end = _end;

    // function type
    tk = next_tk(ctxt, tokens, end,
        "expected %bvalid function type notation%r, but got %y{}")?;
    if(!((tk.val) is primitive)){ // TODO: agregate types (i.e. "|| is ident")
        move_ptr(ctxt, tk);
        return error(ctxt, "expected %bvalid function type%r, but got %y{}",
            strtoken(tk.val));
    };
    const tpe = tk.val as primitive;
    end += 1;

    // function assignment
    end = pop_assert(ctxt, tokens, end, operator::ASG,
        "expected %bfunction body assignment%r, but got %y{}")?;

    const (efx, ffi, _end) = eval_efx(ctxt, tokens, end)?;
    end = _end;
    const s_begin = end;
    if(ffi is void){
        end = skip_scope(ctxt, tokens, end)?;
    };
    end = pop_assert(ctxt, tokens, end, symbol::EOL,
        "expected %bend of line%r, but got %y{}")?;

    const node = new_node(tokens, begin);
    node.kind = path_t::FUN_DEF;
    node.meta = alloc(fn_meta {
        lin = tokens[begin].lin,
        cln = tokens[begin].cln,
        ffi = ffi,
        mod = void,
        used = pub || ffi is str,
        name = name,
        origin = void,
        params = param,
        fn_type = tpe,
        effects = efx,
        scope_begin = s_begin,
    })!;
    node.path = tokens[begin..end];
    return (node, end);
};

// evaluates a function tag setpath
fn eval_efx(ctxt: *context, tokens: []token, at: size)
    (([]tkval, (void | str), size) | COMPERR) = {
    let end = at;
    let efx = []: []tkval;
    let ffi: (void | str) = void;
    let tk = next_tk(ctxt, tokens, end,
        "expected %beffect tag%r or %bscope definition%r, but got %y{}")?;
    if(tk.val is ident || comp_tk(tk.val, keyword::DO)){
        append(efx, tk.val)!;
        end += 1;
        tk = next_tk(ctxt, tokens, end,
            "expected %beffect tag list continuation%r or "
            "%bscope definition%r, but got %y{}")?;

        if(comp_tk(tk.val, symbol::FFI)){
            end += 1;
            tk = next_tk(ctxt, tokens, end,
                "expected %blink symbol%r but got %y{}")?;
            if(!(tk.val is ident)){
                move_ptr(ctxt, tk);
                return error(ctxt, "expected %blink symbol%r but got %y{}",
                    strtoken(tk.val));
            };
            end += 1;
            ffi = (tk.val as ident).id;
        } else if(!comp_tk(tk.val, symbol::LFT_CURLY)){
            if(!comp_tk(tk.val, operator::BAND)){
                move_ptr(ctxt, tk);
                return error(ctxt,
                "expected %beffect tag list continuation%r or "
                "%bscope definition%r, but got %y{}",
                strtoken(tk.val));
            };
        };
        for(ffi is void && comp_tk(tk.val, operator::BAND)){
            if(comp_tk(efx[0], keyword::DO)){
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "the %bdo%r effect tag shall be fallowed by no additional tags");
            };
            tk = next_tk(ctxt, tokens, end,
                "expected %beffect tag list continuation%r or "
                "%bscope definition%r, but got %y{}")?;
            end += 1;
            if(!(tk.val is ident || comp_tk(tk.val, keyword::DO))){
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "expected %beffect tag list continuation%r or "
                    "%bscope definition%r, but got %y{}",
                    strtoken(tk.val));
            };
            for(let tag .. efx){
                if(comp_tk(tk.val, tag)){
                    move_ptr(ctxt, tk);
                    return error(ctxt, "duplicated effect tag");
                };
            };
            append(efx, tk.val)!;
            tk = next_tk(ctxt, tokens, end,
                "expected %beffect tag list continuation%r or "
                "%bscope definition%r, but got %y{}")?;
            if(!comp_tk(tk.val, symbol::LFT_CURLY)){
                if(!comp_tk(tk.val, operator::BAND)){
                    move_ptr(ctxt, tk);
                    return error(ctxt,
                        "expected %beffect tag list continuation%r or "
                        "%bscope definition%r, but got %y{}",
                        strtoken(tk.val));
                };
                end += 1;
            };
        };
    };
    return (efx, ffi, end);
};

// validades effects for a given called function and a caller set of tags
fn validate_efx(ctxt: *context, called: *fn_meta, caller: []tkval)
    (void | COMPERR) = {
    if(len(caller) > 0 && comp_tk(caller[0], keyword::DO)){
        return;
    };
    match(called.origin){
    case let mod: str =>
        for(let lr_tag .. caller){
            if(mod == (lr_tag as ident).id) return;
        };
        const help = fmt::asprintf(
            "%gtry doing %p\"%d= %b{} %y{{%p\""
            "%g in the function scope definition",
            mod)!;
        defer free(help);
        return error(ctxt,
            "the function %b{}%r is from the module "
            "%g{}%r, but the caller function doesn't "
            "implement this effect tag\n{}",
            called.name.id, mod, help);
    case void =>
        for(let ld_tag .. called.effects){
            let found = false;
            for(let lr_tag .. caller){
                if(comp_tk(ld_tag, lr_tag)){
                    found = true;
                    break;
                };
            };
            if(!found){
                const tag = (ld_tag as ident).id;
                const help = fmt::asprintf(
                    "%gtry doing %p\"%d= %b{} %y{{%p\""
                    "%g in the function scope definition",
                    tag)!;
                defer free(help);
                return error(ctxt,
                    "the function %b{}%r implements the effect "
                    "%g{}%r, but the caller function doesn't\n{}",
                    called.name.id, tag, help);
            };
        };
    };
};

// evaluates a param list
fn eval_param_l(ctxt: *context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const begin = pop_assert(ctxt, tokens, at, symbol::LFT_PAR,
        "expected %bvalid parameter list%r, but got %y{}")?;
    let end = begin;
    let tk = tokens[end];
    let meta = param_meta { ... };
    let idx = 0z;
    for(!comp_tk(tk.val, symbol::RGT_PAR)){
        tk = next_tk(ctxt, tokens, end,
            "expected %bvalid parameter name%r or %bend of list%r, but got %y{}")?;
        if(!(tk.val is ident)){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bvalid parameter name%r "
                "or %bend of list%r, but got %y{}",
                strtoken(tk.val));
        };
        append(meta.at, end)!;
        append(meta.pos, tk)!;
        append(meta.names, tk.val as ident)!;
        
        end += 1;
        tk = next_tk(ctxt, tokens, end,
            "expected %bvalid parameter type%r, but got %y{}")?;
        if(!(tk.val is primitive)){ // TODO: composite types
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bvalid parameter type%r, but got %y{}",
                strtoken(tk.val));
        };
        end += 1;
        meta.names[idx].itype = tk.val as primitive;
        idx += 1;
        tk = next_tk(ctxt, tokens, end,
            "expected %bparameter list continuation%r or %bend of list%r, but got %y{}")?;
        if(comp_tk(tk.val, symbol::COMMA)){
            end += 1;
            tk = next_tk(ctxt, tokens, end,
            "expected %bparameter list continuation%r or %bend of list%r, but got %y{}")?;
        };
    };
    end += 1;
    const node = new_node(tokens, begin);
    node.kind = path_t::PARAM_LIST;
    node.path = tokens[begin..end];
    node.meta = alloc(meta)!;
    return (node, end);
};

// skips a scope definition
fn skip_scope(ctxt: *context, tokens: []token, at: size) (size | COMPERR) = {
    const max = len(tokens);
    let end = pop_assert(ctxt, tokens, at, symbol::LFT_CURLY,
        "expected %bvalid scope definition%r, but got %y{}")?;
    for(end < max; end += 1){
        if(comp_tk(tokens[end].val, symbol::LFT_CURLY)){
            end = skip_scope(ctxt, tokens, end)?;
        } else if(comp_tk(tokens[end].val, symbol::RGT_CURLY)){
            return end + 1;
        };
    };
    move_ptr(ctxt, tokens[end - 1]);
    return error(ctxt, "expected %bend of scope%r, but got %y{}",
        strtoken(eof));
};

// evaluates a scope.
// remember to set the scope field of context before calling this.
fn eval_scope(ctxt: *context, tokens: []token, at: size, hint: primitive = primitive::ANY)
    ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = pop_assert(ctxt, tokens, at, symbol::LFT_CURLY,
        "expected %bvalid scope definition%r, but got %y{}")?;

    const node = new_node(tokens, begin);
    node.kind = path_t::SCOPE;
    const meta = expr_meta {
        rets = false,
        tpe = hint,
        members = [],
        scp = ctxt.scp,
    };
    let tpe = primitive::ANY;
    let tk = next_tk(ctxt, tokens, end,
        "expected %bvalid expression%r, but got %y{}")?;
    for(!comp_tk(tk.val, symbol::RGT_CURLY)){
        match(tk.val){
        case let oper: operator =>
            if(oper == operator::MAP){
                const (exp, _end) = eval_expression(ctxt, tokens, end + 1, hint)?;
                end = _end;
                meta.rets = true;
                append(meta.members, exp)!;
                match(exp.meta){
                case let e_meta: *expr_meta =>
                    e_meta.rets = true;
                    tpe = push_type(ctxt, tpe, e_meta.tpe, tk)?;
                case let v_meta: *var_meta =>
                    tpe = push_type(ctxt, tpe, v_meta.name.itype, tk)?;
                };
            } else {
                move_ptr(ctxt, tk);
                return error(ctxt, "expected %bvalid expression%r, but got %y{}",
                    strtoken(oper));
            };
        case =>
            const (exp, _end) = eval_expression(ctxt, tokens, end)?;
            end = _end;
            append(meta.members, exp)!;
            match(exp.meta){
            // parsed expression is being returned
            case let e_meta: *expr_meta =>
                if(e_meta.rets){
                    move_ptr(ctxt, tk);
                    return error(ctxt, "inner expression %greturns a value%r, "
                        "but the root %gdoes not");
                };
            case *var_meta =>
                push_var(ctxt, exp)?;
            case *funcall_meta => void;
            };
        };
        end = pop_assert(ctxt, tokens, end, symbol::EOL,
            "expected %bend of line%r, but got %y{}")?;
        tk = next_tk(ctxt, tokens, end,
            "expected %bvalid expression%r, but got %y{}")?;
    };
    end = pop_assert(ctxt, tokens, end, symbol::RGT_CURLY,
        "expected %bend of scope%r, but got %y{}")?;

    if(tpe == primitive::ANY) tpe = primitive::UNIT;
    if(!is_subtype(tpe, meta.tpe)){
        move_ptr(ctxt, tk);
        return error(ctxt,
            "mismatch between %bfunction type %g({}%b)%r "
            "and %bscope evaluation type %g({}%b)%r",
            strtoken(meta.tpe), strtoken(tpe));
    };

    node.meta = alloc(meta)!;
    node.path = tokens[begin..end];
    return (node, end);
};

// evaluates a generic expression
fn eval_expression(ctxt: *context, tokens: []token, at: size, hint: primitive = primitive::ANY)
    ((*ast, size) | COMPERR) = {
    let tk = tokens[at];
    match(tk.val){
    case let kwd: keyword =>
        switch(kwd){
        case keyword::LET =>
            return eval_decl(ctxt, tokens, at)?;
        case =>
            move_ptr(ctxt, tk);
            return error(ctxt, "TODO: statements");
        };
    case =>
        return eval_abbs_exp(ctxt, tokens, at, hint)?;
    };
};

// evaluates a namespace declaration
fn eval_decl(ctxt: *context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    assert(comp_tk(tokens[at].val, keyword::LET));

    let tk = next_tk(ctxt, tokens, end + 1, "expected %bdeclaration's namespace%r, "
        "but got %y{}")?;
    end += 1;
    if(!(tk.val is ident)){
        move_ptr(ctxt, tk);
        return error(ctxt, "expected %bdeclarations's namespace%r, but got %y{}",
            strtoken(tk.val));
    };
    const name = tk.val as ident;

    tk = next_tk(ctxt, tokens, end + 1, "expected %btype notation%r or "
        "%bvalue assignment%r, but got %y{}")?;
    end += 1;

    const node = new_node(tokens, begin);
    node.kind = path_t::DECL;
    match(tk.val){
    case let prim: primitive =>
        end = pop_assert(ctxt, tokens, end + 1, operator::ASG,
            "exprected %bvalue assignment%r, but got %y{}")?;
        const eq = end;
        const (exp, _end) = eval_expression(ctxt, tokens, end, prim)?;
        end = _end;
        node.inner = exp;
        match(exp.meta){
        case let meta: *expr_meta =>
            if(meta.rets){
                assert(comp_tk(tokens[eq + 1].val, operator::MAP));
                move_ptr(ctxt, tokens[eq + 1]);
                return error(ctxt,
                    "cannot return a value from the right side of an assigntment");
            };
            name.itype = push_type(ctxt, meta.tpe, prim, tokens[eq])?;
        case let meta: *var_meta =>
            name.itype = push_type(ctxt, meta.name.itype, prim, tokens[eq])?;
        };
    case let ctpe: ident =>
        assert(false, "TODO: composite types");
    case let oper: operator =>
        if(oper != operator::ASG){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %value bassignment%r, but got %y{}");
        };
        const eq = end;
        const (exp, _end) = eval_expression(ctxt, tokens, end + 1)?;
        end = _end;
        node.inner = exp;
        match(exp.meta){
        case let meta: *expr_meta =>
            if(meta.rets){
                assert(comp_tk(tokens[eq + 1].val, operator::MAP));
                move_ptr(ctxt, tokens[eq + 1]);
                return error(ctxt, "cannot return a value from the right side of an assigntment");
            };
            if(untyped(meta.tpe)){
                move_ptr(ctxt, tk);
                return error(ctxt, "cannot infer expression type");
            };
            name.itype = meta.tpe;
        case let meta: *var_meta =>
            name.itype = meta.name.itype;
        };
    };
    node.path = tokens[begin..end];
    node.meta = alloc(var_meta {
        lin = tokens[begin].lin,
        cln = tokens[begin].cln,
        ffi = void,
        mod = void,
        glob = false,
        name = name,
    })!;
    return (node, end);
};

// evaluates arithmetic, boolean, binary and string expressions
fn eval_abbs_exp(ctxt: *context, tokens: []token, at: size, hint: primitive = primitive::ANY)
    ((*ast, size) | COMPERR) = {
    const max = len(tokens);
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, tokens, end,
        "expected %bexpression member%r, but got %y{}")?;

    let tpe = hint;
    let membs = []: []*ast;
    if(tk.val is operator){
        const oper = tk.val as operator;
        if(!is_unary(oper)){
            move_ptr(ctxt, tk);
            return error(ctxt, "invalid use of operator");
        };
        const op = new_node(tokens, end);
        op.kind = path_t::OPERATOR;
        append(membs, op)!;
        end += 1;
        tk = next_tk(ctxt, tokens, end,
            "expected %bexpression member%r, but got %y{}")?;
    };
    for(!(comp_tk(tk.val, symbol::RGT_PAR) || comp_tk(tk.val, symbol::COMMA) ||
        comp_tk(tk.val, symbol::EOL)) && end < max){
        const (mem_l, _end) = eval_member(ctxt, tokens, end, tpe)?;
        end = _end;
        tk = next_tk(ctxt, tokens, end, "expected %btype casting%r or "
            "%bexpression continuation%r, but got %y{}")?;
        if(tk.val is primitive){ // TODO: composite types
            tpe = cast(ctxt, tpe, tk.val as primitive, tk)?;
            end += 1;
        } else {
            match(mem_l.meta){
            case let member_t: primitive =>
                tpe = push_type(ctxt, tpe, member_t, tk, true)?;
            case let v_meta: *var_meta =>
                tpe = push_type(ctxt, tpe, v_meta.name.itype, tk, true)?;
            case let e_meta: *expr_meta =>
                tpe = push_type(ctxt, tpe, e_meta.tpe, tk, true)?;
            case let fncall: *funcall_meta =>
                const f_meta = fncall.fun.meta as *fn_meta;
                tpe = push_type(ctxt, tpe, f_meta.fn_type, tk, true)?;
            case =>
                assert(false, "unreachable");
            };
        };
        append(membs, mem_l)!;
        tk = next_tk(ctxt, tokens, end,
            "expected %boperator%r or %bend of line%r, but got %y{}")?;

        if(comp_tk(tk.val, symbol::RGT_PAR) || comp_tk(tk.val, symbol::COMMA) ||
            comp_tk(tk.val, symbol::EOL)) break;

        if(!(tk.val is operator)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "expected %boperator%r or %bend of line%r, but got %y{}",
                strtoken(tk.val));
        } else if(!is_binary(tk.val as operator)){
            move_ptr(ctxt, tk);
            return error(ctxt, "invalid %bbinary operator");
        };
        const op = new_node(tokens, end);
        op.kind = path_t::OPERATOR;
        append(membs, op)!;

        end += 1;
        const (mem_r, _end) = eval_member(ctxt, tokens, end, tpe)?;
        end = _end;
        tk = next_tk(ctxt, tokens, end, "expected %btype casting%r or "
            "%bexpression continuation%r, but got %y{}")?;
        if(tk.val is primitive){ // TODO: composite types
            tpe = cast(ctxt, tpe, tk.val as primitive, tk)?;
            end += 1;
        } else {
            match(mem_r.meta){
            case let member_t: primitive =>
                tpe = push_type(ctxt, tpe, member_t, tk, true)?;
            case let v_meta: *var_meta =>
                tpe = push_type(ctxt, tpe, v_meta.name.itype, tk, true)?;
            case let e_meta: *expr_meta =>
                tpe = push_type(ctxt, tpe, e_meta.tpe, tk, true)?;
            case let fncall: *funcall_meta =>
                const f_meta = fncall.fun.meta as *fn_meta;
                tpe = push_type(ctxt, tpe, f_meta.fn_type, tk, true)?;
            case =>
                assert(false, "unreachable");
            };
        };
        append(membs, mem_r)!;
        tk = next_tk(ctxt, tokens, end,
            "expected %bexpression member%r, but got %y{}")?;
        if(comp_tk(tk.val, symbol::RGT_PAR) ||
            comp_tk(tk.val, symbol::EOL)) break;
    };
    const node = new_node(tokens, begin);
    node.kind = path_t::EXPR;
    node.path = tokens[begin..end];
    node.meta = alloc(expr_meta {
        rets = false,
        tpe = tpe,
        scp = void,
        members = membs,
    })!;
    return (node, end);
};

// evaluates an expression member
fn eval_member(ctxt: *context, tokens: []token, at: size, hint: primitive = primitive::ANY)
    ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, tokens, end,
        "expected %bvalid member%r, but got %y{}")?;
    let tpe = hint;
    match(tk.val){
    case let sym: symbol =>
        if(sym == symbol::LFT_PAR){
            const (exp, _end) = eval_expression(ctxt, tokens, end + 1)?;
            end = pop_assert(ctxt, tokens, _end, symbol::RGT_PAR,
                "expected %bclosing parenthesis%r, but got %y{}")?;
            tk = next_tk(ctxt, tokens, end,
                "expected %btype casting%r or %bexpression continuation%r, "
                "but got %y{}")?;
            if(tk.val is primitive){ // TODO: composite types
                const meta = exp.meta as *expr_meta;
                meta.tpe = cast(ctxt, meta.tpe, tk.val as primitive, tk)?;
                return (exp, end + 1);
            } else {
                return (exp, end);
            };
        } else {
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bvalid member%r, but got %y{}",
                strtoken(tk.val));
        };
    case size =>
        end += 1;
        tk = next_tk(ctxt, tokens, end, "expected %btype casting%r or "
            "%bexpression continuation%r, but got %y{}")?;
        if(tk.val is primitive){ // TODO: composite types
            const new = tk.val as primitive;
            if(is_subtype(tpe, primitive::NUMBER)){
                tpe = cast(ctxt, tpe, new, tk)?;
                end += 1;
            } else {
                move_ptr(ctxt, tk);
                return error(ctxt, "invalid cast of %g{}%r to %g{}",
                    strtoken(primitive::NUMBER), strtoken(new));
            };
        } else {
            tpe = push_type(ctxt, tpe, primitive::NUMBER, tk)?;
        };
    case let idt: ident =>
        // TODO: field access
        match(get_var(ctxt.scp as *scope, idt)){
        case let var: *ast =>
            const meta = var.meta as *var_meta;
            tpe = push_type(ctxt, tpe, meta.name.itype, tk)?;
            return (var, end + 1);
        case =>
            tk = next_tk(ctxt, tokens, end + 1,
                "expected %bexpression continuation%r, but got %y{}")?;
            // funcall
            if(comp_tk(tk.val, symbol::LFT_PAR)){
                return eval_funcall(ctxt, tokens, end);
            } else if((end + 2 < len(tokens) &&
                comp_tk(tokens[end + 1].val, symbol::FIELD)) &&
                tokens[end + 2].val is ident){
                const field = tokens[end + 2].val as ident;
                match(get_mod_var(ctxt, tokens[begin], field)){
                case let var: *ast =>
                    const meta = var.meta as *var_meta;
                    tpe = push_type(ctxt, tpe, meta.name.itype, tk)?;
                    return (var, end + 3);
                case let e: COMPERR =>
                    tk = next_tk(ctxt, tokens, end + 3,
                        "expected %bfunction call%r or %boperator%r, but got %y{}")?;
                    if(comp_tk(tk.val, symbol::LFT_PAR)){
                        return eval_funcall(ctxt, tokens, end);
                    } else {
                        return e;
                    };
                };
            } else {
                move_ptr(ctxt, tk);
                return error(ctxt, "the variable %y{}%r is undefined at this point",
                    idt.id);
            };
        };
    case str =>
        tpe = push_type(ctxt, tpe, primitive::STR, tk)?;
        end += 1;
        // TODO: casting to composite types
    case let kwd: keyword =>
        if(kwd == keyword::TODO){
            if(untyped(tpe)){
                move_ptr(ctxt, tk);
                return error(ctxt, "%gtodo%r cannot infer expression type");
            };
            end += 1;
        } else if(kwd == keyword::FAIL){
            if(false){ // TODO: unions and error types
                move_ptr(ctxt, tk);
                return error(ctxt, "%gerror%r is not a subtype of this expression");
            };
            end += 1;
        } else {
            assert(false, "TODO: statements");
        };
    case =>
        move_ptr(ctxt, tk);
        return error(ctxt, "invalid %bexpression member%r found here");
    };
    const node = new_node(tokens, begin);
    node.kind = path_t::MEMBER;
    node.meta = tpe;
    node.path = tokens[begin..end];
    return (node, end);
};

// evaluates a function call
fn eval_funcall(ctxt: *context, tokens: []token, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    const fun_name = tokens[begin].val as ident;
    const fun =
        match(get_fun(ctxt, fun_name)){
        case let fun: *ast => yield fun;
        case void =>
            yield if(end + 1 < len(tokens) && comp_tk(tokens[end + 1].val, symbol::FIELD)){
                const obj = next_tk(ctxt, tokens, end + 2,
                    "expected %bmodule field access%r, but got %y{}")?;
                if(!(obj.val is ident)){
                    move_ptr(ctxt, obj);
                    return error(ctxt, "expected %bvalid module field%r, but got %y{}%",
                        strtoken(obj.val));
                };
                end += 2;
                yield get_mod_fun(ctxt, tokens[begin], obj.val as ident)?;
            } else {
                const help = undef_tip(fun_name.id);
                move_ptr(ctxt, tokens[at]);
                return error(ctxt, "the function %y{}%r is undefined at this point{}",
                    fun_name.id, help);
            };
        };
    const f_meta = fun.meta as *fn_meta;
    move_ptr(ctxt, tokens[begin]);
    validate_efx(ctxt, f_meta, (ctxt.scp as *scope).effects)?;

    f_meta.used = true;
    const tpe = f_meta.fn_type;
    const arg_l = (f_meta.params as *ast).meta as *param_meta;

    end = pop_assert(ctxt, tokens, end + 1, symbol::LFT_PAR,
        "expected %bfunction call argument list%r, but got %y{}")?;
    
    let tk = next_tk(ctxt, tokens, end,
        "expected %bfunction argument%r, but got %y{}")?;

    const node = new_node(tokens, begin);
    node.kind = path_t::FUN_CALL;

    const list = []: []*ast;
    for(!comp_tk(tk.val, symbol::RGT_PAR)){
        if(len(list) + 1 > len(arg_l.names)){
            move_ptr(ctxt, tk);
            return error(ctxt, "too much arguments in the function call. "
                "the function %g{}%r takes %g{}%r arguments", f_meta.name.id,
                len(arg_l.names));
        };
        const (exp, _end) = eval_expression(ctxt, tokens, end,
            arg_l.names[len(list)].itype)?;
        end = _end;
        append(list, exp)!;

        tk = next_tk(ctxt, tokens, end,
            "expected %bcomma%r or %bclosing parenthesis%r, but got %y{}")?;
        if(comp_tk(tk.val, symbol::COMMA)){
            end += 1;
            tk = next_tk(ctxt, tokens, end,
                "expected %bfunction argument%r, but got %y{}")?;
        };
    };
    if(len(list) < len(arg_l.names)){
        move_ptr(ctxt, tk);
        return error(ctxt, "missing the %b{} argument%r of the function",
            ordnum(len(list) + 1));
    };
    end += 1;
    node.path = tokens[begin..end];
    node.meta = alloc(funcall_meta {
        fun = fun,
        args = list,
    })!;
    return (node, end);
};

// returns the correct IR representation for a given namespace from its metadata
fn fix_global(meta: (*fn_meta | *var_meta)) str = {
    match(meta){
    case let f_meta: *fn_meta =>
        if(f_meta.ffi is str){
            return f_meta.ffi as str;
        } else if(f_meta.mod is str){
            return f_meta.mod as str;
        } else {
            return f_meta.name.id;
        };
    case let v_meta: *var_meta =>
        if(v_meta.ffi is str){
            return v_meta.ffi as str;
        } else {
            return v_meta.name.id;
        };
    };
};

// attempts to update a given current type to a new one, returning an error if
// not possible. if exp is set to true, the error refers to left anf right hands,
// if not, as source and dest types.
fn push_type(ctxt: *context, current: primitive, new: primitive, pos: token, exp: bool = false)
    (primitive | COMPERR) = {
    if(is_subtype(new, current) || current == primitive::ANY){
        if(current == primitive::ANY || current == primitive::NUMBER ||
            current == primitive::RATIO) return new;
        return current;
    } else {
        move_ptr(ctxt, pos);
        if(exp){
            return error(ctxt,
                "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                strtoken(current), strtoken(new));
        } else {
            return error(ctxt, "type mismatch between source %y({})%r and dest %y({})",
                strtoken(new), strtoken(current));
        };
    };
};

// attemps to cast a given current type to a new one, returning an error if it's
// an invalid cast. the error points to the given `pos` token.
fn cast(ctxt: *context, current: primitive, new: primitive, pos: token) (primitive | COMPERR) = {
    if(is_castable(current, new)){
        return new;
    } else {
        move_ptr(ctxt, pos);
        return error(ctxt, "invalid cast of %g{}%r to %g{}",
            strtoken(current), strtoken(new));
    };
};

// checks is a given type is not a solid type
fn untyped(tpe: primitive) bool = {
    return tpe == primitive::ANY || tpe == primitive::NUMBER || tpe == primitive::RATIO;
};

// checks if a given type is castable in another
fn is_castable(this: primitive, that: primitive) bool = {
    if(is_subtype(this, primitive::NUMBER) &&
        is_subtype(that, primitive::NUMBER)) return true;
    return is_subtype(this, that) || is_subtype(that, this);
};

// checks if a given type is a subset of another
fn is_subtype(this: primitive, that: primitive) bool = {
    if(this == primitive::ANY) return true;
    switch(that){
    case primitive::U8, primitive::U16,
        primitive::U32, primitive::U64 =>
        return (this <= that && this >= primitive::U8) || this == primitive::NUMBER;
    case primitive::I8, primitive::I16,
        primitive::I32, primitive::I64 =>
        return (this <= that && this >= primitive::I8) || this == primitive::NUMBER;
    case primitive::F32, primitive::F64 =>
        return (this <= that && this >= primitive::F32) || this == primitive::RATIO;
    case primitive::NUMBER =>
        return this == primitive::NUMBER || is_subtype(that, this);
    case primitive::RATIO =>
        return this == primitive::RATIO || is_subtype(that, this);
    case primitive::VOID =>
        return this == primitive::UNIT || this == primitive::VOID;
    case =>
        return this == that;
    };
};

// returns the actual parsed size of a given string
fn true_size(lit: str) size = {
    const fixed = strings::multireplace(lit,
        ("\\t", "\t"), ("\\b", "\b"),
        ("\\a", "\a"), ("\\r", "\r"),
        ("\\n", "\n"), ("\\f", "\f"),
        ("\\0", "\0"), ("\\\"", "\""))!;
    defer free(fixed);
    return len(fixed);
};

// returns a tip for a given undefined function
fn undef_tip(name: str) str = {
    if(name == "print"){
        return ". %gtry using the module %yio%g with "
            "%p\"%bio%d::%bprint%d()%p\"";
    } else if(name == "printf"){
        return ". %gtry using the module %yio%g with "
            "%p\"%bio%d::%bprintf%d()%p\"";
    } else if(name == "scan"){
        return ". %gtry using the module %yio%g with "
            "%p\"%bio%d::%bscan%d()%p\"";
    } else {
        return "";
    };
};
