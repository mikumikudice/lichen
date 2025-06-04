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
    const (l, c) = get_pos(ctxt);
    return fmt::asprintf("{}:{}:{}", ctxt.name, l, c)!;
};

// calculates token coordinates from source pointer
fn get_pos(ctxt: *context) (size, size) = {
    const max = len(ctxt.src);
    let l = 0z;
    let c = 0z;
    let i = 0z;
    for(i < ctxt.ptr; i += 1){
        c += 1;
        if(ctxt.src[i] == '\n'){
            c = 0;
            l += 1;
        };
    };
    return (l + 1, c + 1);
};

fn inc_ptr(ctxt: *context, amount: size = 1) void = {
    const max = len(ctxt.src);
    for(let i = 0z; i < amount && ctxt.ptr < max; i += 1){
        if(ctxt.src[ctxt.ptr] == '\n'){
            ctxt.begin = ctxt.ptr + 1;
        };
        ctxt.ptr += 1;
    };
};

// function shortcut
fn u8tostr(a: []u8) str = strings::fromutf8(a)!;

// loads the file `fname` and instantiates
// a file parsing object. returns an error
// if such file cannot be opened.
fn load(fname: str, libpath: str, strlits: *[]str, typedefs: *[](*aggregated | *ext_array))
    (context | COMPERR) = {
    // open file or rise an error
    const fsrc = match(os::open(fname)){
    case let f: io::file => yield f;
    case let e: fs::error =>
        return error(void,
            "%rfailed to load %g\"{}\"%r source file: %y{}",
            fname, fs::strerror(e));
    };
    defer io::close(fsrc)!;

    const file = context {
        name = fname, libpath = libpath,
        ptr = 0, last = 0, begin = 0,
        src = [], scp = void,
        tokens = [],
        head = null,
        buffer = alloc(memio::dynamic())!,
        literals = strlits,
        l_arrays = [],
        fun_defs = [],
        typedefs = typedefs,
        modules = [],
        glob = scope {
            effects = [],
            vars = [],
            upper = void,
        },
        scope_owner = void,
        eval_t = eval_kind::NONE,
        fail = false,
        tailcall = false,
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
        case primitive::NUMBER, primitive::RATIO, primitive::ANY =>
            return strings::dup(prm_value[prm])!;
        case =>
            if(prm > primitive::RATIO){
                return fmt::asprintf("type \"{}\"", prm_value[prm])!;
            } else {
                return fmt::asprintf("primitive type \"{}\"", prm_value[prm])!;
            };
        };
    case let opr: operator =>
        return fmt::asprintf("\"{}\" operator", opr_value[opr: int])!;
    case let sym: symbol =>
        return strings::dup(sym_value[sym])!;
    case eof =>
        return strings::dup("end of file")!;
    };
};

fn strtype(tpe: lichen_t) str = {
    if(tpe is primitive){
        return strtoken(tpe as primitive);
    } else if(tpe is *aggregated){
        const agg = tpe as *aggregated;
        switch(agg.kind){
        case keyword::UNION =>
            let variations = &memio::dynamic();
            if(agg.error_val is lichen_t){
                fmt::fprintf(variations, "{}", strtype(agg.error_val as lichen_t))!;
                for(let v .. agg.base){
                    fmt::fprintf(variations, " | {}", strtype(v))!;
                };
            } else {
                fmt::fprint(variations, "fail")!;
                for(let v .. agg.base){
                    fmt::fprintf(variations, " | {}", strtype(v))!;
                };
            };
            return fmt::asprintf("union {}", memio::string(variations)!)!;
        case keyword::RECORD =>
            return fmt::asprintf("record \"{}\"", agg.name)!;
        case keyword::ENUM =>
            return fmt::asprintf("enum \"{}\"", agg.name)!;
        case keyword::LET =>
            const left =
                match(agg.error_val){
                case let t: lichen_t => yield strtype(tpe);
                case => yield strings::dup("fail")!;
                };
            defer free(left);
            assert(len(agg.base) > 0);
            return fmt::asprintf("type {} | {}", left, strtype(agg.base[0]))!;
        case =>
            assert(false, "unreachable");
            return "";
        };
    } else {
        const arr = tpe as *ext_array;
        return fmt::asprintf("{} array", strtype(arr.base))!;
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
    return token {
        pos = ctxt.last,
        begin = ctxt.begin,
        val = val,
    };
};

// forcefully moves the context to the position of the
// given token.
fn move_ptr(ctxt: *context, tk: token) void = {
    ctxt.ptr = tk.pos;
    ctxt.begin = tk.begin;
};

// checks if a given operator is unary
fn is_unary(opr: operator) bool = {
    return opr == operator::LENGTH || opr == operator::NOT ||
        opr == operator::BANG || opr == operator::MIN;
};

// checks if a given operator is a binary
fn is_binary(opr: operator) bool = {
    return opr == operator::EQL || opr == operator::NEQ ||
        opr == operator::LEQ || opr == operator::GEQ ||
        opr == operator::LST || opr == operator::GTT ||
        opr == operator::SHL || opr == operator::SHR ||
        opr == operator::LOR || opr == operator::LAND ||
        opr == operator::BOR || opr == operator::BAND ||
        opr == operator::PLS || opr == operator::MIN ||
        opr == operator::MUL || opr == operator::IDIV ||
        opr == operator::FDIV || opr == operator::MOD;
};

// pulls next token from token array and asserts for buffer overflow/eof
fn next_tk(ctxt: *context, at: size, msg: str)
    (token | COMPERR) = {
    if(at == len(ctxt.tokens)){
        const tk = ctxt.tokens[at - 1];
        ctxt.ptr = tk.pos;
        ctxt.begin = tk.begin;
        return error(ctxt, msg, strtoken(eof));
    };
    return ctxt.tokens[at];
};

// calls next_tk and asserts if said token is equal to `val`
fn pop_assert(ctxt: *context, at: size, val: tkval, msg: str)
    (size | COMPERR) = {
    const tk = next_tk(ctxt, at, msg)?;
    if(!comp_tk(tk.val, val)){
        move_ptr(ctxt, tk);
        return error(ctxt, msg, strtoken(tk.val));
    };
    return at + 1;
};

let count: size = 0;

// allocates a new empty ast node
fn new_node() *ast = {
    count += 1;
    return alloc(ast {
        kind = path_t::EOF,
        path = [],
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
    assert(count > 0);
    count -= 1;
    const node = _node as *ast;
    match(node.meta){
    case void =>
        void;
    case lichen_t =>
        void;
    case let test: *test_meta =>
        io::close(test.line_msg)!;
        free(test.line_msg);
    case let memb: *member_meta =>
        defer free(memb);
        if(memb.val is *ast){
            const val = memb.val as *ast;
            if(val.kind == path_t::EXPR) free_nodes(memb.val as *ast);
        };
    case let meta: *var_meta =>
        defer free(meta);
        if(meta.mod is str) free(meta.mod as str);
        if(node.inner is *ast) free_nodes(node.inner);

    case let exp: *expr_meta =>
        defer free(exp);
        defer free(exp.members);
        for(let memb ..& exp.members){
            match(memb){
            case operator => void;
            case let mem: *ast =>
                free_nodes(mem);
            };
        };
    case let scp: *scope_meta =>
        defer free(scp);
        defer free(scp.members);
        const defs: []*ast = [];
        defer free(defs);
        for(let memb ..& scp.members){
            free_nodes(memb);
            if(memb.kind == path_t::DECL){
                append(defs, memb)!;
            };
        };
        for(let var ..& defs) free(var);
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
        if(fncall.dest is str) free(fncall.dest as str);
    case let array: *array_meta =>
        for(let item ..& array.items){
            free_nodes(item);
        };
        free(array.items);
    case let ifel_block: *if_else_meta =>
        defer free(ifel_block);
        defer free(ifel_block.conds);
        for(let cond ..& ifel_block.conds) free_nodes(cond);
        defer free(ifel_block.bodies);
        for(let body ..& ifel_block.bodies) free_nodes(body);
    };
    if(node.next is *ast){
        free_nodes(node.next);
    };
    if(node.kind != path_t::DECL &&
        node.kind != path_t::CONST_DEF){
        free(node);
    };
};

fn check_shadowing(ctxt: *context, name: token) (void | COMPERR) = {
    match(get_mod(ctxt, name)){
    case let mod: (token, *context) =>
        move_ptr(ctxt, mod.0);
        const dup_pos = gen_pos(ctxt);
        move_ptr(ctxt, name);
        return error(ctxt, "a module binding is already using this namespace. "
            "previously defined at {}", dup_pos);
    case => void;
    };
    match(get_fun(ctxt, name.val as ident)){
    case let fun: *ast =>
        move_ptr(ctxt, fun.path[0]);
        const dup_pos = gen_pos(ctxt);
        move_ptr(ctxt, name);
        return error(ctxt, "a function is already using this namespace. "
            "previously defined at {}", dup_pos);
    case void => void;
    };
    match(get_var(ctxt.scp as *scope, name.val as ident)){
    case let dup: *ast =>
        move_ptr(ctxt, dup.path[0]);
        const dup_pos = gen_pos(ctxt);
        move_ptr(ctxt, name);
        return error(ctxt, "a variable is already using this namespace. "
            "previously defined at {}", dup_pos);
    case => void;
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
fn get_mod_var(ctxt: *context, bind: token, name: ident) (*ast | COMPERR) = {
    move_ptr(ctxt, bind);
    const modname = bind.val as ident;
    const mod = get_mod(ctxt, bind)?;
    for(let var ..& mod.1.glob.vars){
        const meta = var.meta as *var_meta;
        meta.mod = fmt::asprintf("{}.{}", modname.id, meta.name.id)!;
        if(meta.name.id == name.id) return var;
    };
    return error(ctxt,
        "the module %b{} (bound to %g{}%b)%r has no %y{}%r function",
        mod.1.name, modname.id, name.id);
};

// pushes given variable definition to the current scope. returns an
// error if the variable namespace is already in use.
fn push_var(ctxt: *context, var_def: *ast) (void | COMPERR) = {
    const meta = var_def.meta as *var_meta;
    const tok =
        if(meta.name.glob){
            yield var_def.path[0];
        } else {
            yield var_def.path[1];
        };
    // assert for dups
    check_shadowing(ctxt, tok)?;

    const scp = ctxt.scp as *scope;
    append(scp.vars, var_def)!;
};

// fetches the corresponding function definition of `name` from the
// current scope. returns void if no match is found.
fn get_fun(ctxt: *context, name: ident)
    (*ast | void | COMPERR) = {
    for(let fun ..& ctxt.fun_defs){
        const meta = fun.meta as *fn_meta;
        if(meta.name.id == name.id){
            if(meta.ffi is void && !meta.used){
                if(strings::hassuffix(ctxt.name, ".lim")){
                    const mod = strings::rcut(
                        strings::rcut(ctxt.name, ".lim").0, "/").1;
                    meta.mod = fmt::asprintf("{}.{}",
                        mod, meta.name.id)!;
                };
                meta.used = true;
                gen_fun(ctxt, fun)?;
            };
            return fun;
        };
    };
};

// fetches the corresponding function definition of `name` from the module
// bound to `mod`. returns an error if said module or variable do not exist.
fn get_mod_fun(ctxt: *context, bind: token, name: ident)
    (*ast | COMPERR) = {
    move_ptr(ctxt, bind);
    const modname = bind.val as ident;
    const mod = get_mod(ctxt, bind)?;
    for(let fun ..& mod.1.fun_defs){
        const meta = fun.meta as *fn_meta;
        if(meta.name.id == name.id){
            if(!meta.used && meta.ffi is void){
                const modname = strings::rcut(
                    strings::rcut(mod.1.name, ".lim").0, "/").1;
                meta.mod = fmt::asprintf("{}.{}", modname, meta.name.id)!;
                meta.used = true;
                gen_fun(mod.1, fun)?;
            };
            return fun;
        };
    };
    const help = undef_tip(name.id);
    return error(ctxt,
        "the module %b{} (bound to %g{}%b)%r has no %y{}%r function{}",
        mod.1.name, modname.id, name.id, help);
};

// pushes given function definition to the given context. returns an
// error if the function namespace is already in use.
fn push_fun(ctxt: *context, fn_def: *ast) (void | COMPERR) = {
    const meta = fn_def.meta as *fn_meta;
    const tok =
        if(meta.name.glob){
            yield fn_def.path[0];
        } else {
            yield fn_def.path[1];
        };
    // assert for dups
    check_shadowing(ctxt, tok)?;
    append(ctxt.fun_defs, fn_def)!;
};

// pushes a new string literal to the context and returns its index. if given
// literal already exits, it's index is returned instead.
fn push_str(ctxt: *context, lit: str) size = {
    match(finds(*ctxt.literals, lit)){
    case let id: size => return id;
    case void =>
        append(ctxt.literals, lit)!;
        return len(ctxt.literals) - 1;
    };
};

fn get_mod(ctxt: *context, bind: token) ((token, *context) | COMPERR) = {
    move_ptr(ctxt, bind);
    const modname = bind.val as ident;
    for(let m ..& ctxt.modules){
        if((m.0.val as ident).id  == modname.id){
            return m;
        };
    };
    return error(ctxt, "module bind %b{0}%r not found. try adding "
        "%p\"%c{0} %d= %puse %y\"{0}.lim\"%d;%p\"", modname.id);
};

// pushes a new module bound to `bind` to the current context. returns an error
// if given bind is already in use.
fn push_module(ctxt: *context, bind: token, module: *context) (void | COMPERR) = {
    // assert for dups
    check_shadowing(ctxt, bind)?;
    append(ctxt.modules, (bind, module))!;
};

// cleans up all allocated data from an abstract object file.
fn free_module(ctxt: *context) void = {
    io::close(ctxt.buffer)!;
    free(ctxt.buffer);
    free(ctxt.tokens);

    free_nodes(ctxt.head);
    for(let mod .. ctxt.modules) free_module(mod.1);

    for(let var ..& ctxt.glob.vars) free(var);
    free(ctxt.glob.vars);

    free(ctxt.modules);
    free(ctxt.fun_defs);
    free(ctxt.name);
    free(ctxt.src);
    free(ctxt);
};

fn new_array_t(ctxt: *context, base: lichen_t, length: size = 0) lichen_t = {
    for(let tpdef ..& ctxt.typedefs){
        if(tpdef is *ext_array){
            const arr = tpdef as *ext_array;
            if(arr.length is size && arr.length as size == length &&
                comp_type(arr.base, base)) return tpdef;
        };
    };
    return alloc(ext_array {
        length = length,
        base = base,
    })!;
};

fn new_union_t(ctxt: *context, base: []lichen_t, error: bool = false,
    error_val: (void | lichen_t) = void, name: (void | str) = void) lichen_t = {
    for(let t .. base){
        assert(!untyped(t), strtype(t));
    };
    if(error_val is lichen_t) assert(!untyped(error_val as lichen_t));

    for(let tpdef ..& ctxt.typedefs){
        if(tpdef is *aggregated){
            const agg = tpdef as *aggregated;
            if(agg.error == error){
                if(agg.error_val is lichen_t && error_val is lichen_t){
                    if(!comp_type(agg.error_val as lichen_t,
                        error_val as lichen_t)){
                        continue;
                    };
                } else if(agg.error_val is lichen_t && error_val is void ||
                    agg.error_val is void && error_val is lichen_t){
                    continue;
                };
                let subtype = true;
                for(let v .. base){
                    let found = false;
                    for(let vp .. agg.base){
                        if(comp_type(v, vp)){
                            found = true;
                            break;
                        };
                    };
                    if(!found){
                        subtype = false;
                        break;
                    };
                };
                if(subtype) return tpdef;
            };
        };
    };
    const type_name =
        match(name){
        case let some: str =>
            yield strings::dup(some)!;
        case void =>
            yield fmt::asprintf(":type.{}", len(ctxt.typedefs))!;
        };
    const tdef = alloc(aggregated {
        name = type_name,
        error = error,
        kind = keyword::UNION,
        base = base,
        error_val = error_val,
    })!;
    append(ctxt.typedefs, tdef)!;
    return tdef;
};

// qbe_t modes
type mode = enum u8 { REAL, ASSIGN, LOAD };

// returns the qbe equivalent of a given type. changing the mode to
// ASSIGN rounds types smaller than a word to a word, and to LOAD
// adds a sign prefix to the type.
fn qbe_t(tpe: lichen_t, md: mode = mode::REAL) str = {
    if(tpe is primitive){
        assert(tpe as primitive != primitive::ANY);
        switch(tpe as primitive){
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
            primitive::CSTR, primitive::ARR_U8, primitive::ARR_U16,
            primitive::ARR_U32, primitive::ARR_U64, primitive::ARR_I8,
            primitive::ARR_I16, primitive::ARR_I32, primitive::ARR_I64,
            primitive::ARR_F32, primitive::ARR_F64, primitive::ARR_STR,
            primitive::ARR_CSTR, primitive::NUMBER, primitive::RATIO =>
            return "l";
        case primitive::UNIT, primitive::VOID =>
            assert(md != mode::ASSIGN);
            return prm_value[tpe as primitive];
        case =>
            color_error("%Runreachable:%r unknown type %y{}", prm_value[tpe as primitive]);
        };
    } else if(tpe is *aggregated){
        const agg = tpe as *aggregated;
        if(md == mode::ASSIGN) return agg.name;
        return "l";
    } else {
        return "l";
    };
};

fn type_size(tpe: lichen_t) size = {
    if(tpe is primitive){
        assert(!untyped(tpe as primitive));
        switch(tpe as primitive){
        case primitive::UNIT, primitive::VOID => return 0;
        case primitive::U8, primitive::I8 => return 1;
        case primitive::U16, primitive::I16 => return 2;
        case primitive::U32, primitive::I32,
            primitive::F32 => return 4;
        case primitive::U64, primitive::I64,
            primitive::F64, primitive::STR,
            primitive::CSTR, primitive::ARRAY,
            primitive::ARR_U8, primitive::ARR_U16,
            primitive::ARR_U32, primitive::ARR_U64,
            primitive::ARR_I8, primitive::ARR_I16,
            primitive::ARR_I32, primitive::ARR_I64,
            primitive::ARR_F32, primitive::ARR_F64,
            primitive::ARR_STR, primitive::ARR_CSTR => return 8;
        case =>
            assert(false, "unreachable");
            return 0;
        };
    } else if(tpe is *aggregated){
        const agg = tpe as *aggregated;
        let length = 0z;
        if(agg.kind == keyword::RECORD){
            for(let f .. (tpe as *aggregated).base){
                length += type_size(f);
            };
            return length + length % 16;
        } else {
            assert(agg.kind == keyword::UNION, strtype(agg));
            for(let f .. (tpe as *aggregated).base){
                const f_z = type_size(f);
                if(f_z > length) length = f_z;
            };
            length += 8;
        };
        return length + length % 16;
    } else if(tpe is *ext_array){
        const arr = tpe as *ext_array;
        if(arr.length is void){
            return 0;
        } else {
            return arr.length as size;
        };
    } else {
        assert(false, "unreachable");
        return 0;
    };
};

fn type_id(tpe: lichen_t) size = {
    match(tpe){
    case let p: primitive =>
        return p: size;
    case let a: *aggregated =>
        return a: uintptr: size;
    case let e: *ext_array =>
        return e: uintptr: size;
    };
};

// compiles down a given file to its QBE IR equivalent as a memio stream
// returns a COMPERR if any compilation error occurs.
fn compile(filename: str, libpath: str, strlits: *[]str, typedefs: *[](*aggregated | *ext_array),
    main: bool = false) (*context | COMPERR) = {
    filename = strings::dup(filename)!;
    // load source file
    const ctxt = alloc(load(filename, libpath, strlits, typedefs)?)!;
    ctxt.scp = &ctxt.glob;

    // tokenize
    let max = len(ctxt.src);
    for(ctxt.ptr < max){
        ctxt.last = ctxt.ptr;
        // remove comments
        if(ctxt.src[ctxt.ptr] == '/' && ctxt.ptr < max - 1){
            if(strings::fromutf8(ctxt.src[ctxt.ptr .. ctxt.ptr + 2])! == "//"){
                for(ctxt.ptr < max && ctxt.src[ctxt.ptr] != '\n'){
                    inc_ptr(ctxt);
                };
            };
        };
        // keyword, numeric literal or identifier
        if(is_alnum(ctxt.src[ctxt.ptr]) || ctxt.src[ctxt.ptr] == '_'){
            const start = ctxt.ptr;
            for(ctxt.ptr < max && is_alnum(ctxt.src[ctxt.ptr]) ||
                ctxt.src[ctxt.ptr] == '_'){
                inc_ptr(ctxt);
            };
            let matched = false;
            let path = u8tostr(ctxt.src[start..ctxt.ptr]);
            const check = strings::replace(path, "_", "")!;
            defer free(check);

            // check for reserved keywords
            for(let i = 0z; i < len(kwd_value); i += 1){
                if(kwd_value[i] == path){
                    append(ctxt.tokens, new_tk(ctxt, i: keyword))!;
                    matched = true;
                    break;
                };
            };
            if(matched) continue;
            // check for primitive types
            for(let i = 0z; i < len(prm_value); i += 1){
                if(prm_value[i] == path){
                    append(ctxt.tokens, new_tk(ctxt, i: primitive))!;
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
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
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
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
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
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
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
                    append(ctxt.tokens, new_tk(ctxt, n: size))!;
                case strconv::overflow =>
                    return error(ctxt,
                        "64-bit literal overflow");
                case =>
                    for(ctxt.ptr < max && ctxt.src[ctxt.ptr] == '\''){
                        inc_ptr(ctxt);
                    };
                    path = u8tostr(ctxt.src[start..ctxt.ptr]);
                    append(ctxt.tokens, new_tk(ctxt, ident {
                        pub = false,
                        glob = false,
                        id = path,
                        itype = primitive::ANY
                    }))!;
                };
            };
        // symbol, operator or string/character literal
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
                inc_ptr(ctxt, start - ctxt.ptr);
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
                        inc_ptr(ctxt);
                        break;
                    case =>
                        if(escape){
                            return error(dup, "invalid escape sequence \"\\{}\"",
                                ctxt.src[ctxt.ptr]: rune);
                        };
                    };
                    inc_ptr(ctxt);
                };
                if(!closed) return error(dup, "unclosed string found here");
                assert(!escape);
                append(ctxt.tokens, new_tk(dup,
                    u8tostr(ctxt.src[start..(ctxt.ptr - 1)])))!;
                continue;
            // character literal
            } else if(ctxt.src[start] == '\''){
                start += 1;
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
                        end = start + 3;
                    } else {
                        return error(ctxt, "invalid escape sequence");
                    };
                case =>
                    val = ctxt.src[start];
                    end = start + 2;
                };
                if(start >= max){
                    return error(ctxt, "invalid character literal found here");
                };
                inc_ptr(ctxt, end - start + 1);
                append(ctxt.tokens, new_tk(ctxt, val: size))!;
                continue;
            };
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
                append(ctxt.tokens, new_tk(ctxt, operator::HEAP))!;
                start += 1;
                inc_ptr(ctxt);
            case '$' =>
                append(ctxt.tokens, new_tk(ctxt, symbol::FFI))!;
                start += 1;
                inc_ptr(ctxt);
            case '.' =>
                if(start < end - 1 && ctxt.src[start + 1] == '.'){
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
                } else if(start < end - 1 && ctxt.src[start + 1] == '>'){
                    append(ctxt.tokens, new_tk(ctxt, operator::MAP))!;
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
                    } else if(ctxt.src[start + 1] == '<'){
                        append(ctxt.tokens, new_tk(ctxt, operator::SHL))!;
                        start += 2;
                        inc_ptr(ctxt, 2);
                    } else {
                        append(ctxt.tokens, new_tk(ctxt, operator::LST))!;
                        start += 1;
                        inc_ptr(ctxt);
                    };
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::LST))!;
                    start += 1;
                    inc_ptr(ctxt);
                };
            case '>' =>
                if(start < end - 1){
                    if(ctxt.src[start + 1] == '='){
                        append(ctxt.tokens, new_tk(ctxt, operator::GEQ))!;
                        start += 2;
                        inc_ptr(ctxt, 2);
                    } else if(ctxt.src[start + 1] == '>'){
                        append(ctxt.tokens, new_tk(ctxt, operator::SHR))!;
                        start += 2;
                        inc_ptr(ctxt, 2);
                    } else {
                        append(ctxt.tokens, new_tk(ctxt, operator::GTT))!;
                        start += 1;
                        inc_ptr(ctxt);
                    };
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::GTT))!;
                    start += 1;
                    inc_ptr(ctxt);
                };
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
                    append(ctxt.tokens, new_tk(ctxt, operator::FDIV))!;
                    start += 1;
                    inc_ptr(ctxt);
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
                if(start < end - 1 && ctxt.src[start + 1] == '/'){
                    for(start < max && ctxt.src[start] != '\n'){
                        start += 1;
                        inc_ptr(ctxt);
                    };
                } else {
                    append(ctxt.tokens, new_tk(ctxt, operator::IDIV))!;
                    inc_ptr(ctxt);
                    start += 1;
                };
            case '%' =>
                append(ctxt.tokens, new_tk(ctxt, operator::MOD))!;
                start += 1;
                inc_ptr(ctxt);
            case '?' =>
                append(ctxt.tokens, new_tk(ctxt, operator::PROP))!;
                start += 1;
                inc_ptr(ctxt);
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
            inc_ptr(ctxt);
        };
    };
    append(ctxt.tokens, new_tk(ctxt, eof))!;

    max = len(ctxt.tokens);
    if(max == 1){
        return error(ctxt, "the file \"{}\" is empty", ctxt.name);
    };
    let node: nullable *ast = null;
    const head: nullable *ast = null;

    for(let t = 0z; t < max){
        match(ctxt.tokens[t].val){
        case let idt: ident =>
            // const global definition
            const (cdef, end) = eval_c_def(ctxt, t)?;
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
                    const k = next_tk(ctxt, t,
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
                    const (fun, end) = eval_fun_def(ctxt, t, pub)?;
                    push_fun(ctxt, fun)?;
                    t = end;
                    node = push_node(node, fun);
                    if(head is null) head = node;
                case =>
                    move_ptr(ctxt, ctxt.tokens[t]);
                    return error(ctxt, "invalid global expression");
                };
            } else {
                const (cdef, end) = eval_c_def(ctxt, t, pub)?;
                if(cdef.kind == path_t::CONST_DEF){
                    push_var(ctxt, cdef)?;
                    t = end;
                    cdef.path = ctxt.tokens[i..t];
                } else {
                    assert(cdef.kind == path_t::IMPORT);
                    if(pub){
                        move_ptr(ctxt, ctxt.tokens[t]);
                        return error(ctxt, "an %guse statement%r cannot be public");
                    };
                    t = end;
                };
                node = push_node(node, cdef);
                if(head is null) head = node;
            };
        case eof => break;
        case =>
            move_ptr(ctxt, ctxt.tokens[t]);
            return error(ctxt, "unexpected %y{}", strtoken(ctxt.tokens[t].val));
        };
    };

    match(get_fun(ctxt, ident { id = "main", itype = primitive::ANY, ... })?){
    case let fun: *ast =>
        if(!main){
            move_ptr(ctxt, fun.path[0]);
            return error(ctxt, "modules %yshall not implement a main function");
        };
        const meta = fun.meta as *fn_meta;
        if(!meta.name.pub){
            move_ptr(ctxt, fun.path[1]);
            return error(ctxt, "main shall be a public function");
        };
        if(!comp_type(meta.fn_type, primitive::VOID)){
            move_ptr(ctxt, fun.path[1]);
            return error(ctxt, "main shall be of void type");
        };
        const params = (meta.params as *ast).meta as *param_meta;
        if(len(params.names) > 0){
            move_ptr(ctxt, fun.path[1]);
            return error(ctxt, "main shall recieve no arguments");
        };
        gen_file(ctxt, head)?;
    case void =>
        if(main){
            if(max > 2){
                move_ptr(ctxt, ctxt.tokens[max - 2]);
            };
            return error(ctxt, "no main function was defined");
        };
    };
    ctxt.head = head;
    return ctxt;
};

// generates the qbe IR of a given context and ast `head` and writes it to
// `buffer`. returns an error if any compilation error occurs.
fn gen_file(ctxt: *context, head: nullable *ast) (void | COMPERR) = {
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
                fmt::fprint(ctxt.buffer, "export ")!;
            };
            const name = fix_global(meta);
            fmt::fprintf(ctxt.buffer, "data ${} = align 16 {{ ", name)!;

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
                fmt::fprintf(ctxt.buffer, "l {}, l {}", length + 16, length)!;
                for(let slc .. slices){
                    fmt::fprintf(ctxt.buffer, ", b \"{}\"", slc)!;
                };
                fmt::fprintln(ctxt.buffer, " }")!;
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
                fmt::fprintfln(ctxt.buffer, "{} {} }}", qbe_t(tpe), acc)!;
            } else {
                assert(false, "TODO: constant ratios");
            };
        case path_t::FUN_DEF => void;
        case path_t::IMPORT => void;
        case =>
            assert(false, "unreachable");
        };
        node = this.next;
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
fn gen_fun(ctxt: *context, this: *ast) (void | COMPERR) = {
    const meta = this.meta as *fn_meta;
    meta.generated = true;
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
        const pdef = new_node();
        pdef.kind = path_t::DECL;
        pdef.meta = alloc(var_meta {
            pos = param_l.pos[p],
            ffi = void,
            mod = void,
            rets = eval_kind::NONE,
            glob = false,
            name = param_l.names[p],
        })!;
        append(local_scp.vars, pdef)!;
        append(params, pdef)!;
    };
    const safe_scp = ctxt.scp;
    const safe_owner = ctxt.scope_owner;
    ctxt.scp = &local_scp;
    ctxt.scope_owner = meta;

    const old_eval = ctxt.eval_t;
    ctxt.eval_t = eval_kind::RET;
    const (body, _) = eval_scope(ctxt, meta.scope_begin, meta.fn_type)?;
    const body_meta = body.meta as *scope_meta;
    const scp_tpe = body_meta.tpe;
    ctxt.eval_t = old_eval;

    if(!is_subtype(scp_tpe, meta.fn_type)){
        move_ptr(ctxt, body.path[len(body.path) - 1]);
        return error(ctxt, "mismatch between %bfunction return type (%g{}%b)%r "
            "and %bscope evaluation type (%g{}%b)",
            strtype(meta.fn_type), strtype(scp_tpe));
    };
    this.inner = body;

    const name = strings::replace(fix_global(meta), "'", ".q")!;
    defer free(name);

    if(meta.name.pub){
        fmt::fprintf(ctxt.buffer,
            "dbgfile \"{}\"\nsection \".text.{}\" \"ax\"\nexport ",
            ctxt.name, name)!;
    } else {
        fmt::fprintfln(ctxt.buffer,
            "dbgfile \"{}\"\nsection \".text.{}\" \"ax\"",
            ctxt.name, name)!;
    };

    fmt::fprintf(ctxt.buffer, "function ")!;
    if(comp_type(meta.fn_type, primitive::VOID) ||
        comp_type(meta.fn_type, primitive::UNIT)){
        fmt::fprintf(ctxt.buffer, "${}(", name)!;
    } else {
        fmt::fprintf(ctxt.buffer, "{} ${}(", qbe_t(meta.fn_type, mode::ASSIGN),
            name)!;
    };
    for(let p = 0z; p < p_max; p += 1){
        if(param_l.names[p].itype is primitive || param_l.names[p].itype is *ext_array){
            fmt::fprintf(ctxt.buffer, "{} %{}, ",
                qbe_t(param_l.names[p].itype, mode::ASSIGN), param_l.names[p].id)!;
        } else {
            fmt::fprintf(ctxt.buffer, "{} %{}, ",
                qbe_t(param_l.names[p].itype, mode::ASSIGN), param_l.names[p].id)!;
        };
    };
    move_ptr(ctxt, body.path[0]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(ctxt.buffer, "){{\n@start\n\tdbgloc {}, {}\n@body", l, c)!;
    gen_scope(ctxt, body)?;

    if(!body_meta.eval){
        if(comp_type(meta.fn_type, primitive::UNIT) && !ctxt.tailcall){
            fmt::fprintln(ctxt.buffer, "\tret")!;
        } else if(is_subtype(meta.fn_type, primitive::UNIT) && !ctxt.tailcall){
            const dest = strings::dup(".empty.ret")!;
            defer free(dest);
            fmt::fprintfln(ctxt.buffer, "\t%{} =l alloc8 {}",
                dest, type_size(meta.fn_type))!;
            const agg = meta.fn_type as *aggregated;
            assert(agg.error_val is void);
            fmt::fprintfln(ctxt.buffer, "\tstorel {1}, %{0}\n\tret %{0}",
                dest, type_id(agg.base[0]))!;
        } else if(is_subtype(meta.fn_type, primitive::VOID)){
            if(meta.fn_type is *aggregated){
                const agg = meta.fn_type as *aggregated;
                if(agg.error){
                    fmt::fprintln(ctxt.buffer, "\tcall $rt_exit(w 1)\n\thlt")!;
                } else {
                    fmt::fprintln(ctxt.buffer, "\tcall $rt_exit(w 0)\n\thlt")!;
                };
            } else {
                fmt::fprintln(ctxt.buffer, "\tcall $rt_exit(w 0)\n\thlt")!;
            };
        };
    };
    fmt::fprintln(ctxt.buffer, "@fail\n\tcall $rt_exit(w 1)\n\thlt\n}")!; // TODO: report assertion position
    ctxt.scp = safe_scp;
    ctxt.scope_owner = safe_owner;
};

// generates the qbe IR for a given scope
fn gen_scope(ctxt: *context, node: nullable *ast, stt_dest: (void | str) = void)
    (void | COMPERR) = {
    const node = node as *ast;
    const scp_meta = node.meta as *scope_meta;
    const list = scp_meta.members;
    const scp = scp_meta.scp as *scope;

    const old_fail = ctxt.fail;
    const safe_scp = ctxt.scp;
    ctxt.scp = scp;
    for(let this ..& list){
        switch(this.kind){
        case path_t::DECL, path_t::CONST_DEF =>
            const meta = this.meta as *var_meta;
            move_ptr(ctxt, this.path[0]);
            const (l, c) = get_pos(ctxt);
            fmt::fprintfln(ctxt.buffer, "\tdbgloc {}, {}", l, c)!;

            const name = fix_global(meta);
            defer free(name);

            if(meta.rets == eval_kind::NONE){
                gen_exp(ctxt, this.inner as *ast, name, meta.name.itype)?;
            } else {
                gen_exp(ctxt, this.inner as *ast, name, scp_meta.tpe)?;
            };
        case path_t::EXPR =>
            const meta = this.meta as *expr_meta;
            if(comp_type(meta.tpe, primitive::VOID) ||
                comp_type(meta.tpe, primitive::UNIT)){
                move_ptr(ctxt, this.path[0]);
                const (l, c) = get_pos(ctxt);
                fmt::fprintfln(ctxt.buffer, "\tdbgloc {}, {}", l, c)!;
                for(let m ..& meta.members){
                    if(m is operator) continue;
                    const member = m as *ast;
                    match(member.meta){
                    case let memb: *member_meta =>
                        if(memb.val is *ast) match((memb.val as *ast).meta){
                        // tailcall elimination
                        case let call: *funcall_meta =>
                            if(call.fun.meta as *fn_meta == ctxt.scope_owner as *fn_meta){
                                ctxt.tailcall = true;
                                tailcall(ctxt, call)?;
                                continue;
                            };
                        case => void;
                        };
                        free(gen_member(ctxt, member, memb.tpe)?);
                    case let funcall: *funcall_meta =>
                        gen_funcall(ctxt, member)?;
                    case =>
                        assert(false, "TODO");
                    };
                };
                continue;
            };
            const dest =
                match(stt_dest){
                case let d: str => yield strings::dup(d)!;
                case void =>
                    yield fmt::asprintf("exp.{}", this.path[0].pos)!;
                };
            defer free(dest);

            move_ptr(ctxt, this.path[0]);
            const (l, c) = get_pos(ctxt);
            fmt::fprintfln(ctxt.buffer, "\tdbgloc {}, {}", l, c)!;
            if(meta.rets == eval_kind::NONE){
                gen_exp(ctxt, this, dest, meta.tpe)?;
            } else {
                gen_exp(ctxt, this, dest, scp_meta.tpe)?;
            };
        case path_t::FUN_CALL =>
            move_ptr(ctxt, this.path[0]);
            const (l, c) = get_pos(ctxt);
            fmt::fprintfln(ctxt.buffer, "\tdbgloc {}, {}", l, c)!;
            gen_funcall(ctxt, this)?;
        case path_t::STATEMENT =>
            switch(this.path[0].val as keyword){
            case keyword::IF =>
                gen_if_else(ctxt, this, stt_dest)?;
            case keyword::MATCH =>
                assert(false, "TODO");
            case keyword::TEST =>
                move_ptr(ctxt, this.path[0]);
                const (l, c) = get_pos(ctxt);
                fmt::fprintfln(ctxt.buffer, "\tdbgloc {}, {}", l, c)!;

                const meta = this.meta as *test_meta;
                const name = fmt::asprintf("test.{}", this.path[0].pos)!;
                defer free(name);
                gen_exp(ctxt, meta.cond, name, (meta.cond.meta as *expr_meta).tpe)?;

                fmt::fprintfln(ctxt.buffer, "\tjnz %{0}, @{0}.ok, @{0}.fail\n@{0}.fail\n"
                    "\t%.stderr =l loadsw $rt_stderr\n\tcall $rt_puts(w %.stderr, l $lit.{1})\n"
                    "\tcall $rt_exit(w 1)\n@{0}.ok",
                    name, push_str(ctxt, memio::string(meta.line_msg)!))!;
            case =>
                assert(false, "unreachable");
            };
        case =>
            assert(false, fmt::asprintf("TODO: {}", this.kind: int)!);
        };
    };
    ctxt.scp = safe_scp;
    ctxt.fail = old_fail;
};

fn gen_if_else(ctxt: *context, this: *ast, stt_dest: (void | str) = void)
    (void | COMPERR) = {
    const meta = this.meta as *if_else_meta;
    const cond_max = len(meta.conds);
    const body_max = len(meta.bodies);
    const c_dest = fmt::asprintf("cond.{}", this.path[0].pos)!;
    defer free(c_dest);

    for(let b = 0z; b < body_max; b += 1){
        const body = meta.bodies[b];
        const b_meta = meta.bodies[b].meta as *scope_meta;
        if(b < cond_max){
            const cond = meta.conds[b];

            const c_meta = cond.meta as *expr_meta;
            gen_exp(ctxt, cond, c_dest, c_meta.tpe)?;

            fmt::fprintfln(ctxt.buffer, "\tjnz %{0}, @t.{0}.{1}, @f.{0}.{1}\n@t.{0}.{1}", c_dest, b)!;
            gen_scope(ctxt, body, stt_dest)?;

            if(!ctxt.tailcall && b_meta.rets != eval_kind::RET){
                fmt::fprintfln(ctxt.buffer, "\tjmp @end.{}", c_dest)!;
            };
            fmt::fprintfln(ctxt.buffer, "@f.{}.{}", c_dest, b)!;
            if(meta.tpe is *aggregated && b == body_max - 1 && body_max == cond_max){
                const agg = meta.tpe as *aggregated;
                if(agg.error_val is void && agg.error){
                    assert(stt_dest is str);
                    fmt::fprintfln(ctxt.buffer, "\t%{} =l alloc8 {}",
                    stt_dest as str, type_size(agg))!;
                    fmt::fprintfln(ctxt.buffer, "\tstorel {1}, %{0}\n\tret %{0}",
                        stt_dest as str, type_id(agg.base[0]))!;
                };
            };
        } else {
            gen_scope(ctxt, body, stt_dest)?;
            if(!ctxt.tailcall && b_meta.rets != eval_kind::RET){
                fmt::fprintfln(ctxt.buffer, "\tjmp @end.{}", c_dest)!;
            };
        };
    };
    fmt::fprintfln(ctxt.buffer, "@end.{}", c_dest)!;
    ctxt.tailcall = false;
    if(meta.rets == eval_kind::RET) fmt::fprintln(ctxt.buffer, "\thlt")!;
};

fn gen_for_iterator(ctxt: *context, this: *ast, dest: str) (void | COMPERR) = {
    const f_meta = this.meta as *for_meta;
    const iter_item = strings::replace(solve_iter(f_meta.item).id, "'", ".q")!;
    defer free(iter_item);

    const elem_t = qbe_t(f_meta.element_tpe);
    const elem_l = qbe_t(f_meta.element_tpe, mode::LOAD);
    const elem_z = type_size(f_meta.element_tpe);

    const exp_t = qbe_t(f_meta.element_tpe, mode::ASSIGN);

    move_ptr(ctxt, this.path[0]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(ctxt.buffer, "\tdbgloc {}, {}", l, c)!;

    fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l copy %{0}\n"
        "\t%{0}.ptr =l add %{0}.ptr, 8\n"
        "\t%{0}.len =l loadl %{0}.ptr\n"
        "\t%iter.last.c =l sub %{0}.len, 1\n"
        "\t%{0}.ptr =l add %{0}.ptr, 8", iter_item)!;
    fmt::fprintfln(ctxt.buffer, "\t%iter.acc =l copy 0")!;

    const array_out = !is_subtype(f_meta.tpe, primitive::UNIT) &&
        !is_subtype(f_meta.tpe, primitive::VOID) && len(f_meta.out_acc) == 0;

    if(array_out){
        stack_allocate_array(ctxt, dest, f_meta.out_size * elem_z + 16, f_meta.out_size);
    } else if(len(f_meta.out_acc) > 0){
        const wrap = strings::replace((f_meta.out_acc[0].val as ident).id, "'", ".q")!;
        defer free(wrap);

        gen_exp(ctxt, f_meta.acc[0].inner as *ast, wrap, f_meta.tpe)?;
    };
    fmt::fprintfln(ctxt.buffer, "@iter.{}.rep", this.path[0].pos)!;
    fmt::fprintfln(ctxt.buffer,
        "\t%iter.over =l cultl %iter.acc, %{0}.len\n"
        "\tjnz %iter.over, @iter.{1}.body, @iter.{1}.end",
        iter_item, this.path[0].pos)!;
    fmt::fprintfln(ctxt.buffer, "@iter.{}.body", this.path[0].pos)!;

    switch(len(f_meta.pairs)){
    case 3 =>
        const pair_0 = strings::replace((f_meta.pairs[0].val as ident).id, "'", ".q")!;
        defer free(pair_0);
        const pair_1 = strings::replace((f_meta.pairs[1].val as ident).id, "'", ".q")!;
        defer free(pair_1);
        const pair_2 = strings::replace((f_meta.pairs[2].val as ident).id, "'", ".q")!;
        defer free(pair_2);

        fmt::fprintfln(ctxt.buffer, "\t%iter.first =l ceql %iter.acc, 0")!;
        fmt::fprintfln(ctxt.buffer,
            "\t%iter.last =l ceql %iter.acc, %iter.last.c")!;

        fmt::fprintfln(ctxt.buffer,
            "\tjnz %iter.first, @iter.{0}.first, @iter.{0}.normal",
            this.path[0].pos)!;

        if(is_subtype(f_meta.element_tpe, primitive::STR) ||
            is_subtype(f_meta.element_tpe, primitive::CSTR)){ // TODO: make is_ptr_tpe
            fmt::fprintfln(ctxt.buffer,
            "@iter.{2}.first\n\t%{0} ={1} copy $rt_zero", pair_0, exp_t,
                this.path[0].pos)!;
        } else {
            fmt::fprintfln(ctxt.buffer,
            "@iter.{2}.first\n\t%{0} ={1} copy 0", pair_0, exp_t, this.path[0].pos)!;
        };
        fmt::fprintfln(ctxt.buffer,
            "\tjmp @iter.{3}.over.0\n@iter.{3}.normal\n"
            "\t%{0} ={1} copy %{2}\n@iter.{3}.over.0",
            pair_0, exp_t, pair_1, this.path[0].pos)!;

        fmt::fprintfln(ctxt.buffer, "\t%{} ={} load{} %{}.ptr",
            pair_1, exp_t, elem_l, iter_item)!;
        fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l add %{0}.ptr, {1}", iter_item, elem_z)!;

        fmt::fprintfln(ctxt.buffer,
            "\tjnz %iter.last, @iter.{0}.last, @iter.{0}.notlast",
            this.path[0].pos)!;

        if(is_subtype(f_meta.element_tpe, primitive::STR) ||
            is_subtype(f_meta.element_tpe, primitive::CSTR)){ // TODO: make is_ptr_tpe
            fmt::fprintfln(ctxt.buffer,
                "@iter.{2}.last\n\t%{0} ={1} copy $rt_zero",
                pair_2, exp_t, this.path[0].pos)!;
        } else {
            fmt::fprintfln(ctxt.buffer,
                "@iter.{2}.last\n\t%{0} ={1} copy 0",
                pair_2, exp_t, this.path[0].pos)!;
        };
        fmt::fprintfln(ctxt.buffer,
            "\tjmp @iter.{4}.over.1\n"
            "@iter.{4}.notlast\n"
            "\t%{0} ={1} load{2} %{3}.ptr\n@iter.{4}.over.1",
            pair_2, exp_t, elem_l, iter_item, this.path[0].pos)!;
    case 1 =>
        const pair = strings::replace((f_meta.pairs[0].val as ident).id, "'", ".q")!;
        defer free(pair);

        fmt::fprintfln(ctxt.buffer, "\t%{} ={} load{} %{}.ptr", pair, exp_t, elem_l, iter_item)!;
        fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l add %{0}.ptr, {1}", iter_item, elem_z)!;
    case 0 =>
        assert(false, "TODO");
    case =>
        assert(false);
    };

    if(array_out){
        const asg = fmt::asprintf("{}.iter.val", iter_item)!;
        defer free(asg);
        gen_scope(ctxt, f_meta.body, asg)?;
        fmt::fprintfln(ctxt.buffer, "\tstore{} %{}, %{}.ptr",
            elem_t, asg, dest)!;
        fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l add %{0}.ptr, {1}", dest, elem_z)!;
    } else if(len(f_meta.out_acc) > 0){
        const wrap = strings::replace((f_meta.out_acc[0].val as ident).id, "'", ".q")!;
        defer free(wrap);
        gen_scope(ctxt, f_meta.body, wrap)?;
    } else {
        gen_scope(ctxt, f_meta.body)?;
    };

    fmt::fprintfln(ctxt.buffer,
        "\t%iter.acc =l add %iter.acc, 1\n\tjmp @iter.{0}.rep\n@iter.{0}.end",
        this.path[0].pos)!;

    if(len(f_meta.out_acc) > 0){
        const wrap = strings::replace((f_meta.out_acc[0].val as ident).id, "'", ".q")!;
        defer free(wrap);
        fmt::fprintfln(ctxt.buffer, "\t%{} ={} copy %{}", dest, exp_t, wrap)!;
    };
};

fn solve_iter(exp: *expr_meta) ident = {
    assert(len(exp.members) == 1);
    assert(exp.members[0] is *ast);
    const m_meta = (exp.members[0] as *ast).meta as *member_meta;
    match((m_meta.val as *ast).meta){
    case let e_meta: *expr_meta =>
        return solve_iter(e_meta);
    case let var: *var_meta =>
        return var.name;
    case =>
        fmt::fatalf("solve_iter: unreachable ({})",
            (exp.members[0] as *ast).kind: u8);
    };
};

// generates the qbe IR for a given expression
fn gen_exp(ctxt: *context, exp: *ast, dest: str, exp_type: lichen_t)
    (void | COMPERR) = {
    match(exp.meta){
    case let var: *var_meta =>
        const temp = memio::dynamic();
        defer io::close(&temp)!;
        const old_fail = ctxt.fail;
        gen_move(ctxt, &temp, dest, exp, exp_type)?;

        if(var.rets == eval_kind::RET){
            if(!is_subtype(exp_type, primitive::UNIT)
                && !is_subtype(exp_type, primitive::VOID)){
                fmt::fprintfln(ctxt.buffer, "\tret %{}", dest)!;
            } else {
                fmt::fprintfln(ctxt.buffer, "\tret")!;
            };
        };
        ctxt.fail = old_fail;
    case let exp_meta: *expr_meta =>
        const members = exp_meta.members;
        const old_fail = ctxt.fail;
        gen_exp_steps(ctxt, members, dest, exp_type)?;
        
        const skip_ret =
            if(len(members) == 1 && members[0] is *ast){
                const memb = members[0] as *ast;
                const meta = memb.meta as *member_meta;
                yield
                if(meta.val is *ast){
                    yield
                    match((meta.val as *ast).meta){
                    case *if_else_meta =>
                        yield true;
                    case *for_meta =>
                        yield true;
                    case => yield false;
                    };
                } else {
                    yield false;
                };
            } else {
                yield false;
            };
        if(exp_meta.rets == eval_kind::RET && !skip_ret){
            if(!comp_type(exp_type, primitive::UNIT)
                && !comp_type(exp_type, primitive::VOID)){
                fmt::fprintfln(ctxt.buffer, "\tret %{}", dest)!;
            } else {
                fmt::fprintfln(ctxt.buffer, "\tret")!;
            };
        };
        ctxt.fail = old_fail;
    case let array: *array_meta =>
        gen_stack_array(ctxt, array, dest)?;
    case =>
        assert(false, "unreachable");
    };
};

fn gen_exp_steps(ctxt: *context, members: [](*ast | operator), dest: str,
    exp_type: lichen_t, stop_logic: bool = false) (size | COMPERR) = {
    const exp_t = qbe_t(exp_type, mode::ASSIGN);
    const temp = memio::dynamic();
    defer io::close(&temp)!;

    const max = len(members);
    const begin =
        match(members[0]){
        case let oper: operator =>
            if(oper == operator::MIN){
                gen_move(ctxt, &temp, dest, members[1] as *ast, exp_type)?;
                fmt::fprintfln(ctxt.buffer, "{0}\t{1} ={2} neg {1}",
                    memio::string(&temp)!, dest, exp_t)!;
            } else {
                gen_move(ctxt, &temp, dest, members[1] as *ast, exp_type)?;
            };
            yield 2z;
        case let mem: *ast =>
            gen_move(ctxt, &temp, dest, members[0] as *ast, exp_type)?;
            yield 1z;
        };
    for(let m = begin; m < max; m += 2){
        const op = members[m] as operator;
        switch(op){
        case operator::PLS, operator::MIN, operator::MUL, operator::IDIV,
            operator::SHL, operator::SHR, operator::BAND, operator::BOR =>
            const memb = gen_member(ctxt, members[m + 1] as *ast, exp_type)?;
            defer free(memb);
            const inst =
                switch(op){
                case operator::PLS => yield "add";
                case operator::MIN => yield "sub";
                case operator::MUL => yield "mul";
                case operator::IDIV =>
                    yield if(is_subtype(exp_type, primitive::U64)){
                        yield "udiv";
                    } else {
                        yield "div";
                    };
                case operator::SHL => yield "shl";
                case operator::SHR =>
                    yield if(is_subtype(exp_type, primitive::U64)){
                        yield "shr";
                    } else {
                        yield "sar";
                    };
                case operator::BAND => yield "and";
                case operator::BOR => yield "or";
                case =>
                    assert(false, "TODO");
                    yield "";
                };
            const memb_meta = (members[m - 1] as *ast).meta as *member_meta;
            if(is_subtype(memb_meta.tpe, primitive::STR)){
                if(op == operator::PLS){
                    assert(false, "TODO: runtime string concatenation");
                } else if(op == operator::MUL){
                    assert(false, "TODO: string repeat");
                } else {
                    assert(false, "unreachable");
                };
            } else {
                fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} {2} %{0}, {3}",
                    dest, exp_t, inst, memb)!;
            };
        case operator::EQL, operator::NEQ, operator::LEQ, operator::GEQ,
            operator::LST, operator::GTT =>
            const inst =
                switch(op){
                case operator::EQL => yield "eq";
                case operator::NEQ => yield "ne";
                case operator::LEQ =>
                    yield if(is_subtype(exp_type, primitive::U64)){
                        yield "ule";
                    } else {
                        yield "sle";
                    };
                case operator::GEQ =>
                    yield if(is_subtype(exp_type, primitive::U64)){
                        yield "uge";
                    } else {
                        yield "sge";
                    };
                case operator::LST =>
                    yield if(is_subtype(exp_type, primitive::U64)){
                        yield "ult";
                    } else {
                        yield "slt";
                    };
                case operator::GTT =>
                    yield if(is_subtype(exp_type, primitive::U64)){
                        yield "ugt";
                    } else {
                        yield "sgt";
                    };
                case =>
                    assert(false, "TODO");
                    yield "";
                };
            const pos = members[m - 1] as *ast;
            const memb_meta = pos.meta as *member_meta;
            const right = fmt::asprintf("rght.{}", pos.path[0].pos)!;
            defer free(right);

            m += gen_exp_steps(ctxt, members[m .. max], right,
                exp_type, true)?;

            if(is_subtype(memb_meta.tpe, primitive::STR)){
                if(op == operator::EQL){
                    fmt::fprintfln(ctxt.buffer, "\t%{0} =l call $rt_strcmp(l %{0}, l %{1})",
                        dest, right)!;
                } else {
                    fmt::fprintfln(ctxt.buffer, "\t%{0} =l call $rt_strcmp(l %{0}, l %{1})",
                        dest, right)!;
                    fmt::fprintfln(ctxt.buffer, "\t%{0} =l ceql l%{0}, 0", dest)!;
                };
            } else {
                fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} c{2}{1} %{0}, %{3}",
                    dest, exp_t, inst, right)!;
            };
        case operator::LAND =>
            if(stop_logic) return m;
            const pos = members[m - 1] as *ast;
            const label = fmt::asprintf("lazy.{}", pos.path[0].pos)!;
            defer free(label);

            fmt::fprintfln(ctxt.buffer, "\tjnz %{0}, @{1}.m, @{1}.f\n@{1}.m",
                dest, label)!;

            const right = fmt::asprintf("rght.{}", pos.path[0].pos)!;
            defer free(right);
            m += gen_exp_steps(ctxt, members[m .. max], right,
                exp_type, true)?;

            fmt::fprintfln(ctxt.buffer, "\tjnz %{0}, @{1}.t, @{1}.f", right, label)!;
            fmt::fprintfln(ctxt.buffer, "@{0}.t\n\tjmp @{0}.asg\n@{0}.f\n\tjmp @{0}.asg",
                label)!;
            fmt::fprintfln(ctxt.buffer, "@{0}.asg\n\t%{1} ={2} phi @{0}.f 0, @{0}.t 1",
                label, dest, exp_t)!;

        case operator::LOR =>
            if(stop_logic) return m;
            const pos = members[m - 1] as *ast;
            const label = fmt::asprintf("lazy.{}", pos.path[0].pos)!;
            defer free(label);

            fmt::fprintfln(ctxt.buffer, "\tjnz %{0}, @{1}.t, @{1}.m\n@{1}.m",
                dest, label)!;

            const right = fmt::asprintf("rght.{}", pos.path[0].pos)!;
            defer free(right);
            m += gen_exp_steps(ctxt, members[m .. max], right,
                exp_type, true)?;

            assert(m >= max || comp_tk(members[m] as operator, operator::LAND) ||
                comp_tk(members[m] as operator, operator::LOR));

            fmt::fprintfln(ctxt.buffer, "\tjnz %{0}, @{1}.t, @{1}.f", right, label)!;
            fmt::fprintfln(ctxt.buffer, "@{0}.t\n\tjmp @{0}.asg\n@{0}.f\n\tjmp @{0}.asg",
                label)!;
            fmt::fprintfln(ctxt.buffer, "@{0}.asg\n\t%{1} ={2} phi @{0}.f 0, @{0}.t 1",
                label, dest, exp_t)!;
            if(m < max && members[m] is operator){
                if(!comp_tk(members[m] as operator, operator::LAND) &&
                    !comp_tk(members[m] as operator, operator::LOR)) break;
            };
        case =>
            assert(false, strtoken(op));
        };
    };
    return max;
};

fn tailcall(ctxt: *context, call: *funcall_meta) (void | COMPERR) = {
    const fun = call.fun.meta as *fn_meta;
    const p_meta = (fun.params as *ast).meta as *param_meta;
    const max = len(p_meta.names);
    assert(len(call.args) == max);

    const temp = memio::dynamic();
    defer io::close(&temp)!;
    for(let a = 0z; a < max; a += 1){
        const arg = call.args[a];
        const arg_t = qbe_t(p_meta.names[a].itype, mode::ASSIGN);
        match(arg.meta){
        case let expr: *expr_meta =>
            const wrap = fmt::asprintf("arg.{}.{}", arg_t, arg.path[0].pos)!;
            defer free(wrap);

            gen_exp(ctxt, arg, wrap, p_meta.names[a].itype)?;
            fmt::fprintfln(&temp, "\t%{} ={} copy %{}",
                p_meta.names[a].id, arg_t, wrap)!;
        case let vdef: *var_meta =>
            fmt::fprintfln(&temp, "\t%{} ={} copy %{}",
                p_meta.names[a].id, arg_t, fix_global(vdef))!;
        };
    };
    fmt::fprintfln(ctxt.buffer, "{}\tjmp @body", memio::string(&temp)!)!;
};

// generates the qbeIR for a given funcall. if `dest` is set, the return value
// is assigned to it. `dest` shall not have qbe temporaries prefix.
fn gen_funcall(ctxt: *context, this: *ast, dest: (void | str) = void)
    (void | COMPERR) = {
    const meta = this.meta as *funcall_meta;
    const temp = memio::dynamic();
    defer io::close(&temp)!;

    const tpe = meta.tpe;
    const fun = meta.fun;
    const f_meta = fun.meta as *fn_meta;
    const p_meta = (f_meta.params as *ast).meta as *param_meta;
    const name = strings::replace(fix_global(f_meta), "'", ".q")!;
    defer free(name);
    const res =
        match(dest){
        case let wrap: str =>
            yield
            if(!comp_type(f_meta.fn_type, primitive::UNIT) &&
                !comp_type(f_meta.fn_type, primitive::UNIT)){
                fmt::fprintf(&temp, "\t%{} ={} call ${}(",
                    wrap, qbe_t(f_meta.fn_type, mode::ASSIGN), name)!;
                yield wrap;
            } else {
                fmt::fprintf(&temp, "\tcall ${}(", name)!;
                yield "";
            };
        case void =>
            yield match(meta.dest){
            case let wrap: str =>
                fmt::fprintf(&temp, "\t%{} ={} call ${}(",
                    wrap, qbe_t(f_meta.fn_type, mode::ASSIGN), name)!;
                yield wrap;
            case void =>
                yield
                if(f_meta.fn_type is *aggregated){
                    const wrap = fmt::asprintf(".res")!;
                    fmt::fprintf(&temp, "\t%{} ={} call ${}(",
                        wrap, qbe_t(f_meta.fn_type, mode::ASSIGN), name)!;
                    yield wrap;
                } else {
                    fmt::fprintf(&temp, "\tcall ${}(", name)!;
                    yield "";
                };
            };
        };
    const max = len(p_meta.names);
    assert(len(meta.args) == max);
    for(let a = 0z; a < max; a += 1){
        const arg = meta.args[a];
        const arg_t = qbe_t(p_meta.names[a].itype, mode::ASSIGN);
        match(arg.meta){
        case let expr: *expr_meta =>
            const wrap = fmt::asprintf("arg.{}.{}", arg_t, arg.path[0].pos)!;
            defer free(wrap);

            gen_exp(ctxt, arg, wrap, p_meta.names[a].itype)?;
            fmt::fprintf(&temp, "{} %{}, ", arg_t, wrap)!;
        case let vdef: *var_meta =>
            fmt::fprintf(&temp, "{} %{}, ", arg_t, fix_global(vdef))!;
        };
    };
    fmt::fprintfln(ctxt.buffer, "{})", memio::string(&temp)!)!;
    if(meta.prop is operator){
        assert(res != "");
        const prop = meta.prop as operator;
        ctxt.fail = true;
        if(prop == operator::BANG){ // TODO: report assertion location
            fmt::fprintfln(ctxt.buffer,
                "\t%.on_fail =l loadl %{0}\n"
                "\t%.on_fail =l ceql %.on_fail, -1\n"
                "\tjnz %.on_fail, @fail, @keep.{1}\n@keep.{1}",
                res, this.path[0].pos)!;
        } else {
            const host = ctxt.scope_owner as *fn_meta;
            if(is_subtype(host.fn_type, primitive::UNIT) ||
                is_subtype(host.fn_type, primitive::VOID)){
                fmt::fprintfln(ctxt.buffer,
                    "\t%.on_fail =l loadl %{0}\n"
                    "\t%.on_fail =l ceql %.on_fail, -1\n"
                    "\tjnz %.on_fail, @bubble.{1}, @keep.{1}\n"
                    "@bubble.{1}\n\tret %{0}\n@keep.{1}",
                    res, this.path[0].pos)!;
            } else {
                    fmt::fprintfln(ctxt.buffer,
                    "\t%.on_fail =l loadl %{0}\n"
                    "\t%.on_fail =l ceql %.on_fail, -1\n"
                    "\tjnz %.on_fail, @bubble.{1}, @keep.{1}\n"
                    "@bubble.{1}\n\tret %{0}\n@keep.{1}",
                    res, this.path[0].pos)!;
            };
        };
    };
};

// generates the coresponding move instruction for a given member and fixes any
// casting for the given member type and expected `tpe` type.
fn gen_move(ctxt: *context, header: *memio::stream, dest: str,
    member: *ast, tpe: lichen_t) (void | COMPERR) = {
    assert(!strings::hasprefix(dest, "%"), dest);
    const move_t = qbe_t(tpe, mode::ASSIGN);
    const m_meta = member.meta as *member_meta;
    match(m_meta.val){
    case let node: *ast =>
        match(node.meta){
        case let var: *var_meta =>
            let name = fix_global(var);
            defer free(name);
            if(var.name.itype is primitive && tpe is primitive){
                if(is_subtype(var.name.itype, primitive::NUMBER)){
                    if(var.name.glob){
                        if(is_subtype(var.name.itype, primitive::NUMBER)){
                            fmt::fprintfln(header, "\t%{0} ={1} load{2} ${0}",
                                name, qbe_t(var.name.itype, mode::ASSIGN),
                                qbe_t(var.name.itype, mode::LOAD))!;
                        } else {
                            fmt::fprintfln(header, "\t%{0} =l copy ${0}", name)!;
                        };
                    };
                    if(comp_type(var.name.itype, tpe) || is_subtype(tpe, var.name.itype) ||
                        type_size(tpe) <= type_size(var.name.itype)){
                        fmt::fprintfln(ctxt.buffer, "{}\t%{} ={} copy %{}",
                            memio::string(header)!, dest, move_t, name)!;
                    } else {
                        fmt::fprintfln(ctxt.buffer, "{}\t%{} ={} ext{} %{}",
                            memio::string(header)!, dest, move_t,
                            qbe_t(var.name.itype, mode::LOAD), name)!;
                    };
                } else if(comp_type(var.name.itype, primitive::STR) &&
                    comp_type(tpe, primitive::CSTR)){
                    if(var.glob){
                        fmt::fprintfln(ctxt.buffer, "{}\t%{} ={} add ${}, 16",
                            memio::string(header)!, dest, move_t, name)!;
                    } else {
                        fmt::fprintfln(ctxt.buffer, "{}\t%{} ={} add %{}, 16",
                            memio::string(header)!, dest, move_t, name)!;
                    };
                } else if(comp_type(var.name.itype, primitive::STR) ||
                    comp_type(var.name.itype, primitive::CSTR)){
                    if(var.glob){
                        fmt::fprintfln(ctxt.buffer, "{}\t%{} ={} copy ${}",
                            memio::string(header)!, dest, move_t, name)!;
                    } else {
                        fmt::fprintfln(ctxt.buffer, "{}\t%{} ={} copy %{}",
                            memio::string(header)!, dest, move_t, name)!;
                    };
                } else if(is_subtype(var.name.itype, primitive::RATIO)){
                    assert(false, "TODO: ratios");
                } else if(is_subtype(var.name.itype, primitive::ARRAY)){
                    fmt::fprintfln(ctxt.buffer, "{}\t%{} =l copy %{}",
                        memio::string(header)!, dest, name)!;
                } else {
                    //assert(false, "unexpected type");
                    fmt::fatalf("unexpected type {}", strtype(var.name.itype));
                };
            } else if(var.name.itype is primitive && tpe is *aggregated){
                const dest_t = tpe as *aggregated;
                if(dest_t.kind == keyword::UNION){
                    fmt::fprintfln(ctxt.buffer, "\t%{} =l alloc8 {}",
                        dest, type_size(dest_t))!;
                    fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l copy %{0}", dest)!;
                    fmt::fprintfln(ctxt.buffer, "\tstorel {}, %{}.ptr",
                        type_id(dest_t.base[0]), dest)!;
                    fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l add %{0}.ptr, 8", dest)!;
                    fmt::fprintfln(ctxt.buffer, "\tstore{} %{}, %{}.ptr",
                        qbe_t(var.name.itype, mode::ASSIGN), name, dest)!;
                };
            } else if(var.name.itype is *aggregated && tpe is *aggregated){
                assert(false, "todo");
            } else {
                assert(false, "todo");
            };
        case let array: *array_meta =>
            gen_stack_array(ctxt, array, dest)?;
        case let index: *index_meta =>
            gen_array_index(ctxt, index, dest)?;
        case *if_else_meta =>
            gen_if_else(ctxt, node, dest)?;
        case *for_meta =>
            gen_for_iterator(ctxt, node, dest)?;
        case let exp: *expr_meta =>
            gen_exp(ctxt, node, dest, exp.tpe)?;
        case let funcall: *funcall_meta =>
            const f_meta = funcall.fun.meta as *fn_meta;
            if(comp_type(funcall.tpe, f_meta.fn_type)){
                gen_funcall(ctxt, node, dest)?;
            } else {
                const temp = fmt::asprintf(".agg")!;
                defer free(temp);
                gen_funcall(ctxt, node, temp)?;
                if(f_meta.fn_type is *aggregated){
                    const dest_t = f_meta.fn_type as *aggregated;
                    if(dest_t.kind == keyword::UNION){
                        fmt::fprintfln(ctxt.buffer, "\t%{0}.tag =l loadl %{0}", temp)!;
                        fmt::fprintfln(ctxt.buffer, "\t%{0}.tag =l ceql %{0}.tag, {1}",
                            temp, type_id(tpe))!;
                        fmt::fprintfln(ctxt.buffer, "\tjnz %{0}.tag, @tag.match.{1}, @fail\n@tag.match.{1}",
                            temp, member.path[0].pos)!;
                        fmt::fprintfln(ctxt.buffer, "\t%{0} =l add %{0}, 8", temp)!;
                        fmt::fprintfln(ctxt.buffer, "\t%{} ={} load{} %{}", dest,
                            qbe_t(tpe, mode::ASSIGN), qbe_t(tpe, mode::LOAD), temp)!;
                    } else {
                        assert(false, "todo");
                    };
                } else {
                    assert(false, "todo");
                };
            };
        };
    case let tok: tkval =>
        match(tok){
        case let kwd: keyword =>
            switch(kwd){
            case keyword::TODO =>
                if(is_subtype(tpe, primitive::STR)){
                    fmt::fprintfln(ctxt.buffer, "\t%{} =l copy $rt_zero", dest)!;
                } else {
                    fmt::fprintfln(ctxt.buffer, "\t%{} =l copy 0", dest)!;
                };
            case keyword::FAIL =>
                fmt::fprintfln(ctxt.buffer,
                    "\t%{} =l alloc8 {}", dest, type_size(tpe))!;
                assert(tpe is *aggregated, strtype(tpe));
                const agg = tpe as *aggregated;
                assert(agg.error_val is void);
                fmt::fprintfln(ctxt.buffer, "\tstorel -1, %{}", dest)!;
            case =>
                assert(false, "unreachable");
            };
        case let num: size =>
            fmt::fprintfln(ctxt.buffer, "\t%{} ={} copy {}", dest, move_t, num)!;
        case let txt: str =>
            if(comp_type(tpe, primitive::CSTR)){
                fmt::fprintfln(ctxt.buffer, "\t%{} =l add $lit.{}, 16", dest,
                    push_str(ctxt, txt))!;
            } else {
                fmt::fprintfln(ctxt.buffer, "\t%{} =l copy $lit.{}", dest,
                    push_str(ctxt, txt))!;
            };
        case =>
            assert(false, "unreachable");
        };
    };
    if(m_meta.pre is operator){
        switch(m_meta.pre as operator){
        case operator::MIN =>
            fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} neg %{0}", dest, move_t)!;
        case operator::BANG =>
            fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} ceq{1} %{0}, 0", dest, move_t)!;
        case operator::NOT =>
            fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} xor %{0}, 18446744073709551615",
                dest, move_t)!;
        case operator::LENGTH =>
            fmt::fprintfln(ctxt.buffer, "\t%{0}.len =l add %{0}, 8", dest)!;
            fmt::fprintfln(ctxt.buffer, "\t%{0} =l loadl %{0}.len", dest)!;
        case =>
            assert(false, "unreachable");
        };
    };
};

fn gen_stack_array(ctxt: *context, array: *array_meta, dest: str) (void | COMPERR) = {
    const item_size = type_size(array.itm_tpe);
    const array_size = len(array.items) * item_size + 16;
    stack_allocate_array(ctxt, dest, array_size, len(array.items));

    let count = 0z;
    for(let item .. array.items){
        const index = fmt::asprintf("{}.{}", dest, count)!;
        defer free(index);
        gen_exp(ctxt, item, index, array.itm_tpe)?;

        fmt::fprintfln(ctxt.buffer, "\tstore{} %{}, %{}.ptr", qbe_t(array.itm_tpe), index, dest)!;
        fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l add %{0}.ptr, {1}",
            dest, item_size)!;
        count += 1;
    };
};

fn stack_allocate_array(ctxt: *context, dest: str, array_size: size, length: size) void = {
    const name = strings::replace(dest, "'", ".q")!;
    defer free(name);

    fmt::fprintfln(ctxt.buffer, "\t%{0} =l alloc8 {1}\n\t%{0}.ptr =l copy %{0}",
        name, array_size)!;
    fmt::fprintfln(ctxt.buffer, "\tstorel {}, %{}", array_size, name)!;
    fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l add %{0}.ptr, 8", name)!;
    fmt::fprintfln(ctxt.buffer, "\tstorel {}, %{}.ptr", length, name)!;
    fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l add %{0}.ptr, 8", name)!;
};

fn gen_array_index(ctxt: *context, index: *index_meta, dest: str) (void | COMPERR) = {
    const array_name =
        match(index.array.meta){
        case let var: *var_meta =>
            yield fix_global(var);
        case let funcall: *funcall_meta =>
            gen_funcall(ctxt, index.array)?;
            yield strings::replace(funcall.dest as str, "'", ".q")!;
        case =>
            assert(false, "unreachable");
            yield "";
        };
    defer free(array_name);
    fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l copy %{0}", array_name)!;

    const index_id = fmt::asprintf("{}.item", array_name)!;
    defer free(index_id);

    const i_meta = index.index.meta as *expr_meta;
    const index_t = qbe_t(i_meta.tpe);

    gen_exp(ctxt, index.index, index_id, i_meta.tpe)?;
    fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} mul %{0}, {2}",
        index_id, index_t, type_size(index.tpe))!;
    fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} add %{0}, 16", index_id, index_t)!;

    fmt::fprintfln(ctxt.buffer, "\t%{0}.ptr =l add %{0}.ptr, %{1}",
        array_name, index_id)!;
    fmt::fprintfln(ctxt.buffer, "\t%{} =l load{} %{}.ptr",
        dest, qbe_t(index.tpe, mode::LOAD), array_name)!;
};

fn gen_member(ctxt: *context, member: *ast, exp_type: lichen_t)
    (str | COMPERR) = {
    const m_meta = member.meta as *member_meta;
    match(m_meta.val){
    case let node: *ast =>
        match(node.meta){
        case let var: *var_meta =>
            const move_t = qbe_t(exp_type, mode::ASSIGN);
            let name = fix_global(var);
            defer free(name);
            if(is_subtype(var.name.itype, primitive::NUMBER)){
                if(var.name.glob){
                    if(is_subtype(var.name.itype, primitive::NUMBER)){
                        fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} load{2} ${0}",
                            name, qbe_t(var.name.itype, mode::ASSIGN),
                            qbe_t(var.name.itype, mode::LOAD))!;
                    } else {
                        fmt::fprintfln(ctxt.buffer, "\t%{0} =l copy ${0}", name)!;
                    };
                };
                if(m_meta.pre is operator){
                    switch(m_meta.pre as operator){
                    case operator::BANG =>
                        const old_name = name;
                        name = fmt::asprintf("{}.mod", name)!;
                        defer free(old_name);
                        fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} ceq{1} %{2}, 0",
                            name, move_t, old_name)!;
                    case operator::NOT =>
                        const old_name = name;
                        name = fmt::asprintf("{}.mod", name)!;
                        defer free(old_name);
                        fmt::fprintfln(ctxt.buffer, "\t%{} ={} xor %{}, 18446744073709551615",
                            name, move_t, old_name)!;
                    case operator::LENGTH =>
                        fmt::fprintfln(ctxt.buffer, "\t%{0}.len =l add %{0}, 8", name)!;
                        fmt::fprintfln(ctxt.buffer, "\t%{0} =l loadl %{0}.len", name)!;
                    case =>
                        assert(false, "unreachable");
                    };
                };
                if(comp_type(var.name.itype, exp_type) || is_subtype(exp_type, var.name.itype) ||
                    type_size(exp_type) <= type_size(var.name.itype)){
                    return fmt::asprintf("%{}", name)!;
                } else {
                    const wrap = fmt::asprintf("%{}.{}", name, move_t)!;
                    fmt::fprintfln(ctxt.buffer, "\t{} ={} ext{} %{}",
                        wrap, move_t, qbe_t(var.name.itype, mode::LOAD), name)!;
                    return wrap;
                };
            } else if(comp_type(var.name.itype, primitive::STR)){
                if(var.glob){
                    fmt::fprintfln(ctxt.buffer, "\t%{0} ={1} copy ${0}",
                        name, move_t)!;
                };
                return fmt::asprintf("%{}", name)!;
            } else {
                assert(false, "TODO: ratios");
                return "";
            };
        case let exp: *expr_meta =>
            const move_t = qbe_t(exp_type, mode::ASSIGN);
            const wrap = fmt::asprintf("%exp.{}", node.path[0].pos)!;
            const slice = strings::sub(wrap, 1);

            gen_exp(ctxt, node, slice, exp.tpe)?;
            if(m_meta.pre is operator){
                switch(m_meta.pre as operator){
                case operator::BANG =>
                fmt::fprintfln(ctxt.buffer, "\t{0} ={1} ceq{1} {0}, 0", wrap, move_t)!;
                case operator::NOT =>
                    fmt::fprintfln(ctxt.buffer, "\t{0} ={1} xor {0}, 18446744073709551615",
                        wrap, move_t)!;
                case operator::LENGTH =>
                    fmt::fprintfln(ctxt.buffer, "\t{0}.len =l add {0}, 8", wrap)!;
                    fmt::fprintfln(ctxt.buffer, "\t{0} =l loadl {0}.len", wrap)!;
                case =>
                    assert(false, "unreachable");
                };
            };
            return wrap;
        case let funcall: *funcall_meta =>
            const wrap = fmt::asprintf("%exp.{}", node.path[0].pos)!;
            const slice = strings::sub(wrap, 1);

            gen_funcall(ctxt, node, slice)?;
            return wrap;
        case *for_meta =>
            const wrap = fmt::asprintf("%exp.{}", node.path[0].pos)!;
            const slice = strings::sub(wrap, 1);

            gen_for_iterator(ctxt, node, slice)?;
            return wrap;
        case *if_else_meta =>
            const wrap = fmt::asprintf("%exp.{}", node.path[0].pos)!;
            const slice = strings::sub(wrap, 1);

            gen_if_else(ctxt, node, slice)?;
            if(m_meta.pre is operator && !is_subtype(exp_type, primitive::UNIT) &&
                !is_subtype(exp_type, primitive::VOID)){
                const move_t = qbe_t(exp_type, mode::ASSIGN);
                switch(m_meta.pre as operator){
                case operator::BANG =>
                    fmt::fprintfln(ctxt.buffer, "\t{0} ={1} ceq{1} {0}, 0", wrap, move_t)!;
                case operator::NOT =>
                    fmt::fprintfln(ctxt.buffer, "\t{0} ={1} xor {0}, 18446744073709551615",
                        wrap, move_t)!;
                case operator::LENGTH =>
                    fmt::fprintfln(ctxt.buffer, "\t{0}.len =l add {0}, 8", wrap)!;
                    fmt::fprintfln(ctxt.buffer, "\t{0} =l loadl {0}.len", wrap)!;
                case =>
                    assert(false, "unreachable");
                };
            };
            return wrap;
        };
    case let tok: tkval =>
        match(tok){
        case let kwd: keyword =>
            switch(kwd){
            case keyword::TODO =>
                if(is_subtype(exp_type, primitive::STR)){
                    return strings::dup("$rt_zero")!;
                } else {
                    return strings::dup("0")!;
                };
            case =>
                assert(false, "unreachable");
                return "";
            };
        case let num: size =>
            const move_t = qbe_t(exp_type, mode::ASSIGN);
            const val = fmt::asprint(num)!;
            if(m_meta.pre is operator){
                defer free(val);
                const wrap = fmt::asprintf("%exp.{}", member.path[0].pos)!;
                switch(m_meta.pre as operator){
                case operator::BANG =>
                    fmt::fprintfln(ctxt.buffer, "\t{0} ={1} ceq{1} {2}, 0",
                        wrap, move_t, val)!;
                case operator::NOT =>
                    fmt::fprintfln(ctxt.buffer, "\t{} ={} xor {}, 18446744073709551615",
                        wrap, move_t, val)!;
                case =>
                    assert(false, "unreachable");
                };
                return wrap;
            } else {
                return val;
            };
        case let txt: str =>
            const move_t = qbe_t(exp_type, mode::ASSIGN);
            if(m_meta.pre is operator){
                switch(m_meta.pre as operator){
                case operator::LENGTH =>
                    const id = push_str(ctxt, txt);
                    const wrap = fmt::asprintf("%l.{}", id)!;
                    fmt::fprintfln(ctxt.buffer, "\t%{}.len =l add $lit.{}, 8", id)!;
                    fmt::fprintfln(ctxt.buffer, "\t%{} =l loadl %{}.len", wrap, id)!;
                    return wrap;
                case =>
                    assert(false, "unreachable");
                    return "";
                };
            } else {
                if(comp_type(exp_type, primitive::CSTR)){
                    const id = push_str(ctxt, txt);
                    const out = fmt::asprintf("%cstr.{}", id)!;
                    fmt::fprintfln(ctxt.buffer, "\t{} =l add $lit.{}, 16", out, id)!;
                    return out;
                } else {
                    return fmt::asprintf("$lit.{}", push_str(ctxt, txt))!;
                };
            };
        case =>
            assert(false, "unreachable");
            return "";
        };
    };
};

// evaluates an "use" statement
fn eval_use(ctxt: *context, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, begin,
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
    end = pop_assert(ctxt, end + 1, operator::ASG,
        "expected %bmodule binding assignment%r, but got %y{}")?;
    end = pop_assert(ctxt, end, keyword::USE,
        "expected %bkeyword \"use\"%r, but got %y{}")?;

    tk = next_tk(ctxt, end,
        "expected %bmodule path%r, but got %y{}")?;
    if(!(tk.val is str)){
        move_ptr(ctxt, tk);
        return error(ctxt,
            "expected %bmodule path%r, but got %y{}",
            strtoken(tk.val));
    };
    end = pop_assert(ctxt, end + 1, symbol::EOL,
        "expected %bend of line%r, but got %y{}")?;

    const path = tk.val as str;
    const stdpath = strings::concat(ctxt.libpath, path)!;
    defer free(stdpath);
    const file =
        if(os::exists(stdpath)){
            yield stdpath;
        } else {
            const prepath =
                if(strings::index(ctxt.name, "/") is size){
                    yield strings::rcut(ctxt.name, "/").0;
                } else {
                    yield ".";
                };
            yield strings::concat(prepath, "/", path)!;
        };

    if(ctxt.name == file){
        move_ptr(ctxt, tk);
        return error(ctxt, "cannot recursively use a module");
    };

    const module = compile(file, ctxt.libpath, ctxt.literals, ctxt.typedefs)?;
    push_module(ctxt, bind, module)?;
    const node = new_node();
    node.kind = path_t::IMPORT;
    node.path = ctxt.tokens[begin..end];

    return (node, end);
};

// evaluates a constant definition. assumes `at` is pointing to the expression's namespace
fn eval_c_def(ctxt: *context, at: size, pub: bool = false)
    ((*ast, size) | COMPERR) = {
    const max = len(ctxt.tokens);
    const begin = at;
    let end = at;
    const name = ctxt.tokens[end].val as ident;

    end += 1;
    let tk = next_tk(ctxt, end,
        "expected %btype notation%r, but got %y{}")?;
    const tpe = tk;

    if(comp_tk(tk.val, operator::ASG)){
        tk = next_tk(ctxt, end + 1,
            "expected %buse statement%r, but got %y{}")?;
        if(comp_tk(tk.val, keyword::USE)){
            return eval_use(ctxt, begin);
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
    end = pop_assert(ctxt, end, operator::ASG,
        "expected %bconstant definition assignment%r, but got %y{}")?;

    tk = next_tk(ctxt, end,
        "expected %bconstant expression%r or "
        "%buse statement%r, but got %y{}")?;

    const old_eval = ctxt.eval_t;
    ctxt.eval_t = eval_kind::MOV;
    const (val, _end) = eval_c_exp(ctxt, end, name.itype)?;
    ctxt.eval_t = old_eval;

    end = pop_assert(ctxt, _end, symbol::EOL,
        "expectend %bend of line%r, but got %y{}")?;

    const ffi: (void | str) =
        if(comp_tk(val.path[0].val, symbol::FFI)){
            yield (val.path[1].val as ident).id;
        };
    const node = new_node();
    node.kind = path_t::CONST_DEF;
    node.meta = alloc(var_meta {
        pos = ctxt.tokens[begin],
        ffi = ffi,
        mod = void,
        rets = ctxt.eval_t,
        glob = true,
        name = name,
    })!;
    node.inner = val;
    node.path = ctxt.tokens[begin..end];
    return (node, end);
};

// evaluates a constant expression
fn eval_c_exp(ctxt: *context, at: size, hint: lichen_t)
    ((*ast, size) | COMPERR) = {
    const max = len(ctxt.tokens);
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, end,
        "expected %bcontant value%r, but got %y{}")?;

    const meta = expr_meta {
        rets = ctxt.eval_t,
        tpe = hint,
        members = [],
    };

    let tpe: lichen_t = primitive::ANY;
    if(tk.val is operator && (comp_tk(tk.val, operator::PLS) ||
        comp_tk(tk.val, operator::MIN))){
        const oper = tk.val as operator;
        append(meta.members, oper)!;
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %bcontant value%r, but got %y{}")?;
    };
    const (memb, _end) = eval_c_val(ctxt, end, hint)?;
    const m_meta = memb.meta as *member_meta;
    end = _end;

    tpe = push_type(ctxt, tpe, m_meta.tpe);
    append(meta.members, memb)!;

    tk = next_tk(ctxt, end,
        "expected %boperator%r or %bend of line%r, but got %y{}")?;

    // keep parsing expression
    for(!comp_tk(tk.val, symbol::EOL) && end < max){
        if(!(tk.val is operator)){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %boperator%r or %bend of line%r, but got %y{}",
                strtoken(tk.val));
        } else if(!is_binary(tk.val as operator)){
            move_ptr(ctxt, tk);
            return error(ctxt, "invalid %bbinary operator");
        } else {
            const op = tk.val as operator;
            switch(op){
            case operator::PLS =>
                if(!is_subtype(tpe, primitive::STR) &&
                    !is_subtype(tpe, primitive::NUMBER) &&
                    !is_subtype(tpe, primitive::RATIO)){
                    move_ptr(ctxt, tk);
                    return error(ctxt, "cannot perform arithmetic on %b{}",
                        strtype(tpe));
                };
            case =>
                if(!is_subtype(tpe, primitive::NUMBER) &&
                    !is_subtype(tpe, primitive::RATIO)){
                    move_ptr(ctxt, tk);
                    return error(ctxt, "cannot perform arithmetic on %b{}",
                        strtype(tpe));
                };
            };
            append(meta.members, op)!;
        };
        const (mem_r, _end) = eval_c_val(ctxt, end + 1, hint)?;
        const mr_meta = mem_r.meta as *member_meta;
        tpe = push_type(ctxt, tpe, mr_meta.tpe);
        append(meta.members, mem_r)!;
        end = _end;
        tk = next_tk(ctxt, end,
            "expected %bcontant value%r, but got %y{}")?;
    };
    if(!comp_tk(tk.val, symbol::EOL)){
        move_ptr(ctxt, tk);
        return error(ctxt, "expected %bend of line%r, but got %y{}",
            strtoken(tk.val));
    };
    meta.tpe = push_type(ctxt, meta.tpe, tpe);
    const node = new_node();
    node.kind = path_t::CONST_EXP;
    node.meta = alloc(meta)!;
    node.path = ctxt.tokens[begin..end];
    return (node, end);
};

// evaluates a constant value
fn eval_c_val(ctxt: *context, at: size, hint: lichen_t)
    ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    const meta = member_meta {
        pre = void,
        val = eof,
        tpe = hint,
    };
    let tk = next_tk(ctxt, end,
        "expected %bvalid member%r, but got %y{}")?;
    if(tk.val is operator){
        const op = tk.val as operator;
        if(!is_unary(op)){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bvalid unary operator%r, but got {}",
                strtoken(op));
        };
        meta.pre = op;
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %bvalid member%r, but got %y{}")?;
    };
    match(tk.val){
    case let num: size =>
        meta.tpe = push_type(ctxt, meta.tpe, primitive::NUMBER);
        meta.val = num: tkval;
        end += 1;
    case let txt: str =>
        meta.tpe = push_type(ctxt, meta.tpe, primitive::STR);
        meta.val = txt: tkval;
        end += 1;
    case let sym: symbol =>
        if(sym == symbol::FFI){
            tk = next_tk(ctxt, end,
                "expected %blink symbol%r, but got %y{}")?;
            meta.val = sym;
            end += 2;
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
    if(comp_tk(ctxt.tokens[begin].val, operator::LENGTH)){
        if(!is_subtype(meta.tpe, primitive::STR)){
            move_ptr(ctxt, ctxt.tokens[begin]);
            return error(ctxt, "the %blength operator%r can only operate on strings"); // TODO
        };
    } else if(meta.pre is operator){
        if(is_subtype(meta.tpe, primitive::STR)){
            move_ptr(ctxt, ctxt.tokens[begin]);
            return error(ctxt, "cannot use the %b{}%r on strings",
                strtoken(meta.pre as operator));
        };
    };
    const node = new_node();
    node.kind = path_t::CONST_VAL;
    node.meta = alloc(meta)!;
    node.path = ctxt.tokens[begin..end];
    return (node, end);
};

// evaluates a function definition
fn eval_fun_def(ctxt: *context, at: size, pub: bool = false)
    ((*ast, size) | COMPERR) = {
    const max = len(ctxt.tokens);
    const begin = at;
    let end = at;
    let tk = ctxt.tokens[end];

    assert(comp_tk(tk.val, keyword::FN));
    end += 1;

    // function name
    tk = next_tk(ctxt, end,
        "expected %bvalid function name%d, but got %r{}")?;
    if(!((tk.val) is ident)){
        move_ptr(ctxt, tk);
        return error(ctxt, "expected %bvalid function name%r, but got %y{}",
            strtoken(tk.val));
    };
    const name = tk.val as ident;
    name.pub = pub;
    const (param, _end) = eval_param_l(ctxt, end + 1)?;

    // function type
    const (tpe, _end) = eval_type(ctxt, _end)?;
    if(tpe is void){
        move_ptr(ctxt, ctxt.tokens[_end]);
        return error(ctxt, "expected %bvalid function type%r, but got %y{}",
            strtoken(tk.val));
    };

    // function assignment
    end = pop_assert(ctxt, _end, operator::ASG,
        "expected %bfunction body assignment%r, but got %y{}")?;

    const (efx, ffi, _end) = eval_efx(ctxt, end)?;
    end = _end;
    const s_begin = end;
    if(ffi is void){
        end = skip_scope(ctxt, end)?;
    };
    end = pop_assert(ctxt, end, symbol::EOL,
        "expected %bend of line%r, but got %y{}")?;

    const node = new_node();
    node.kind = path_t::FUN_DEF;
    node.meta = alloc(fn_meta {
        pos = ctxt.tokens[begin],
        ffi = ffi,
        mod = void,
        used = false,
        generated = false,
        name = name,
        origin = ctxt.name,
        params = param,
        variadic = false,
        fn_type = tpe: lichen_t,
        effects = efx,
        scope_begin = s_begin,
    })!;
    node.path = ctxt.tokens[begin..end];
    return (node, end);
};

// evaluates a function tag setpath
fn eval_efx(ctxt: *context, at: size)
    (([]tkval, (void | str), size) | COMPERR) = {
    let end = at;
    let efx = []: []tkval;
    let ffi: (void | str) = void;
    let tk = next_tk(ctxt, end,
        "expected %beffect tag%r or %bscope definition%r, but got %y{}")?;
    if(tk.val is ident || comp_tk(tk.val, keyword::DO)){
        append(efx, tk.val)!;
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %beffect tag list continuation%r or "
            "%bscope definition%r, but got %y{}")?;

        if(comp_tk(tk.val, symbol::FFI)){
            end += 1;
            tk = next_tk(ctxt, end,
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
            for(comp_tk(tk.val, operator::BAND)){
                if(comp_tk(efx[0], keyword::DO)){
                    move_ptr(ctxt, tk);
                    return error(ctxt,
                        "the %bdo%r effect tag shall be fallowed by no additional tags");
                };
                end += 1;
                tk = next_tk(ctxt, end,
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
                tk = next_tk(ctxt, end,
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
    };
    return (efx, ffi, end);
};

// validades effects for a given called function and a caller set of tags
fn validate_efx(ctxt: *context, called: *fn_meta, caller: []tkval)
    (void | COMPERR) = {
    if(len(caller) > 0 && comp_tk(caller[0], keyword::DO)){
        if(len(called.effects) > 0 && comp_tk(called.effects[0], keyword::DO)){
            return error(ctxt, "functions tagged with %b`do` effect%r cannot "
                "call another function also tagged with `do`");
        };
        return;
    };
    if(called.origin == ctxt.name){
        for(let ld_tag .. called.effects){
            let found = false;
            for(let lr_tag .. caller){
                if(comp_tk(ld_tag, lr_tag)){
                    found = true;
                    break;
                };
            };
            if(!found){
                const tag =
                    match(ld_tag){
                    case let tag: ident =>
                        yield tag.id;
                    case keyword =>
                        yield "do";
                    };
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
    } else {
        const default = strings::rcut(
            strings::rcut(called.origin, "/").1, ".").0;
        for(let lr_tag .. caller){
            const tag = new_tk(ctxt, lr_tag);
            const mod = get_mod(ctxt, tag)!;
            const bind = mod.1.name;
            if(bind == called.origin) return;
        };
        const help = fmt::asprintf(
            "%gtry doing %p\"%d= %b{} %y{{%p\""
            "%g in the function scope definition",
            default)!;
        defer free(help);
        return error(ctxt,
            "the function %b{}%r is from the module "
            "%g{}%r, but the caller function doesn't "
            "implement this effect tag\n{}",
            called.name.id, default, help);
    };
};

// evaluates a param list
fn eval_param_l(ctxt: *context, at: size) ((*ast, size) | COMPERR) = {
    const begin = pop_assert(ctxt, at, symbol::LFT_PAR,
        "expected %bvalid parameter list%r, but got %y{}")?;
    let end = begin;
    let tk = ctxt.tokens[end];
    let meta = param_meta { ... };
    let idx = 0z;
    for(!comp_tk(tk.val, symbol::RGT_PAR)){
        tk = next_tk(ctxt, end,
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
        const (tpe, _end) = eval_type(ctxt, end)?;
        end = _end;
        if(tpe is void){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bvalid parameter type%r, but got %y{}",
                strtoken(tk.val));
        };
        meta.names[idx].itype = tpe as lichen_t;
        idx += 1;
        tk = next_tk(ctxt, end,
            "expected %bparameter list continuation%r or %bend of list%r, but got %y{}")?;
        if(comp_tk(tk.val, symbol::COMMA)){
            end += 1;
            tk = next_tk(ctxt, end,
            "expected %bparameter list continuation%r or %bend of list%r, but got %y{}")?;
        };
    };
    end += 1;
    const node = new_node();
    node.kind = path_t::PARAM_LIST;
    node.path = ctxt.tokens[begin..end];
    node.meta = alloc(meta)!;
    return (node, end);
};

// skips a scope definition
fn skip_scope(ctxt: *context, at: size) (size | COMPERR) = {
    const max = len(ctxt.tokens);
    let end = pop_assert(ctxt, at, symbol::LFT_CURLY,
        "expected %bvalid scope definition%r, but got %y{}")?;
    for(end < max; end += 1){
        if(comp_tk(ctxt.tokens[end].val, symbol::LFT_CURLY)){
            end = skip_scope(ctxt, end)?;
        } else if(comp_tk(ctxt.tokens[end].val, symbol::RGT_CURLY)){
            return end + 1;
        };
    };
    move_ptr(ctxt, ctxt.tokens[end - 1]);
    return error(ctxt, "expected %bend of scope%r, but got %y{}",
        strtoken(eof));
};

// evaluates a scope.
// remember to set the scope field of context before calling this.
fn eval_scope(ctxt: *context, at: size, hint: lichen_t = primitive::ANY,
    msg_kind: tpe_msg = tpe_msg::FN_RT) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = pop_assert(ctxt, at, symbol::LFT_CURLY,
        "expected %bvalid scope definition%r, but got %y{}")?;

    const node = new_node();
    node.kind = path_t::SCOPE;
    const meta = scope_meta {
        rets = ctxt.eval_t,
        ret_exp = null,
        eval = false,
        tpe = hint,
        members = [],
        scp = ctxt.scp,
    };
    const old_eval = ctxt.eval_t;

    let rets = false;
    let last: lichen_t = primitive::ANY;
    let tpe: lichen_t = primitive::ANY;
    let tk = next_tk(ctxt, end,
        "expected %bvalid expression%r, but got %y{}")?;
    for(!comp_tk(tk.val, symbol::RGT_CURLY)){
        if(!untyped(last) && is_subtype(last, primitive::VOID) &&
            !is_subtype(last, primitive::UNIT)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "no additional code shall follow a %yhalt statement");
        };
        match(tk.val){
        case let oper: operator =>
            if(oper == operator::MAP){
                rets = true;
                const ret_pos = tk;
                const (exp, _end) = eval_expression(ctxt, end + 1,
                    hint, msg_kind)?;
                meta.ret_exp = exp;
                end = _end;
                append(meta.members, exp)!;
                match(exp.meta){
                case let e_meta: *expr_meta =>
                    e_meta.rets = ctxt.eval_t;
                    tpe = push_type(ctxt, tpe, e_meta.tpe);
                case let v_meta: *var_meta =>
                    v_meta.rets = ctxt.eval_t;
                    tpe = push_type(ctxt, tpe, v_meta.name.itype);
                case *test_meta =>
                    move_ptr(ctxt, tk);
                    return error(ctxt, "cannot evaluate test blocks");
                };
                meta.eval = true;
                last = primitive::VOID;
            } else {
                move_ptr(ctxt, tk);
                return error(ctxt, "expected %bvalid expression%r, but got %y{}",
                    strtoken(oper));
            };
        case =>
            const (exp, _end) = eval_expression(ctxt, end)?;
            end = _end;
            append(meta.members, exp)!;
            // assert for parsed expression returning
            match(exp.meta){
            case let e_meta: *expr_meta =>
                if(e_meta.rets != eval_kind::NONE){
                    move_ptr(ctxt, tk);
                    return error(ctxt, "missing %bmap operator%r # 1");
                };
                last = e_meta.tpe;
            case let ifel_block: *if_else_meta =>
                if(ifel_block.rets != eval_kind::NONE){
                    move_ptr(ctxt, tk);
                    return error(ctxt, "missing %bmap operator%r # 2");
                };
                last = ifel_block.tpe;
            case let var: *var_meta =>
                push_var(ctxt, exp)?;
                last = var.name.itype;
            case *test_meta =>
                last = primitive::UNIT;
            case let call: *funcall_meta =>
                last = call.tpe;
            };
            ctxt.eval_t = old_eval;
        };
        end = pop_assert(ctxt, end, symbol::EOL,
            "expected %bend of line%r, but got %y{}")?;
        tk = next_tk(ctxt, end,
            "expected %bvalid expression%r, but got %y{}")?;
    };
    end = pop_assert(ctxt, end, symbol::RGT_CURLY,
        "expected %bend of scope%r, but got %y{}")?;

    if(comp_type(tpe, primitive::ANY)) tpe = primitive::UNIT;
    if(!rets) meta.rets = eval_kind::NONE;

    meta.tpe = push_type(ctxt, meta.tpe, tpe);
    node.meta = alloc(meta)!;
    node.path = ctxt.tokens[begin..end];
    return (node, end);
};

// evaluates a generic expression
fn eval_expression(ctxt: *context, at: size, hint: lichen_t = primitive::ANY,
    msg_kind: tpe_msg = tpe_msg::LT_RT) ((*ast, size) | COMPERR) = {
    let tk = ctxt.tokens[at];
    match(tk.val){
    case let kwd: keyword =>
        switch(kwd){
        case keyword::LET =>
            return eval_decl(ctxt, at)?;
        case keyword::IF, keyword::FOR, keyword::MATCH,
            keyword::TODO, keyword::FAIL =>
            return eval_abbs_exp(ctxt, at, hint, msg_kind)?;
        case keyword::TEST =>
            return eval_test(ctxt, at)?;
        case =>
            move_ptr(ctxt, tk);
            return error(ctxt, "invalid statement");
        };
    case =>
        return eval_abbs_exp(ctxt, at, hint, msg_kind)?;
    };
};

fn eval_test(ctxt: *context, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    assert(comp_tk(ctxt.tokens[at].val, keyword::TEST));

    const old_eval = ctxt.eval_t;
    ctxt.eval_t = eval_kind::NONE;
    const (exp, end) = eval_expression(ctxt, begin + 1,
        primitive::NUMBER, tpe_msg::BOOL)?;
    ctxt.eval_t = old_eval;

    move_ptr(ctxt, ctxt.tokens[at + 1]);
    const buffer = alloc(memio::dynamic())!;

    defer free(buffer);
    defer io::close(buffer)!;

    error_line(ctxt, buffer);

    const line = strings::multireplace(memio::string(buffer)!,
        ("\t", "\\t"), ("\n", "\\n"), ("\"", "\\\""), ("\'", "\\\'"))!;
    defer free(line);

    const msg = fmt::asprintf("%R{}%r test failed\\n{}\\n", gen_pos(ctxt), line)!;
    defer free(msg);

    const lit = add_color(strings::toutf8(msg));

    const node = new_node();
    node.kind = path_t::STATEMENT;
    node.path = ctxt.tokens[begin .. end];
    node.meta = alloc(test_meta {
        cond = exp,
        global = false,
        line_msg = lit,
    })!;
    return (node, end);
};

// evaluates a namespace declaration
fn eval_decl(ctxt: *context, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    assert(comp_tk(ctxt.tokens[at].val, keyword::LET));

    let tk = next_tk(ctxt, end + 1, "expected %bdeclaration's namespace%r, "
        "but got %y{}")?;
    end += 1;
    if(!(tk.val is ident)){
        move_ptr(ctxt, tk);
        return error(ctxt, "expected %bdeclarations's namespace%r, but got %y{}",
            strtoken(tk.val));
    };
    const name = tk.val as ident;
    const (tpe, _end) = eval_type(ctxt, end + 1)?;
    end = _end;

    const old_eval = ctxt.eval_t;
    ctxt.eval_t = eval_kind::MOV;

    const node = new_node();
    node.kind = path_t::DECL;
    match(tpe){
    case let tpe: lichen_t =>
        end = pop_assert(ctxt, end, operator::ASG,
            "exprected %bvalue assignment%r, but got %y{}")?;
        const eq = end;
        const (exp, _end) = eval_expression(ctxt, end, tpe)?;
        end = _end;
        node.inner = exp;
        match(exp.meta){
        case let meta: *expr_meta =>
            name.itype = push_type(ctxt, meta.tpe, tpe);
        case let meta: *if_else_meta =>
            if(len(meta.conds) == len(meta.bodies)){
                move_ptr(ctxt, tk);
                return error(ctxt, "the if block is not exhaustive");
            };
        case let meta: *var_meta =>
            name.itype = push_type(ctxt, meta.name.itype, tpe);
        };
    case void =>
        tk = next_tk(ctxt, end, "expected %bvalue assignment%r, but got %y{}")?;
        if(!comp_tk(tk.val, operator::ASG)){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bvalue assignment%r, but got %y{}",
                strtoken(tk.val));
        };
        const eq = end;
        const (exp, _end) = eval_expression(ctxt, end + 1)?;
        end = _end;
        node.inner = exp;
        match(exp.meta){
        case let meta: *expr_meta =>
            if(untyped(meta.tpe)){
                move_ptr(ctxt, tk);
                return error(ctxt, "cannot infer expression type");
            };
            name.itype = meta.tpe;
        case let meta: *var_meta =>
            name.itype = meta.name.itype;
        case let meta: *array_meta =>
            if(untyped(meta.tpe)){
                move_ptr(ctxt, tk);
                return error(ctxt, "cannot infer expression type");
            };
            name.itype = meta.tpe;
        case =>
            fmt::fatalf("missing match for {} kind", exp.kind: u8);
        };
    };
    ctxt.eval_t = old_eval;

    node.path = ctxt.tokens[begin..end];
    node.meta = alloc(var_meta {
        pos = ctxt.tokens[begin],
        ffi = void,
        mod = void,
        rets = eval_kind::NONE,
        glob = false,
        name = name,
    })!;
    return (node, end);
};

// evaluates arithmetic, boolean, binary and string expressions
fn eval_abbs_exp(ctxt: *context, at: size, hint: lichen_t = primitive::ANY,
    kind: tpe_msg = tpe_msg::LT_RT) ((*ast, size) | COMPERR) = {
    const max = len(ctxt.tokens);
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, end,
        "expected %bexpression member%r, but got %y{}")?;
    const meta = expr_meta {
        rets = eval_kind::NONE,
        tpe = hint,
        members = [],
    };
    if(tk.val is operator && (comp_tk(tk.val, operator::PLS) ||
        comp_tk(tk.val, operator::MIN))){
        const oper = tk.val as operator;
        append(meta.members, oper)!;
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %bcontant value%r, but got %y{}")?;
    };
    // eval first member;
    const (mem_l, _end) = eval_member(ctxt, end)?;
    const ml_meta = mem_l.meta as *member_meta;
    let lft_t = ml_meta.tpe;
    end = _end;
    append(meta.members, mem_l)!;
    let tpe = lft_t;

    tk = next_tk(ctxt, end,
        "expected %boperator%r or %bend of line%r, but got %y{}")?;

    // keep parsing expression
    for(!(comp_tk(tk.val, symbol::RGT_PAR) || comp_tk(tk.val, symbol::RGT_SQUARE) ||
        comp_tk(tk.val, symbol::LFT_CURLY) || comp_tk(tk.val, symbol::COMMA) ||
        comp_tk(tk.val, symbol::EOL)) && end < max){
        const oper =
            if(!(tk.val is operator)){
                move_ptr(ctxt, tk);
                return error(ctxt, "expected %boperator%r or %bend of line%r, but got %y{}",
                    strtoken(tk.val));
            } else if(!is_binary(tk.val as operator)){
                move_ptr(ctxt, tk);
                return error(ctxt, "invalid %bbinary operator");
            } else {
                yield tk.val as operator;
            };
        append(meta.members, oper)!;

        const (mem_r, _end) = eval_member(ctxt, end + 1)?;
        const mr_meta = mem_r.meta as *member_meta;
        let rgt_t = mr_meta.tpe;
        end = _end;
        append(meta.members, mem_r)!;

        move_ptr(ctxt, tk);
        switch(oper){
        case operator::LAND, operator::LOR =>
            tpe = mr_meta.tpe;
        case operator::EQL, operator::NEQ =>
            if(!untyped(lft_t) && !untyped(rgt_t)){
                if(!comp_type(lft_t, rgt_t)){
                    return error(ctxt,
                        "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                        strtype(lft_t), strtype(rgt_t));
                };
                tpe = push_type(ctxt, tpe, rgt_t);
            } else {
                if(!is_subtype(lft_t, rgt_t)){
                    return error(ctxt,
                        "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                        strtype(lft_t), strtype(rgt_t));
                };
                if(untyped(lft_t)){
                    tpe = push_type(ctxt, tpe, rgt_t);
                } else {
                    tpe = push_type(ctxt, tpe, lft_t);
                };
            };
            if(!is_subtype(tpe, primitive::NUMBER) &&
                !is_subtype(tpe, primitive::RATIO)){
                tpe = primitive::U64;
            };
        case operator::LEQ, operator::GEQ, operator::LST, operator::GTT =>
            if(!untyped(lft_t) && !untyped(rgt_t)){
                if(!comp_type(lft_t, rgt_t)){
                    return error(ctxt,
                        "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                        strtype(lft_t), strtype(rgt_t));
                };
                tpe = push_type(ctxt, tpe, rgt_t);
            } else {
                if(!is_subtype(lft_t, rgt_t)){
                    return error(ctxt,
                        "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                        strtype(lft_t), strtype(rgt_t));
                };
                if(untyped(lft_t)){
                    tpe = push_type(ctxt, tpe, rgt_t);
                } else {
                    tpe = push_type(ctxt, tpe, lft_t);
                };
            };
            if(!is_subtype(rgt_t, primitive::NUMBER) &&
                !is_subtype(rgt_t, primitive::NUMBER)){
                return error(ctxt, "invalid comparison operator for %b{}",
                    strtype(rgt_t));
            };
        case operator::MUL =>
            if(is_subtype(lft_t, primitive::STR) ||
                is_subtype(rgt_t, primitive::STR)){
                if(is_subtype(lft_t, primitive::STR) &&
                    !is_subtype(rgt_t, primitive::STR)){
                    if(!is_subtype(rgt_t, primitive::NUMBER)){
                        return error(ctxt, "cannot %brepeat a string%r by %y{}",
                            strtype(rgt_t));
                    };
                } else if(is_subtype(rgt_t, primitive::STR) &&
                    !is_subtype(lft_t, primitive::STR)){
                    if(!is_subtype(lft_t, primitive::NUMBER)){
                        return error(ctxt, "cannot %brepeat a string%r by %y{}",
                            strtype(lft_t));
                    };
                } else if(!is_subtype(lft_t, rgt_t)){
                    return error(ctxt,
                    "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                    strtype(lft_t), strtype(rgt_t));
                };
                tpe = push_type(ctxt, tpe, primitive::STR);
            } else {
                if(!untyped(lft_t) && !untyped(rgt_t)){
                    if(!comp_type(lft_t, rgt_t)){
                        return error(ctxt,
                            "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                            strtype(lft_t), strtype(rgt_t));
                    };
                    tpe = push_type(ctxt, tpe, rgt_t);
                } else {
                    if(!is_subtype(ml_meta.tpe, rgt_t)){
                        return error(ctxt,
                            "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                            strtype(ml_meta.tpe), strtype(rgt_t));
                    };
                    if(untyped(lft_t)){
                        tpe = push_type(ctxt, tpe, rgt_t);
                    } else {
                        tpe = push_type(ctxt, tpe, lft_t);
                    };
                };
                if(!is_subtype(tpe, primitive::NUMBER) &&
                    !is_subtype(tpe, primitive::NUMBER)){
                    return error(ctxt, "cannot perform arithmetic on %b{}",
                        strtype(tpe));
                };
            };
        case =>
            if(!untyped(lft_t) && !untyped(rgt_t)){
                if(!comp_type(lft_t, rgt_t)){
                    return error(ctxt,
                        "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                        strtype(lft_t), strtype(rgt_t));
                };
                tpe = push_type(ctxt, tpe, rgt_t);
            } else {
                if(!is_subtype(lft_t, rgt_t)){
                    return error(ctxt,
                        "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                        strtype(lft_t), strtype(rgt_t));
                };
                if(untyped(lft_t)){
                    tpe = push_type(ctxt, tpe, rgt_t);
                } else {
                    tpe = push_type(ctxt, tpe, lft_t);
                };
            };
            if(!is_subtype(tpe, primitive::NUMBER) &&
                !is_subtype(tpe, primitive::NUMBER)){
                return error(ctxt, "cannot perform arithmetic on %b{}",
                    strtype(tpe));
            };
        };
        lft_t = tpe;

        // update type when it is a comparison
        tk = next_tk(ctxt, end,
            "expected %bcontant value%r, but got %y{}")?;
    };
    if(!untyped(tpe)){
        move_ptr(ctxt, ctxt.tokens[begin]);
        meta.tpe = push_type(ctxt, meta.tpe, tpe);
    } else {
        assert_subtype(ctxt, tpe, hint, ctxt.tokens[begin])?;
        meta.tpe = hint;
    };

    if(!comp_type(hint, primitive::ANY)){
        if(untyped(ml_meta.tpe) && len(meta.members) == 1){
            const m_meta = (meta.members[0] as *ast).meta as *member_meta;
            m_meta.tpe = hint;
            if(m_meta.val is *ast)
            match((m_meta.val as *ast).meta){
            case let a_meta: *array_meta =>
                a_meta.tpe = hint;
                a_meta.itm_tpe = from_array(hint);
            case let e_meta: *expr_meta =>
                e_meta.tpe = hint;
            case => void;
            };
        };
    };
    const node = new_node();
    node.kind = path_t::EXPR;
    node.path = ctxt.tokens[begin..end];
    node.meta = alloc(meta)!;
    return (node, end);
};

// evaluates an expression member
fn eval_member(ctxt: *context, at: size, hint: lichen_t = primitive::ANY)
    ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, end,
        "expected %bvalid member%r, but got %y{}")?;
    const meta = member_meta {
        pre = void,
        val = eof,
        tpe = hint,
    };
    if(tk.val is operator){
        const op = tk.val as operator;
        if(!is_unary(op)){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bvalid unary operator%r, but got {}",
                strtoken(op));
        };
        meta.pre = op;
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %bvalid member%r, but got %y{}")?;
    };
    let pos = tk;
    match(tk.val){
    case let sym: symbol =>
        if(sym == symbol::LFT_PAR){
            const (exp, _end) = eval_expression(ctxt, end + 1)?;
            end = pop_assert(ctxt, _end, symbol::RGT_PAR,
                "expected %bclosing parenthesis%r, but got %y{}")?;
            const e_meta = exp.meta as *expr_meta;

            const (new_tpe, _end) = eval_type(ctxt, end)?;
            end = _end;
            if(new_tpe is lichen_t){
                pos = tk;
                e_meta.tpe = cast(ctxt, e_meta.tpe, new_tpe as lichen_t, tk)?;
            };
            meta.tpe = push_type(ctxt, meta.tpe, e_meta.tpe);
            meta.val = exp;
        } else if(sym == symbol::LFT_SQUARE){
            const (arr, _end) = eval_array_lit(ctxt, at, hint)?;
            end = _end;
            const a_meta = arr.meta as *array_meta;

            tk = next_tk(ctxt, end,
                "expected %barray type casting%r, but got %y{}")?;

            if(tk.val is primitive){
                const new = tk.val as primitive;
                if(!is_subtype(a_meta.itm_tpe, new)){
                    move_ptr(ctxt, tk);
                    return error(ctxt, "casting type %b{}%r invalid for this array",
                        strtoken(new));
                };
                a_meta.tpe = as_array(ctxt, new);
                a_meta.itm_tpe = new;
                meta.tpe = a_meta.tpe;
                end += 1;
            };
            meta.tpe = push_type(ctxt, meta.tpe, a_meta.tpe);
            meta.val = arr;
        } else {
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bvalid member%r, but got %y{}",
                strtoken(tk.val));
        };
    case let num: size =>
        end += 1;
        let tpe: lichen_t = primitive::NUMBER;
        const (new_tpe, _end) = eval_type(ctxt, end)?;
        end = _end;
        if(new_tpe is lichen_t){
            pos = tk;
            tpe = cast(ctxt, tpe, new_tpe as lichen_t, tk)?;
        };
        meta.tpe = push_type(ctxt, meta.tpe, tpe);
        meta.val = num: tkval;
    case let idt: ident =>
        // TODO: field access
        match(get_var(ctxt.scp as *scope, idt)){
        case let var: *ast =>
            end += 1;
            const v_meta = var.meta as *var_meta;
            tk = next_tk(ctxt, end, "expected %btype casting%r or "
                "%bexpression continuation%r, but got %y{}")?;
            let tpe = unary_fix_type(ctxt, pos, meta.pre, v_meta.name.itype)?;

            const (new_tpe, _end) = eval_type(ctxt, end)?;
            end = _end;
            if(new_tpe is lichen_t){
                pos = tk;
                tpe = cast(ctxt, tpe, new_tpe as lichen_t, tk)?;
            } else if(comp_tk(tk.val, symbol::LFT_SQUARE)){
                return eval_array_index(ctxt, end, var);
            };
            meta.tpe = push_type(ctxt, meta.tpe, tpe);
            meta.val = var;
        case =>
            tk = next_tk(ctxt, end + 1,
                "expected %bexpression continuation%r, but got %y{}")?;
            // funcall
            if(comp_tk(tk.val, symbol::LFT_PAR)){
                const (exp, _end) = eval_funcall(ctxt, end)?;
                end = _end;

                const call = exp.meta as *funcall_meta;
                tk = next_tk(ctxt, end, "expected %btype casting%r or "
                    "%bexpression continuation%r, but got %y{}")?;
                const fun = call.fun;
                const f_meta = fun.meta as *fn_meta;

                let tpe = unary_fix_type(ctxt, pos, meta.pre, call.tpe)?;
                const (new_tpe, _end) = eval_type(ctxt, end)?;
                end = _end;
                if(new_tpe is lichen_t){
                    pos = tk;
                    tpe = cast(ctxt, tpe, new_tpe as lichen_t, tk)?;
                } else if(comp_tk(tk.val, symbol::LFT_SQUARE)){
                    call.dest = fmt::asprintf("{}.call", f_meta.name.id)!;
                    return eval_array_index(ctxt, end, exp);
                };
                meta.tpe = push_type(ctxt, meta.tpe, tpe);
                meta.val = exp;
            // module field
            } else if((end + 2 < len(ctxt.tokens) &&
                comp_tk(ctxt.tokens[end + 1].val, symbol::FIELD)) &&
                ctxt.tokens[end + 2].val is ident){
                const field = ctxt.tokens[end + 2].val as ident;
                match(get_mod_var(ctxt, ctxt.tokens[end], field)){
                case let var: *ast =>
                    end += 3;
                    const v_meta = var.meta as *var_meta;
                    tk = next_tk(ctxt, end, "expected %btype casting%r or "
                        "%bexpression continuation%r, but got %y{}")?;
                    let tpe = unary_fix_type(ctxt, pos, meta.pre, v_meta.name.itype)?;
                    const (new_tpe, _end) = eval_type(ctxt, end)?;
                    end = _end;
                    if(new_tpe is lichen_t){
                        pos = tk;
                        tpe = cast(ctxt, v_meta.name.itype, new_tpe as lichen_t, tk)?;
                    } else if(comp_tk(tk.val, symbol::LFT_SQUARE)){
                        return eval_array_index(ctxt, end, var);
                    };
                    meta.tpe = push_type(ctxt, meta.tpe, tpe);
                    meta.val = var;
                case let e: COMPERR =>
                    tk = next_tk(ctxt, end + 3,
                        "expected %bfunction call%r or %boperator%r, but got %y{}")?;
                    if(comp_tk(tk.val, symbol::LFT_PAR)){
                        const (exp, _end) = eval_funcall(ctxt, end)?;
                        end = _end;

                        const call = exp.meta as *funcall_meta;
                        tk = next_tk(ctxt, end, "expected %btype casting%r or "
                            "%bexpression continuation%r, but got %y{}")?;
                        const fun = call.fun;
                        const f_meta = fun.meta as *fn_meta;

                        let tpe = unary_fix_type(ctxt, pos, meta.pre, call.tpe)?;
                        const (new_tpe, _end) = eval_type(ctxt, end)?;
                        end = _end;
                        if(new_tpe is lichen_t){
                            pos = tk;
                            tpe = cast(ctxt, tpe, new_tpe as lichen_t, tk)?;
                        } else if(comp_tk(tk.val, symbol::LFT_SQUARE)){
                            call.dest = fmt::asprintf("{}.call", f_meta.name.id)!;
                            return eval_array_index(ctxt, end, exp);
                        };
                        meta.tpe = push_type(ctxt, meta.tpe, tpe);
                        meta.val = exp;
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
    case let txt: str =>
        if(meta.pre is operator){
            if(meta.pre as operator != operator::LENGTH){
                move_ptr(ctxt, pos);
                return error(ctxt, "invalid unary operator for %y{}",
                    strtoken(primitive::STR));
            };
            meta.tpe = primitive::U64;
        } else {
            meta.tpe = primitive::STR;
        };
        end += 1;
        const (new_tpe, _end) = eval_type(ctxt, end)?;
        end = _end;
        if(new_tpe is lichen_t){
            pos = tk;
            meta.tpe = cast(ctxt, meta.tpe, new_tpe as lichen_t, tk)?;
        };
        meta.val = txt: tkval;
        // TODO: casting to composite types
    case let kwd: keyword =>
        switch(kwd){
        case keyword::TODO =>
            end += 1;
            meta.val = kwd: tkval;
            meta.tpe = hint;
        case keyword::FAIL =>
            end += 1;
            meta.val = kwd: tkval;
            const host = ctxt.scope_owner as *fn_meta;
            if((host.fn_type is *aggregated &&
                !error_compatible(host.fn_type, host.fn_type as *aggregated)) ||
                host.fn_type is primitive || host.fn_type is *ext_array){
                move_ptr(ctxt, pos);
                return error(ctxt, "function type %b{}%r cannot return %y`fail`",
                    strtype(host.fn_type));
            };
            meta.tpe =
                if(!untyped(hint)){
                    yield
                    if(hint is *aggregated){
                        const agg = hint as *aggregated;
                        yield
                        if(agg.error){
                            yield agg;
                        } else {
                            yield new_union_t(ctxt, agg.base, true);
                        };
                    } else {
                        let base = []: []lichen_t;
                        append(base, hint)!;
                        yield new_union_t(ctxt, base, true);
                    };
                } else {
                    yield host.fn_type;
                };
        case keyword::IF =>
            const (exp, _end) = eval_if_else(ctxt, end, hint)?;
            end = _end;
            const stt_meta = exp.meta as *if_else_meta;
            let tpe = stt_meta.tpe;
            const (new_tpe, _end) = eval_type(ctxt, end)?;
            end = _end;
            if(new_tpe is lichen_t){
                pos = tk;
                tpe = cast(ctxt, tpe, new_tpe as lichen_t, tk)?;
                end += 1;
            };
            meta.tpe = push_type(ctxt, meta.tpe, tpe);
            meta.val = exp;
        case keyword::ELSE =>
            move_ptr(ctxt, tk);
            return error(ctxt, "needless else block found here");
        case keyword::MATCH =>
            assert(false, "TODO: match block");
        case keyword::FOR =>
            const (exp, _end) = eval_for_iterator(ctxt, end, hint)?;
            end = _end;
            const stt_meta = exp.meta as *for_meta;
            let tpe = stt_meta.tpe;
            const (new_tpe, _end) = eval_type(ctxt, end)?;
            end = _end;
            if(new_tpe is lichen_t){
                pos = tk;
                tpe = cast(ctxt, tpe, new_tpe as lichen_t, tk)?;
                end += 1;
            };
            meta.tpe = push_type(ctxt, meta.tpe, tpe);
            meta.val = exp;
        case =>
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %expression%r or %bstatement%r, but got %y{}",
                strtoken(kwd));
        };
    case =>
        move_ptr(ctxt, tk);
        return error(ctxt, "invalid %bexpression member%r found here");
    };
    const node = new_node();
    node.kind = path_t::MEMBER;
    node.path = ctxt.tokens[begin..end];
    node.meta = alloc(meta)!;
    return (node, end);
};

fn eval_array_lit(ctxt: *context, at: size, hint: lichen_t)
    ((*ast, size) | COMPERR) = {
    assert(comp_tk(ctxt.tokens[at].val, symbol::LFT_SQUARE));
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, end + 1,
        "expected %bnext item%r or %bend or array literal%r, but got %y{}")?;
    end += 1;

    let items = []: []*ast;
    let tpe = hint;
    const old_eval = ctxt.eval_t;
    ctxt.eval_t = eval_kind::NONE;
    for(!comp_tk(tk.val, symbol::RGT_SQUARE)){
        // TODO: array rules
        const (item, _end) = eval_expression(ctxt, end, hint, tpe_msg::ARRAY)?;
        append(items, item)!;

        const meta = item.meta as *expr_meta;
        tpe = push_type(ctxt, tpe, meta.tpe);
        end = _end;
        tk = next_tk(ctxt, end,
            "expected %bnext item%r or %bend or array literal%r, but got %y{}")?;
        if(!comp_tk(tk.val, symbol::COMMA) && !comp_tk(tk.val, symbol::RGT_SQUARE)){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bnext item%r or %bend or array literal%r, but got %y{}",
                strtoken(tk.val));
        };
        if(comp_tk(tk.val, symbol::COMMA)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bnext item%r or %bend or array literal%r, but got %y{}")?;
        };
    };
    ctxt.eval_t = old_eval;

    end = pop_assert(ctxt, end, symbol::RGT_SQUARE,
        "expected %bend of array declaration%r, but got %y{}")?;

    const arr_tpe = as_array(ctxt, tpe);
    const node = new_node();
    node.kind = path_t::ARRAY;
    node.path = ctxt.tokens[begin..end];
    node.meta = alloc(array_meta {
        tpe = arr_tpe,
        itm_tpe = tpe,
        items = items,
    })!;
    return (node, end);
};

fn eval_array_index(ctxt: *context, at: size, array: *ast) ((*ast, size) | COMPERR) = {
    assert(comp_tk(ctxt.tokens[at].val, symbol::LFT_SQUARE));
    const begin = at;

    let val_tpe: lichen_t = primitive::ANY;
    match(array.meta){
    case let var: *var_meta =>
        if(!is_subtype(var.name.itype, primitive::ARRAY)){
            move_ptr(ctxt, ctxt.tokens[begin]);
            return error(ctxt, "%g{}%r is not indexable", strtype(var.name.itype));
        };
        val_tpe = from_array(var.name.itype);
    case let funcall: *funcall_meta =>
        const fn_meta = funcall.fun.meta as *fn_meta;
        if(!is_subtype(funcall.tpe, primitive::ARRAY)){
            move_ptr(ctxt, ctxt.tokens[begin]);
            return error(ctxt, "%g{}%r is not indexable", strtype(funcall.tpe));
        };
        val_tpe =
            if(funcall.tpe is primitive){
                yield from_array(funcall.tpe);
            } else {
                yield new_array_t(ctxt, funcall.tpe);
            };
    case =>
        move_ptr(ctxt, ctxt.tokens[begin]);
        return error(ctxt, "value not indexable");
    };

    const old_eval = ctxt.eval_t;
    ctxt.eval_t = eval_kind::NONE;
    let (index, end) = eval_expression(ctxt, at + 1, primitive::NUMBER, tpe_msg::BOOL)?;
    ctxt.eval_t = old_eval;

    const meta = index.meta as *expr_meta;
    if(untyped(meta.tpe)) meta.tpe = primitive::U64;

    end = pop_assert(ctxt, end, symbol::RGT_SQUARE,
        "expected %bend of indexing%r, but got %y{}")?;

    const indexing = new_node();
    indexing.kind = path_t::INDEXING;
    indexing.path = ctxt.tokens[begin..end];
    indexing.meta = alloc(index_meta {
        tpe = val_tpe,
        array = array,
        index = index,
    })!;

    const node = new_node();
    node.kind = path_t::MEMBER;
    node.path = ctxt.tokens[begin..end];
    node.meta = alloc(member_meta {
        pre = void,
        val = indexing,
        tpe = val_tpe,
    })!;
    return (node, end);
};

fn eval_if_else(ctxt: *context, at: size, hint: lichen_t) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    let tk = ctxt.tokens[begin];
    const upper = ctxt.scp as *scope;
    const local_scp = scope {
        vars = [],
        upper = upper,
        effects = upper.effects,
    };
    defer free(local_scp.vars);
    ctxt.scp = &local_scp;

    const meta = if_else_meta {
        rets = eval_kind::NONE,
        tpe = hint,
        conds = [],
        bodies = [],
    };
    for(comp_tk(tk.val, keyword::IF)){
        // TODO: local if-else variables
        const (cond, begin_scope) = eval_expression(ctxt, end + 1)?;
        assert_subtype(ctxt, (cond.meta as *expr_meta).tpe,
            primitive::NUMBER, tk, tpe_msg::BOOL)?;
        end = begin_scope;
        append(meta.conds, cond)!;

        // eval if body
        const (if_body, _end) = eval_scope(ctxt, begin_scope,
            hint, tpe_msg::BRANCH)?;
        const if_body_meta = if_body.meta as *scope_meta;
        end = _end;
        const scp_tpe = if_body_meta.tpe;
        meta.tpe = push_type(ctxt, meta.tpe, scp_tpe);
        append(meta.bodies, if_body)!;

        tk = next_tk(ctxt, end,
            "expected %belse block%r or %bend of line%r, but got %y{}")?;

        if(comp_tk(tk.val, keyword::ELSE)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %belse block%r or %bend of line%r, but got %y{}")?;
            if(comp_tk(tk.val, keyword::IF)){
                continue;
            } else if(comp_tk(tk.val, symbol::LFT_CURLY)){
                const (else_body, _end) = eval_scope(ctxt, end, hint,
                    tpe_msg::BRANCH)?;
                const else_body_meta = else_body.meta as *scope_meta;
                end = _end;
                const scp_tpe = else_body_meta.tpe;
                meta.tpe = push_type(ctxt, meta.tpe, scp_tpe);
                append(meta.bodies, else_body)!;

                tk = next_tk(ctxt, end, "expected %bend of line%r, but got %y{}")?;
                if(!comp_tk(tk.val, symbol::EOL)){
                    move_ptr(ctxt, tk);
                    return error(ctxt, "expected %bend of line%r, but got %y{}",
                        strtoken(tk.val));
                };
                break;
            } else {
                move_ptr(ctxt, tk);
                return error(ctxt,
                    "expected %belse body%r or %belse-if block%r, but got %y{}",
                    strtoken(tk.val));
            };
        } else if(comp_tk(tk.val, symbol::EOL)){
            break;
        } else {
            move_ptr(ctxt, tk);
            return error(ctxt,
                "expected %belse block%r or %bend of line%r, but got %y{}",
                strtoken(tk.val));
        };
    };
    // non-exhaustive if
    if(len(meta.bodies) == len(meta.conds)){
        meta.tpe = push_type(ctxt, meta.tpe, primitive::UNIT);
    };
    for(let body ..& meta.bodies){
        const b_meta = body.meta as *scope_meta;
        move_ptr(ctxt, body.path[0]);
        assert_subtype(ctxt, b_meta.tpe, meta.tpe, body.path[0])?;
        b_meta.tpe = meta.tpe;
        if(b_meta.ret_exp is *ast){
            const r_exp = b_meta.ret_exp as *ast;
            match(r_exp.meta){
            case let e_meta: *expr_meta =>
                assert_subtype(ctxt, e_meta.tpe, meta.tpe, r_exp.path[0])?;
                e_meta.tpe = meta.tpe;
            case => void;
            };
        };
    };
    ctxt.scp = upper;
    const node = new_node();
    node.kind = path_t::STATEMENT;
    node.meta = alloc(meta)!;
    node.path = ctxt.tokens[begin..end];
    return (node, end);
};

fn eval_for_iterator(ctxt: *context, at: size, hint: lichen_t) ((*ast, size) | COMPERR) = {
    const begin = at;
    assert(comp_tk(ctxt.tokens[begin].val, keyword::FOR));
    let end = at + 1;

    let pairs = []: []token;
    let acc = []: []*ast;

    let tk = next_tk(ctxt, end,
        "expected %biterator item%r, but got %y{}")?;
    const next = next_tk(ctxt, end + 1,
        "expected %accumulator assignment%r or %brange operator%r, but got %y{}")?;

    let has_acc = false;
    if(comp_tk(next.val, operator::ASG) || next.val is primitive){
        has_acc = true;
        const (s_def, _end) = eval_statement_decl(ctxt, end)?;
        end = _end;
        append(acc, s_def)!;

        end = pop_assert(ctxt, end, symbol::EOL,
            "expected %biterator item%r, but got %y{}")?;

        tk = next_tk(ctxt, end,
            "expected %biterator item%r, but got %y{}")?;
    };
    for(true){
        if(!(tk.val is ident)){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %biterator item%r, but got %y{}",
                strtoken(tk.val));
        };
        if(len(pairs) == 3){
            move_ptr(ctxt, tk);
            // TODO: assert this only for iterators without accumulators (?)
            return error(ctxt, "iterators shall have either a %b3-wide window"
                "of items%r or a %bsingle item");
        };
        append(pairs, tk)!;
        check_shadowing(ctxt, tk)?;
        end += 1;
        // TODO: accumulators
        tk = next_tk(ctxt, end,
            "expected %bcomma%r or %brange operator%r, but got %y{}")?;
        if(comp_tk(tk.val, operator::RANGE)){
            break;
        } else if(!comp_tk(tk.val, symbol::COMMA)){
            move_ptr(ctxt, tk);
            return error(ctxt, "expected %bcomma%r or %brange operator%r, but got %y{}",
                strtoken(tk.val));
        };
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %bnext iterator item%r or %brange operator%r, but got %y{}")?;
    };
        if(len(pairs) == 2){
        move_ptr(ctxt, tk);
            // TODO: assert this only for iterators without accumulators (?)
        return error(ctxt, "iterators shall have either a %b3-wide window"
                "of items%r or a %bsingle item");
    };
    assert(comp_tk(tk.val, operator::RANGE));

    const old_eval = ctxt.eval_t;
    ctxt.eval_t = eval_kind::NONE;
    const (item, _end) = eval_expression(ctxt, end + 1,
        primitive::ARRAY, tpe_msg::BOOL)?;
    ctxt.eval_t = old_eval;

    end = _end;
    const i_meta = item.meta as *expr_meta;
    if(untyped(i_meta.tpe)){
        move_ptr(ctxt, ctxt.tokens[end + 1]);
        return error(ctxt, "cannot iterate over %b{}%r (an %yuntyped array%r)",
            strtype(i_meta.tpe));
    };
    const ele_tpe = from_array(i_meta.tpe);

    tk = next_tk(ctxt, end,
        "expected %bend of line%r or %bscope definition%r, but got %y{}")?;

    let out_acc = []: []token;
    let eval_tpe: lichen_t = primitive::UNIT;
    let buff_size = 0z;
    if(comp_tk(tk.val, symbol::EOL) && !has_acc){
        end = pop_assert(ctxt, end + 1, symbol::LFT_SQUARE,
            "expected %boutput buffer declaration%r, but got %y{}")?;

        tk = next_tk(ctxt, end,
            "expected %bcompile time contant buffer size%r, but got %y{}")?;
        if(!(tk.val is size)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "expected %bcompile time contant buffer size%r, but got %y{}",
                strtoken(tk.val));
        };
        eval_tpe = i_meta.tpe;
        buff_size = tk.val as size;
        end = pop_assert(ctxt, end + 1, symbol::RGT_SQUARE,
            "expected %bend of output buffer size%r, but got %y{}")?;

        tk = next_tk(ctxt, end,
            "expected %bbuffer type%r, but got %y{}")?;
        if(!(tk.val is primitive)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "expected %bbuffer type%r, but got %y{}",
                strtoken(tk.val));
        };
        if(!comp_type(ele_tpe, tk.val as primitive)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "mismatch between %bbuffer type%r (%g{}%r) and %biteration item type%r (%g{}%r)",
                strtype(ele_tpe), strtoken(tk.val));
        };
        end += 1;
    } else if(has_acc){
        end += 1;
        tk = next_tk(ctxt, end,
            "expected %bevaluation accumulator%r, but got %y{}")?;
        if(!(tk.val is ident)){
            move_ptr(ctxt, tk);
            return error(ctxt,
                "expected %bevaluation accumulator%r, but got %y{}",
                strtoken(tk.val));
        };
        const out = tk.val as ident;
        let exists = false;
        for(let a .. acc){
            const v_meta = a.meta as *var_meta;
            if(v_meta.name.id == out.id){
                exists = true;
                eval_tpe = v_meta.name.itype;
            };
        };
        if(!exists){
            move_ptr(ctxt, tk);
            return error(ctxt, "attempt to evaluate to undefined accumulator");
        };
        append(out_acc, tk)!;
        end += 1;
    };
    const upper = ctxt.scp as *scope;
    const local_scp = scope {
        vars = [],
        upper = upper,
        effects = upper.effects,
    };
    defer free(local_scp.vars);
    for(let p .. pairs){
        const pdef = new_node();
        pdef.kind = path_t::DECL;
        const meta = var_meta {
            pos = p,
            ffi = void,
            mod = void,
            rets = ctxt.eval_t,
            glob = false,
            name = p.val as ident,
        };
        meta.name.itype = ele_tpe;
        pdef.meta = alloc(meta)!;
        append(local_scp.vars, pdef)!;
    };
    for(let a .. acc){
        append(local_scp.vars, a)!;
    };
    ctxt.scp = &local_scp;
    const (body, _end) =
        if(!is_subtype(eval_tpe, primitive::UNIT)){
            yield eval_scope(ctxt, end, ele_tpe, tpe_msg::BOOL)?;
        } else {
            yield eval_scope(ctxt, end)?;
        };
    end = _end;

    const meta = for_meta {
        rets = ctxt.eval_t,
        tpe = eval_tpe,
        item = item.meta as *expr_meta,
        item_tpe = i_meta.tpe,
        element_tpe = ele_tpe,
        out_size = buff_size,
        pairs = pairs,
        acc = acc,
        out_acc = out_acc,
        body = body,
    };

    ctxt.scp = upper;
    const node = new_node();
    node.kind = path_t::STATEMENT;
    node.meta = alloc(meta)!;
    node.path = ctxt.tokens[begin..end];
    return (node, end);
};

fn eval_statement_decl(ctxt: *context, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    const namespace = ctxt.tokens[begin].val as ident;

    const (new_tpe, _end) = eval_type(ctxt, end + 1)?;
    end = _end;
    let tpe =
        if(new_tpe is lichen_t){
            yield new_tpe as lichen_t;
        } else {
            yield primitive::ANY: lichen_t;
        };

    let end = pop_assert(ctxt, end, operator::ASG,
        "expected %bassignment%r, but got %y{}")?;

    const old_eval = ctxt.eval_t;
    ctxt.eval_t = eval_kind::NONE;
    const (exp, _end) = eval_expression(ctxt, end, tpe)?;
    ctxt.eval_t = old_eval;

    const e_meta = exp.meta as *expr_meta;
    if(untyped(e_meta.tpe)){
        move_ptr(ctxt, ctxt.tokens[begin]);
        return error(ctxt, "cannot infer expression type");
    };
    end = _end;
    namespace.itype = tpe;

    const node = new_node();
    node.kind = path_t::STT_DECL;
    node.path = ctxt.tokens[begin..end];
    node.meta = alloc(var_meta {
        pos = ctxt.tokens[begin],
        ffi = void,
        mod = void,
        glob = false,
        rets = ctxt.eval_t,
        name = namespace,
    })!;
    node.inner = exp;
    return (node, end);
};

// evaluates a function call
fn eval_funcall(ctxt: *context, at: size) ((*ast, size) | COMPERR) = {
    const begin = at;
    let end = at;
    const fun_name = ctxt.tokens[begin].val as ident;
    const fun =
        match(get_fun(ctxt, fun_name)?){
        case let fun: *ast => yield fun;
        case void =>
            yield if(end + 1 < len(ctxt.tokens) &&
                comp_tk(ctxt.tokens[end + 1].val, symbol::FIELD)){
                const obj = next_tk(ctxt, end + 2,
                    "expected %bmodule field access%r, but got %y{}")?;
                if(!(obj.val is ident)){
                    move_ptr(ctxt, obj);
                    return error(ctxt, "expected %bvalid module field%r, but got %y{}%",
                        strtoken(obj.val));
                };
                end += 2;
                yield get_mod_fun(ctxt, ctxt.tokens[begin], obj.val as ident)?;
            } else {
                const help = undef_tip(fun_name.id);
                move_ptr(ctxt, ctxt.tokens[at]);
                return error(ctxt, "the function %y{}%r is undefined at this point{}",
                    fun_name.id, help);
            };
        };
    const f_meta = fun.meta as *fn_meta;
    move_ptr(ctxt, ctxt.tokens[begin]);
    validate_efx(ctxt, f_meta, (ctxt.scp as *scope).effects)?;

    f_meta.used = true;
    let tpe = f_meta.fn_type;
    const arg_l = (f_meta.params as *ast).meta as *param_meta;

    end = pop_assert(ctxt, end + 1, symbol::LFT_PAR,
        "expected %bfunction call argument list%r, but got %y{}")?;

    let tk = next_tk(ctxt, end,
        "expected %bfunction argument%r, but got %y{}")?;

    const node = new_node();
    node.kind = path_t::FUN_CALL;

    const old_eval = ctxt.eval_t;
    ctxt.eval_t = eval_kind::NONE;
    const list = []: []*ast;
    for(!comp_tk(tk.val, symbol::RGT_PAR)){
        if(len(list) + 1 > len(arg_l.names)){
            move_ptr(ctxt, tk);
            return error(ctxt, "too much arguments in the function call. "
                "the function %g{}%r takes %g{}%r arguments", f_meta.name.id,
                len(arg_l.names));
        };
        const (exp, _end) = eval_expression(ctxt, end, arg_l.names[len(list)].itype)?;
        end = _end;
        append(list, exp)!;

        tk = next_tk(ctxt, end,
            "expected %bcomma%r or %bclosing parenthesis%r, but got %y{}")?;
        if(comp_tk(tk.val, symbol::COMMA)){
            end += 1;
            tk = next_tk(ctxt, end,
                "expected %bfunction argument%r, but got %y{}")?;
        };
    };
    ctxt.eval_t = old_eval;

    if(len(list) < len(arg_l.names)){
        move_ptr(ctxt, tk);
        return error(ctxt, "missing the %b{} argument%r of the function",
            ordnum(len(list) + 1));
    };
    end += 1;
    tk = next_tk(ctxt, end,
        "expected %bexpression continuation%r or %bend or line%r, but got %y{}")?;
    
    let handle: (void | operator) = void;
    if(comp_tk(tk.val, operator::BANG) || comp_tk(tk.val, operator::PROP)){
        if(f_meta.fn_type is *aggregated){
            const agg = f_meta.fn_type as *aggregated;
            if(agg.error){
                const host = ctxt.scope_owner as *fn_meta;
                if(comp_tk(tk.val, operator::PROP) &&
                    !error_compatible(host.fn_type, agg)){
                    move_ptr(ctxt, tk);
                    return error(ctxt, "caller function of %b{}%r cannot handle propagation of %b{}",
                        strtype(host.fn_type), strtype(f_meta.fn_type));
                } else {
                    tpe =
                        if(len(agg.base) > 1){
                            yield new_union_t(ctxt, agg.base);
                        } else {
                            yield agg.base[0];
                        };
                };
                handle = tk.val as operator;
            } else {
                move_ptr(ctxt, tk);
                return error(ctxt, "%b{}%r is not an error type",
                    strtype(f_meta.fn_type));
            };
        } else {
            move_ptr(ctxt, tk);
            return error(ctxt, "cannot propagate error from {}",
                strtype(f_meta.fn_type));
        };
        end += 1;
    } else if(f_meta.fn_type is *aggregated && (f_meta.fn_type as *aggregated).error &&
        ctxt.eval_t != eval_kind::MOV){
        move_ptr(ctxt, tk);
        return error(ctxt, "cannot ignore error here");
    };

    node.path = ctxt.tokens[begin..end];
    node.meta = alloc(funcall_meta {
        tpe = tpe,
        prop = handle,
        dest = void,
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
            return strings::dup(f_meta.mod as str)!;
        } else {
            return strings::replace(f_meta.name.id, "'", ".q")!;
        };
    case let v_meta: *var_meta =>
        if(v_meta.ffi is str){
            return strings::dup(v_meta.ffi as str)!;
        } else if(v_meta.mod is str){
            return strings::dup(v_meta.mod as str)!;
        } else {
            return strings::replace(v_meta.name.id, "'", ".q")!;
        };
    };
};

fn unary_fix_type(ctxt: *context, pos: token, unary: (operator | void), tpe: lichen_t)
    (lichen_t | COMPERR) = {
    if(unary is operator && unary as operator == operator::LENGTH){
        if(!is_subtype(tpe, primitive::STR) &&
            !is_subtype(tpe, primitive::ARRAY)){
            move_ptr(ctxt, pos);
            return error(ctxt, "invalid unary operator for %y{}",
                strtype(tpe));
        };
        return primitive::U64;
    } else if(unary is operator){
        if((is_subtype(tpe, primitive::STR) ||
            is_subtype(tpe, primitive::ARRAY)) &&
            unary as operator != operator::LENGTH){
            move_ptr(ctxt, pos);
            return error(ctxt, "invalid unary operator for %y{}",
                strtype(tpe));
        };
    };
    return tpe;
};

fn eval_type(ctxt: *context, at: size) (((lichen_t | void), size) | COMPERR) = {
    const begin = at;
    let end = at;
    let tk = next_tk(ctxt, end,
        "expected %bvalid type notation%r, but got %y{}")?;
    if(comp_tk(tk.val, symbol::LFT_SQUARE)){
        end += 1;
        tk = next_tk(ctxt, end, "expected %bclosing square brackets%r, but got %y{}")?;

        if(!comp_tk(tk.val, symbol::RGT_SQUARE)){
            return (void, at);
        };
        end += 1;
        tk = next_tk(ctxt, end, "expected %barray item type%r, but got %y{}")?;
        if(tk.val is primitive){
            return (as_array(ctxt, tk.val as primitive), end + 1);
        };
    } else if(comp_tk(tk.val, operator::BANG)){
        const list = []: []lichen_t;
        const (base, _end) = eval_type(ctxt, end + 1)?;
        if(base is lichen_t){
            append(list, base as lichen_t)!;
            return (new_union_t(ctxt, list, true), _end);
        };
        free(list);
    } else if(tk.val is primitive){
        end += 1;
        const tpe = tk.val as primitive;
        tk = next_tk(ctxt, end,
            "expected %bdeclaration continuation%r or "
            "%bor end of type declaration%r, but got %y{}")?;
        if(comp_tk(tk.val, operator::BANG)){
            const list = []: []lichen_t;
            const (base, _end) = eval_type(ctxt, end + 1)?;
            if(base is lichen_t){
                append(list, base as lichen_t)!;
                return (new_union_t(ctxt, list, true, tpe), _end);
            };
            free(list);
        };
        return (tpe, end);
    } else if(tk.val is ident){
        assert(false, "TODO: composite types");
    };
    return (void, end);
};

fn comp_type(this: lichen_t, that: lichen_t) bool = {
    if(this is primitive && that is primitive){
        return this as primitive == that as primitive;
    } else if(this is *aggregated && that is *aggregated){
        return this as *aggregated == that as *aggregated;
    } else if(this is *ext_array && that is *ext_array){
        return this as *ext_array == that as *ext_array;
    } else {
        return false;
    };
};

// message modde for type error
type tpe_msg = enum u8 { FN_RT, LT_RT, ASSIG, BRANCH, BOOL, ARRAY };

// asserts if a incoming type is a subtype of the current type
fn assert_subtype(ctxt: *context, current: lichen_t, new: lichen_t, pos: token,
    msg_kind: tpe_msg = tpe_msg::LT_RT) (void | COMPERR) = {
    if(!is_subtype(new, current) && !comp_type(current, primitive::ANY)){
        move_ptr(ctxt, pos);
        switch(msg_kind){
        case tpe_msg::FN_RT =>
            return error(ctxt,
                "type mismatch between expected body type %y({})%r and evaluation type %y({})",
                strtype(current), strtype(new));
        case tpe_msg::LT_RT =>
            return error(ctxt,
                "type mismatch between lefthand side %y({})%r and righthand side %y({})",
                strtype(current), strtype(new));
        case tpe_msg::ASSIG =>
            return error(ctxt, "type mismatch between source %y({})%r and dest %y({})",
                strtype(new), strtype(current));
        case tpe_msg::BRANCH =>
            return error(ctxt,
                "type mismatch between previous branches type %y({})%r and current branch type %y({})",
                strtype(current), strtype(new));
        case tpe_msg::BOOL =>
            assert(false);
            return error(ctxt,
                "statement expected %b{}%r, but got %y{}", strtype(current), strtype(new));
        case tpe_msg::ARRAY =>
            return error(ctxt,
                "array of %b{}%r cannot hold item of %y{}", strtype(current), strtype(new));
        };
    };
};

fn push_type(ctxt: *context, current: lichen_t, new: lichen_t) lichen_t = {
    if(is_subtype(new, current)){
        if(untyped(current)) return new;
        if(new is primitive && current is *aggregated) return current;
        if(current is primitive && new is *aggregated) return new;
        return current;
    } else if(current is primitive){
        const list = []: []lichen_t;
        if(!untyped(current)) append(list, current)!;
        if(!untyped(new)){
            if(new is *aggregated &&
                (new as *aggregated).kind == keyword::UNION){
                const agg = new as *aggregated;
                append(list, agg.base...)!;
            } else {
                append(list, new)!;
            };
        };
        assert(len(list) > 0);
        return new_union_t(ctxt, list);
    } else if(current is *aggregated){
        const agg = current as *aggregated;
        if(agg.kind == keyword::UNION){
            if(new is *aggregated &&
                (new as *aggregated).kind == keyword::UNION){
                const aggp = new as *aggregated;
                append(agg.base, aggp.base...)!;
            } else {
                append(agg.base, new)!;
            };
            return current;
        } else {
            const list = []: []lichen_t;
            append(list, [current, new]...)!;
            return new_union_t(ctxt, list);
        };
    } else {
        const list = []: []lichen_t;
        append(list, [current, new]...)!;
        return new_union_t(ctxt, list);
    };
};

// attemps to cast a given current type to a new one, returning an error if it's
// an invalid cast. the error points to the given `pos` token.
fn cast(ctxt: *context, current: lichen_t, new: lichen_t, pos: token)
    (lichen_t | COMPERR) = {
    if(is_castable(current, new)){
        return new;
    } else {
        move_ptr(ctxt, pos);
        return error(ctxt, "invalid cast of %g{}%r to %g{}",
            strtype(current), strtype(new));
    };
};

fn as_array(ctxt: *context, tpe: lichen_t) lichen_t = {
    if(tpe is primitive){
        switch(tpe as primitive){
        case primitive::U8 =>
            return primitive::ARR_U8;
        case primitive::U16 =>
            return primitive::ARR_U16;
        case primitive::U32 =>
            return primitive::ARR_U32;
        case primitive::U64 =>
            return primitive::ARR_U64;
        case primitive::I8 =>
            return primitive::ARR_I8;
        case primitive::I16 =>
            return primitive::ARR_I16;
        case primitive::I32 =>
            return primitive::ARR_I32;
        case primitive::I64 =>
            return primitive::ARR_I64;
        case primitive::F32 =>
            return primitive::ARR_F32;
        case primitive::F64 =>
            return primitive::ARR_F64;
        case primitive::STR =>
            return primitive::ARR_STR;
        case primitive::CSTR =>
            return primitive::ARR_CSTR;
        case primitive::NUMBER =>
            return primitive::ARR_NUMBER;
        case primitive::RATIO =>
            return primitive::ARR_RATIO;
        case primitive::ANY =>
            return primitive::ARRAY;
        case =>
            //assert(false);
            fmt::fatal("as_array: unreachable");
        };
    } else {
        return new_array_t(ctxt, tpe);
    };
};

fn from_array(tpe: lichen_t) lichen_t = {
    if(tpe is primitive){
        const p = tpe as primitive;
        assert(p > primitive::ARRAY);
        return p - primitive::ARRAY - 1;
    } else {
        const a = tpe as *ext_array;
        return a.base;
    };
};

// checks is a given type is not a solid type
fn untyped(_tpe: lichen_t) bool = {
    if(_tpe is primitive){
        const tpe = _tpe as primitive;
        return tpe == primitive::ANY || tpe == primitive::NUMBER ||
            tpe == primitive::RATIO || tpe == primitive::ARRAY ||
            tpe == primitive::ARR_NUMBER || tpe == primitive::ARR_RATIO;
    } else {
        return false;
    };
};

// checks if a given type is castable in another
fn is_castable(_this: lichen_t, _that: lichen_t) bool = {
    if(_this is primitive && _that is primitive){
        const this = _this as primitive;
        const that = _that as primitive;
        switch(that){
        case primitive::U8, primitive::U16, primitive::U32, primitive::U64 =>
            return this == primitive::NUMBER || is_subtype(this, primitive::U64) ||
                is_subtype(this, primitive::I64);
        case primitive::I8, primitive::I16, primitive::I32, primitive::I64 =>
            return this == primitive::NUMBER || is_subtype(this, primitive::I64) ||
                is_subtype(this, primitive::U64);
        case primitive::F32, primitive::F64 =>
            return this == primitive::NUMBER || is_subtype(this, primitive::RATIO) ||
                (is_subtype(this, primitive::NUMBER) && type_size(this) == type_size(that));
        case primitive::STR =>
            return this == primitive::STR || this == primitive::CSTR;
        case primitive::CSTR =>
            return this == primitive::CSTR || this == primitive::STR;
        case primitive::UNIT, primitive::VOID =>
            return this == that;
        case =>
            assert(false, "unreachable");
            return false;
        };
    } else if(_this is *aggregated || _that is *aggregated){
        return is_subtype(_this, _that);
    } else {
        return comp_type(_this, _that);
    };
};

// checks if a given type is a subset of another
fn is_subtype(_this: lichen_t, _that: lichen_t) bool = {
    if(_this is primitive && _that is primitive){
        const this = _this as primitive;
        const that = _that as primitive;
        if(this == primitive::ANY || that == primitive::ANY) return true;
        switch(that){
        case primitive::U8, primitive::U16,
            primitive::U32, primitive::U64 =>
            return (this <= that && this >= primitive::U8) || this == primitive::NUMBER;
        case primitive::I8, primitive::I16,
            primitive::I32, primitive::I64 =>
            return (this <= that && this >= primitive::I8) || this == primitive::NUMBER;
        case primitive::F32, primitive::F64 =>
            return (this <= that && this >= primitive::F32) || this == primitive::RATIO;
        case primitive::STR =>
            return this == that || this == primitive::ARR_U8;
        case primitive::NUMBER =>
            return this == primitive::NUMBER || is_subtype(that, this);
        case primitive::RATIO =>
            return this == primitive::RATIO || this == primitive::NUMBER ||
                is_subtype(that, this);
        case primitive::VOID =>
            return this == primitive::UNIT || this == primitive::VOID;
        case primitive::ARRAY =>
            return this >= primitive::ARR_U8 || this == primitive::STR;
        case primitive::ARR_NUMBER =>
            return this > primitive::ARRAY &&
                is_subtype(from_array(this), primitive::NUMBER);
        case primitive::ARR_RATIO =>
            return this > primitive::ARRAY &&
                is_subtype(from_array(this), primitive::RATIO);
        case primitive::ARR_U8, primitive::ARR_U16, primitive::ARR_U32, primitive::ARR_U64,
            primitive::ARR_I8, primitive::ARR_I16, primitive::ARR_I32, primitive::ARR_I64,
            primitive::ARR_F32, primitive::ARR_F64, primitive::ARR_STR, primitive::ARR_CSTR =>
            return this == that || this == primitive::ARRAY ||
                (that == primitive::ARR_U8 && this == primitive::STR);
        case =>
            return this == that;
        };
    } else if(_this is *aggregated || _that is *aggregated){
        match(_this){
        case let this: *aggregated =>
            if(this.kind == keyword::UNION){
                if(_that is primitive){
                    for(let v .. this.base){
                        if(is_subtype(v, _that)) return true;
                    };
                } else if(_that is *aggregated){
                    const that = _that as *aggregated;
                    if(that.kind == keyword::UNION){
                        for(let ts_v .. this.base){
                            let found = false;
                            for(let tt_v .. that.base){
                                if(is_subtype(ts_v, tt_v)){
                                    found = true;
                                    break;
                                };
                            };
                            if(!found) return false;
                        };
                        return true;
                    };
                };
            } else if(this.kind == keyword::LET){
                return is_subtype(_that, this.base[0]);
            };
            return false;
        case let this: primitive =>
            const that = _that as *aggregated;
            if(that.kind == keyword::UNION){
                for(let v .. that.base){
                    if(is_subtype(this, v)) return true;
                };
            } else if(that.kind == keyword::LET){
                return is_subtype(this, that.base[0]);
            };
            return false;
        };
    } else {
        return comp_type(_this, _that);
    };
};

fn error_compatible(host: lichen_t, call: *aggregated) bool = {
    if(host is *aggregated){
        const host_t = host as *aggregated;
        if(host_t.error){
            if(host_t.error_val is lichen_t && call.error_val is lichen_t){
                return comp_type(host_t.error_val as lichen_t,
                    call.error_val as lichen_t);
            } else if(host_t.error_val is void && call.error_val is void){
                return true;
            };
        };
    };
    return false;
};

// returns the actual parsed size of a given string
fn true_size(lit: str) size = {
    const fixed = strings::multireplace(lit,
        ("\\t", "\t"), ("\\b", "\b"),
        ("\\a", "\a"), ("\\r", "\r"),
        ("\\n", "\n"), ("\\f", "\f"),
        ("\\0", "\0"), ("\\\"", "\""),
        ("\\'", "'"))!;
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
    } else if(name == "println"){
        return ". %gtry using the module %yio%g with "
            "%p\"%bio%d::%bprintln%d()%p\"";
    } else if(name == "scan"){
        return ". %gtry using the module %yio%g with "
            "%p\"%bio%d::%bscan%d()%p\"";
    } else if(name == "scanf"){
        return ". %gtry using the module %yio%g with "
            "%p\"%bio%d::%bscan%d()%p\"";
    } else {
        return "";
    };
};
