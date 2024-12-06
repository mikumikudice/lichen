use io;
use fmt;
use memio;
use strings;

// returns the default value for each primitive type
fn getdefval(vtp: prim) str = {
    switch(vtp){
    case prim::STRING =>
        return "$empty.str";
        //return "$empty.arr"; // TODO: arrays
    case =>
        return "0";
    };
};

// converts moss types to qbe types i.e. type length
fn get_qbe_t(vtp: prim, mode: int = 0) str = {
    if(mode == 1)
    if(vtp == prim::U8 || vtp == prim::I8 ||
        vtp == prim::U16 || vtp == prim::I16){
        return "w";
    };
    if(mode == 2)
    if(vtp == prim::U8 || vtp == prim::U16){
        return "uw";
    } else if(vtp == prim::I8 || vtp == prim::U16){
        return "sw";
    };
    switch(vtp){
    case prim::U8 =>
        return "b";
    case prim::I8 =>
        return "b";
    case prim::U16 =>
        return "h";
    case prim::I16 =>
        return "h";
    case prim::U32, prim::UNIT, prim::VOID =>
        if(mode == 2) return "uw";
        return "w";
    case prim::I32 =>
        if(mode == 2) return "sw";
        return "w";
    case prim::U64 =>
        if(mode == 2) return "ul";
        return "l";
    case prim::I64 =>
        if(mode == 2) return "sl";
        return "l";
    case prim::STRING, prim::NUMBER, prim::FUNCTION, prim::ANY =>
        return "l";
    case =>
        fmt::fatalf("get_qbe_t: unknown type {}", vtp: int);
    };
};

// returns size in bytes of a type
fn get_t_len(vtp: prim) int = {
    switch(vtp){
    case prim::U8, prim::I8 =>
        return 1;
    case prim::U16, prim::I16 =>
        return 2;
    case prim::U32, prim::I32 =>
        return 4;
    case prim::U64, prim::I64, prim::NUMBER,
        prim::STRING, prim::ANY =>
        return 8;
    case =>
        fmt::fatalf("gen_t_len: unexpected type {}", vtp: int);
    };
};

fn get_globval(val: expr_h, ctxt: *context) str = {
    let res = "";
    match(val){
    case let n: u64 =>
        res = fmt::asprintf("{}", n: u64);
    case let n: i64 =>
        res = fmt::asprintf("{}", n: i64);
    case let t: txt =>
        res = pushstr(t, ctxt);
    case =>
        assert(false);
    };
    return res;
};

fn kwd_to_tp(vtp: kwd) prim = {
    switch(vtp){
    case kwd::U8__TYPE => return prim::U8;
    case kwd::U16_TYPE => return prim::U16;
    case kwd::U32_TYPE => return prim::U32;
    case kwd::U64_TYPE => return prim::U64;
    case kwd::I8__TYPE => return prim::I8;
    case kwd::I16_TYPE => return prim::I16;
    case kwd::I32_TYPE => return prim::I32;
    case kwd::I64_TYPE => return prim::I64;
    case kwd::STRING_T => return prim::STRING;
    case kwd::UNITTYPE => return prim::UNIT;
    case kwd::VOIDTYPE => return prim::VOID;
    case =>
        fmt::fatalf("kwd_to_tp: invalid type {}", vtp: int);
    };
};

fn utos_tp(tp: prim) prim = {
    assert(is_num(tp));
    switch(tp){
    case prim::U8 =>
        return prim::I8;
    case prim::U16 =>
        return prim::I16;
    case prim::U32 =>
        return prim::I32;
    case prim::U64 =>
        return prim::I64;
    case =>
        fmt::fatal("utos_tp: unreachable");
    };
};

fn pushstr(lit: txt, ctxt: *context) str = {
    if(len(lit) == 0){
        return "$empty.str";
    };
    match(findl(ctxt.strlits, lit: []u8)){
    case let some: size =>
        return fmt::asprintf("$.{}", some);
    case =>
        const indx = len(ctxt.strlits);
        append(ctxt.strlits, tostr(lit));

        fmt::fprintf(&ctxt.datasec, "data $.{} = {{ l {}, b \"{}\" }}\n",
            indx, len(lit), rawstr(lit))!;
        return fmt::asprintf("$.{}", indx);
    };
};

fn gen_wrp(id: (*nmsp | *func), f: *file, ctxt: *context, skipsuf: bool = false) str = {
    let wrp = "";
    match(id){
    case let nm: *nmsp =>
        if(nm.origin != f.name || nm.global){
            wrp = fmt::asprintf("{}", get_globval(nm.value, ctxt));
        } else {
            if(!skipsuf){
                wrp = fmt::asprintf("%{}", nm.name);
            } else {
                wrp = nm.name;
            };
        };
    case let fun: *func =>
        if(fun.origin != f.name){
            if(!skipsuf){
                wrp = fmt::asprintf("${}.{}", ftomod(fun.origin), fun.name);
            } else {
                wrp = fmt::asprintf("{}.{}", ftomod(fun.origin), fun.name);
            };
        } else {
            if(!skipsuf){
                wrp = fmt::asprintf("${}", fun.name);
            } else {
                wrp = fun.name;
            };
        };
    };
    return wrp;
};

fn get_mod(mod: idt, ctxt: *context) (*module | void) = {
    for(let m ..& ctxt.uses){
        if(m.name == mod){
            return m;
        };
    };
};

fn get_idpos(id: (*nmsp | *func | *module)) str = {
    match(id){
    case let nm: *nmsp =>
        return fmt::asprintf("{}:{}:{}", ftomod(nm.origin), nm.pos.0, nm.pos.1);
    case let fun: *func =>
        return fmt::asprintf("{}:{}:{}", ftomod(fun.origin), fun.pos.0, fun.pos.1);
    case let mod: *module =>
        return fmt::asprintf("{}:{}:{}", ftomod(mod.origin), mod.pos.0, mod.pos.1);
    };
};

fn is_obj(tp: prim) bool = {
    return tp == prim::STRING;
};

fn get_nm(nm: idt, lst: (*scope | *module)) (*nmsp | *func | void) = {
    match(lst){
    case let scp: *scope =>
        for(let var .. scp.vars){
            if(var.name == nm) return var;
        };
        for(let fun .. scp.funs){
            if(fun.name == nm) return fun;
        };
        if(scp.over is *scope)
            return get_nm(nm, scp.over as *scope);
    case let mod: *module =>
        for(let var .. mod.vars){
            if(var.name == nm) return var;
        };
        for(let fun .. mod.funs){
            if(fun.name == nm) return fun;
        };
    };
};

fn push_var(nm: idt, f: *file, ctxt: *context, pub: bool = false)
    (*nmsp | COMP_ERR) = {
    match(get_mod(nm, ctxt)){
    case let mod: *module =>
        const tip = fmt::asprintf("required at {}:{}:{}",
            f.name, mod.pos.0, mod.pos.1);
        return errmsg(f, "this namespace is already in use by a module", tip);
    case void => void;
    };
    match(get_nm(nm, ctxt.scp)){
    case void =>
        const self = alloc(nmsp {
            pos = (f.lin + 1, f.cln + 1),
            name = nm,
            value = 0: u64,
            vtype = prim::UNIT,
            param = false,
            global = false,
            origin = f.name,
            public = pub,
        });
        append(ctxt.scp.vars, self);
        return self;
    case let var: *nmsp =>
        return errmsg(f, "invalid namespace re-assignment",
            fmt::asprintf("previously defined at {}:{}:{}",
            var.origin, var.pos.0, var.pos.1));

    case let fun: *func =>
        return errmsg(f, "invalid namespace re-assignment",
            fmt::asprintf("previously defined at {}:{}:{}",
            fun.origin, fun.pos.0, fun.pos.1));
    };
};

fn push_fun(nm: idt, f: *file, ctxt: *context, param: [](idt, prim), retrn: prim,
    efx: []str, pub: bool = false) (*func | COMP_ERR) = {
    match(get_nm(nm, ctxt.scp)){
    case void =>
        const self = alloc(func {
            pos = (f.lin + 1, f.cln + 1),
            name = nm,
            param = param,
            retrn = retrn,
            origin = f.name,
            public = pub,
            impure = len(efx) > 0,
            effect = efx,
        });
        append(ctxt.scp.funs, self);
        return self;
    case let var: *nmsp =>
        return errmsg(f, "invalid namespace re-assignment",
            fmt::asprintf("previously defined at {}:{}:{}",
            var.origin, var.pos.0, var.pos.1));

    case let fun: *func =>
        return errmsg(f, "invalid namespace re-assignment",
            fmt::asprintf("previously defined at {}:{}:{}",
            fun.origin, fun.pos.0, fun.pos.1));
    };
};

fn free_scp(scp: *scope) void = {
    for(let var .. scp.vars){
        free(var);
    };
    for(let fun .. scp.funs){
        free(fun);
    };
};

// recieves a filename and a context and compiles it into a IR
// buffer. returns an error if the file cannot be read or any
// compilation error occurs.
fn parse(fname: str, ctxt: *context) (memio::stream | COMP_ERR) = {
    let f = load(fname)?;
    const buff = memio::dynamic();
    const max = len(f.src);

    let delay = []: []fun_def;
    for(f.ptr < max){
        let next = nxttk(f)?;
        if(next is eol || next is eos) continue;

        // at this level, only global namespaces are parsed
        match(next){
        // private global assignment
        case let i: idt =>
            const idef = eval_globdef(f, ctxt, i)?;
            match(idef){
                case let d: memio::stream =>
                    fmt::fprintln(&buff, memio::string(&d)!)!;
                    io::close(&d)!;
                case let fd: fun_def =>
                    append(delay, fd);
                };
        case let k: kwd =>
            switch(k){
            case kwd::PUBFIELD =>
                next = nxttk(f)?;
                const nm = expct(next is idt, next, f, "invalid identifiver")?: idt;
                const idef = eval_globdef(f, ctxt, nm, true)?;
                match(idef){
                case let d: memio::stream =>
                    fmt::fprintfln(&buff, "export {}", memio::string(&d)!)!;
                    io::close(&d)!;
                case let fd: fun_def =>
                    append(delay, fd);
                };
            case kwd::USE__MOD =>
                next = nxttk(f)?;
                const mod = expct(next is idt, next, f, "expected module name")?: idt;
                if(ftomod(f.name) == mod: str){
                    const err = fmt::asprintf("the module {} is trying to import itself", f.name);
                    return errmsg(f, err);
                };
                match(get_mod(mod, ctxt)){
                case let dup_mod: *module =>
                    const msg = fmt::asprintf("the module {} was already required", mod);
                    const tip = fmt::asprintf("required at {}:{}:{}",
                        f.name, dup_mod.pos.0, dup_mod.pos.1);
                    return errmsg(f, msg, tip);
                case =>
                    if(mod == "rt"){
                        append(ctxt.uses, &rtmod);
                    } else {
                        let lmod = scope {
                            pos = (f.lin + 1, f.cln + 1),
                            over = void,
                            vars = [],
                            funs = [],
                        };
                        let modctxt = context {
                            scp = &lmod,
                            uses = [],
                            srcpath = ctxt.srcpath,
                            libpath = ctxt.libpath,
                            datasec = memio::dynamic(),
                            strlits = [],
                            fnname = void,
                            branch = false,
                            nomain = true,
                            assign = false,
                            effect = [],
                        };
                        const filename = fmt::asprintf("{}{}.ms", modctxt.libpath, mod: str);
                        build(filename, mod: str, &modctxt)?;
                        
                        const newmod = alloc(module {
                            pos = (f.lin + 1, f.cln + 1),
                            name = mod: str,
                            origin = filename,
                            vars = lmod.vars,
                            funs = lmod.funs,
                        });
                        append(ctxt.uses, newmod);
                    };
                    finsh(f, "expected end of module requirement")?;
                };
            case =>
                return errmsg(f, "invalid statement");
            };
        case =>
            return errmsg(f, "expected type or namespace definition or module requirement");
        };
    };
    for(let fd .. delay){
        const fun = eval_fundef(&fd.f, ctxt, fd.nm,
            memio::dynamic(), fd.pub, false)? as memio::stream;
        defer io::close(&fun)!;
        if(fd.pub){
            fmt::fprintfln(&buff, "export {}", memio::string(&fun)!)!;
        } else {
            fmt::fprintfln(&buff, "{}", memio::string(&fun)!)!;
        };
    };
    return buff;
};

fn eval_globdef(f: *file, ctxt: *context, nm: idt, pub: bool = false)
    (memio::stream | fun_def | COMP_ERR) = {
    const buff = memio::dynamic();
    let next = nxttk(f)?;
    const oper = expct(next is opr, next, f, "type or namespace definition")?: opr;
    switch(oper){
    case opr::ASSIGNMT =>
        if(ahead(f, kwd::FUNCTION) is kwd){
            const fd = fun_def {
                f = *f,
                nm = nm,
                pub = pub,
            };
            eval_fundef(f, ctxt, nm, buff, pub)?;
            return fd;
        } else {
            // TODO: comptime expressions
            void;
        };
    case => assert(false, "unreachable");
    };
    return buff;
};

fn eval_fundef(f: *file, ctxt: *context, nm: idt, buff: memio::stream, pub: bool,
    skip: bool = true) (memio::stream | void | COMP_ERR) = {
    let next = nxttk(f)?;
    assert(cmp_tok(next, kwd::FUNCTION));

    next = nxttk(f)?;
    expct(cmp_tok(next, sym::OPEN_PAR), next, f,
        "function's parameter list definition")?;
    
    next = nxttk(f)?;
    let params = []: [](idt, prim);
    for(!is_limit(next, [sym::CLOSEPAR])){
        const prm = expct(next is idt, next, f,
            "invalid parameter name")?: idt;
        // TODO: add `foo, bar type` syntax
        next = nxttk(f)?;
        const ptp = expct(is_type(next), next, f,
            "invalid parameter type")?: kwd;
        const tp = kwd_to_tp(ptp);
        append(params, (prm, tp));

        next = nxttk(f)?;
        if(cmp_tok(next, sym::SYMCOMMA)){
            next = nxttk(f)?;
            continue;
        };
        expct(cmp_tok(next, sym::CLOSEPAR), next, f,
            "end of function's parameter list")?;
    };
    if(nm == "main"){
        expct(len(params) == 0, eol, f,
            "the main function must take no arguments")?;
    };
    next = nxttk(f)?;
    const tp = expct(is_type(next), next, f,
        "function type definition")?: kwd;
    const f_tp = kwd_to_tp(tp);

    if(ctxt.nomain){
        expct(nm != "main", eol, f,
            "modules cannot have a main function")?;
    } else if(nm == "main"){
        expct(f_tp == prim::VOID, eol, f,
            "the main function must be of void type")?;
    };
    let efx = []: []str;
    for(ahead(f, opr::LOGICAND) is opr){
        nxttk(f)!;
        next = nxttk(f)?;
        const e = expct(next is idt, next, f,
            "expected valid effect tag")?: idt;
        append(efx, e: str);
    };
    const self =
        if(!skip){
            yield get_nm(nm, ctxt.scp): *func;
        } else {
            push_fun(nm, f, ctxt, params, f_tp, efx, pub)?;
            next = nxttk(f)?;
            expct(cmp_tok(next, sym::OPN_CRLY), next, f,
            "expected scope declaration")?;
            mtchs(sym::OPN_CRLY, f, false)?;
            return;
        };
    let over = ctxt.scp;
    let fun_scp = scope {
        pos = (f.lin, f.cln),
        over = over,
        vars = [],
        funs = [],
    };
    for(let prm .. params){
        let dp = alloc(nmsp {
            pos = self.pos,
            name = prm.0,
            value = 0: num,
            vtype = prm.1,
            param = true,
            global = false,
            origin = f.name,
            public = false,
        });
        append(fun_scp.vars, dp);
    };
    defer free_scp(&fun_scp);
    ctxt.scp = &fun_scp;
    defer ctxt.scp = over;

    ctxt.effect = efx;
    defer ctxt.effect = [];

    ctxt.fnname = nm;
    defer ctxt.fnname = void;

    const (body, _, has_ret) = eval_body(f, ctxt, f_tp)?;
    defer io::close(&body)!;

    if(!has_ret){
        expct(f_tp == prim::UNIT || f_tp == prim::VOID, eol,
            f, "function evaluates invalid return type",
            cast_err(prim::UNIT, f_tp))?;
    };
    const prms = gen_params(params);
    defer io::close(&prms)!;

    const fname =
        if(ctxt.nomain){
            const mod = ftomod(f.name);
            yield fmt::asprintf("{}.{}", mod, nm);
        } else {
            yield nm: str;
        };
    if(f_tp == prim::VOID){
        fmt::fprintf(&buff, "function ${}({}){{\n@start\n{}\tcall $rt.exit(w 0)\n\thlt\n}}",
            fname, memio::string(&prms)!, memio::string(&body)!)!;
    } else if(f_tp == prim::UNIT){
        fmt::fprintf(&buff, "function ${}({}){{\n@start\n{}\tret\n}}",
            fname, memio::string(&prms)!, memio::string(&body)!)!;
    } else {
        fmt::fprintf(&buff, "function {} ${}({}){{\n@start\n{}}}", get_qbe_t(f_tp, 1),
            fname, memio::string(&prms)!, memio::string(&body)!)!;
    };
    return buff;
};

fn eval_body(f: *file, ctxt: *context, ret_tp: prim, dest: (str | void) = void)
    ((memio::stream, prim, bool) | COMP_ERR) = {
    const buff = memio::dynamic();
    let next = nxttk(f)?;
    expct(cmp_tok(next, sym::OPN_CRLY), next, f,
        "expected scope declaration")?;
    const close = mtchs(sym::OPN_CRLY, f)?;

    let is_ret = false;
    if(ret_tp == prim::VOID) ret_tp = prim::UNIT;
    for(f.ptr < close){
        next = nxttk(f)?;
        if(next is eol || next is eos) continue;

        match(next){
        case let n: num =>
            const exp = eval_exp(f, ctxt, n, memio::dynamic())?;
            defer io::close(&exp)!;

            is_ret = exp.is_ret;
            if(exp.is_ret && !is_untyped(ret_tp)){
                expct(is_subt(exp.expr_t, ret_tp), exp.finish, f,
                    "mismatch between function and return value types",
                    cast_err(exp.expr_t, ret_tp))?;
                expct(cmp_tok(exp.finish, sym::CLS_CRLY), exp.finish, f,
                    "void statements cannot be followed by more code")?;
            } else if(exp.is_ret){
                ret_tp = exp.expr_t;
            };
            if(exp.single){
                if(exp.is_ret && exp.expr_t != prim::UNIT){
                    if(ctxt.branch){
                        fmt::fprintfln(&buff, "\t%{} ={} copy {}", dest,
                            get_qbe_t(exp.expr_t, 1), memio::string(&exp)!)!;
                    } else {
                        fmt::fprintfln(&buff, "\tret {}", memio::string(&exp)!)!;
                    };
                } else if(exp.expr_t != prim::UNIT){
                    return errmsg(f, "meaningless statement", "to return a value, remove the semicolon");
                };
            } else {
                if(!exp.is_ret || exp.expr_t == prim::UNIT){
                    fmt::fprintln(&buff, memio::string(&exp)!)!;
                } else {
                    fmt::fprintfln(&buff, "{}\n\tret {}",
                        memio::string(&exp)!, exp.exp_id)!;
                };
            };
        case let t: txt =>
            const exp = eval_exp(f, ctxt, t, memio::dynamic())?;
            defer io::close(&exp)!;

            is_ret = exp.is_ret;
            if(exp.is_ret && !is_untyped(ret_tp)){
                expct(is_subt(exp.expr_t, ret_tp), exp.finish, f,
                    "mismatch between function and return value types",
                    cast_err(exp.expr_t, ret_tp))?;
                expct(cmp_tok(exp.finish, sym::CLS_CRLY), exp.finish, f,
                    "void statements cannot be followed by more code")?;
            } else if(exp.is_ret){
                ret_tp = exp.expr_t;
            };
            if(exp.single){
                if(exp.is_ret && exp.expr_t != prim::UNIT){
                    if(ctxt.branch){
                        fmt::fprintfln(&buff, "\t%{} ={} copy {}", dest,
                            get_qbe_t(exp.expr_t, 1), memio::string(&exp)!)!;
                    } else {
                        fmt::fprintfln(&buff, "\tret {}", memio::string(&exp)!)!;
                    };
                } else if(exp.expr_t != prim::UNIT){
                    return errmsg(f, "meaningless statement", "to return a value, remove the semicolon");
                };
            } else {
                if(!exp.is_ret || exp.expr_t == prim::UNIT){
                    fmt::fprintln(&buff, memio::string(&exp)!)!;
                } else {
                    fmt::fprintfln(&buff, "{}\n\tret %{}.v",
                        memio::string(&exp)!, get_qbe_t(exp.expr_t, 1))!;
                };
            };
        case let i: idt =>
            const exp = eval_exp(f, ctxt, i, memio::dynamic())?;
            defer io::close(&exp)!;

            is_ret = exp.is_ret;
            if(exp.is_ret && !is_untyped(ret_tp)){
                expct(is_subt(exp.expr_t, ret_tp), exp.finish, f,
                    "mismatch between function and return value types",
                    cast_err(exp.expr_t, ret_tp))?;
                expct(cmp_tok(exp.finish, sym::CLS_CRLY), exp.finish, f,
                    "void statements cannot be followed by more code")?;
            } else {
                if(exp.expr_t == prim::VOID){
                    next = nxttk(f)?;
                    expct(cmp_tok(next, sym::CLS_CRLY), next, f,
                        "void statements cannot be followed by more code")?;
                };
                if(exp.is_ret && is_untyped(ret_tp)){
                    ret_tp = exp.expr_t;
                };
            };
            if(exp.single){
                if(exp.is_ret && exp.expr_t != prim::UNIT){
                    if(ctxt.branch){
                        if(need_extnd(exp.expr_t, ret_tp)){
                            fmt::fprintfln(&buff, "\t%{} =l ext{} {}", dest,
                                get_qbe_t(exp.expr_t, 2), memio::string(&exp)!)!;
                        } else {
                            fmt::fprintfln(&buff, "\t%{} ={} copy {}", dest,
                                get_qbe_t(exp.expr_t, 1), memio::string(&exp)!)!;
                        };
                    } else {
                        fmt::fprintfln(&buff, "\tret {}", memio::string(&exp)!)!;
                    };
                } else {
                    fmt::fprintln(&buff, memio::string(&exp)!)!;
                };
            } else {
                if(!exp.is_ret && exp.fncall is void){
                    fmt::fprintln(&buff, memio::string(&exp)!)!;
                } else if(!exp.is_ret){
                    fmt::fprintln(&buff, memio::string(&exp)!)!;
                } else {
                    if(ctxt.branch){
                        fmt::fprintfln(&buff, "\t%{} ={} copy %{}.v", dest,
                            get_qbe_t(exp.expr_t, 1), exp.exp_id)!;
                    } else if(exp.expr_t != prim::UNIT){
                        fmt::fprintfln(&buff, "{}\n\tret %{}.v",
                            memio::string(&exp)!, exp.exp_id)!;
                    } else {
                        fmt::fprintln(&buff, memio::string(&exp)!)!;
                    };
                };
            };
        case let k: kwd =>
            const exp = eval_statement(k, f, ctxt, ret_tp)?;
            is_ret = exp.is_ret;
            if(exp.is_ret){
                expct(cmp_tok(exp.finish, sym::CLS_CRLY), exp.finish, f,
                    "void statements cannot be followed by more code")?;
                if(ctxt.branch){
                    fmt::fprint(&buff, memio::string(&exp)!)!;
                } else {
                    fmt::fprintf(&buff, "{}\tret %{}\n",
                        memio::string(&exp)!, exp.exp_id)!;
                };
            } else {
                if(exp.expr_t == prim::VOID){
                    next = nxttk(f)?;
                    expct(cmp_tok(next, sym::CLS_CRLY), next, f,
                        "void statements cannot be followed by more code")?;
                };
                fmt::fprintf(&buff, "\t{}\n", memio::string(&exp)!)!;
            };
        case let s: sym =>
            switch(s){
            case sym::CLS_CRLY => assert(f.ptr == close);
            case =>
                return errmsg(f, "expected valid expression");
            };
        case =>
            return errmsg(f, "expected valid expression");
        };
    };
    return (buff, ret_tp, is_ret);
};

fn eval_exp(f: *file, ctxt: *context, tk: tok, buff: memio::stream, limit: []tok = [eos],
    l: size = 0, c: size = 0) (synthexp | COMP_ERR) = {
    // TODO: handle unary operators at the beginning
    const (hand, hand_t) = solve_hand(tk, f, ctxt)?;
    const (ndef, expr_t) =
        match(hand_t){
        case void => yield (true, prim::UNIT);
        case let tp: prim => yield (false, tp);
        };
    let expr = express {
        args = [],
        oprs = [],
        expr_t = expr_t,
    };
    append(expr.args, hand);

    const vid = fmt::asprintf(".{}.{}.v", f.lin + 1, f.cln + 1);
    let out = synthexp {
        buffer = buff,
        expr_t = expr_t,
        is_ret = false,
        single = false,
        fncall = void,
        finish = eol,
        exp_id = vid,
    };
    let next = nxttk(f)?;
    for(!is_limit(next, limit)){
        match(next){
        case let o: opr =>
            next = nxttk(f)?;
            if(ndef){
                expct(o == opr::ASSIGNMT, o, f,
                    "expected variable assignment")?;

                ctxt.assign = true;
                const var = hand: *nmsp;
                const val = eval_exp(f, ctxt, next, memio::dynamic())?;
                defer io::close(&val)!;

                expct(val.expr_t != prim::VOID, eol, f,
                    "void expressions are not assignable")?;

                var.vtype = val.expr_t;
                out.expr_t = val.expr_t;
                ctxt.assign = false;

                if(val.single && val.fncall is void){
                    fmt::fprintf(&out, "\t%{} ={} copy {}", var.name,
                        get_qbe_t(val.expr_t, 1), memio::string(&val)!)!;
                } else {
                    fmt::fprintf(&out, "{}\t%{} ={} copy %{}",
                        memio::string(&val)!, var.name,
                        get_qbe_t(val.expr_t, 1), val.exp_id)!;
                };
                return out;
            } else {
                expct(o != opr::ASSIGNMT, o, f,
                    "cannot reassign values to namespaces")?;

                append(expr.oprs, o);
                let (h, t) = solve_hand(next, f, ctxt)?;

                expct(t is prim, o, f, "invalid usage of undefined variable")?;
                const tp =
                    if(!is_untyped(t: prim)){
                        yield t as prim;
                    } else {
                        yield out.expr_t;
                    };
                expct(operable(out.expr_t, tp, o), o, f, "mismatch between member types",
                    cast_err(out.expr_t, tp, true))?;

                out.expr_t = tp;
                append(expr.args, h);
            };
        case =>
            out.is_ret = true;
            puttk(f);
            break;
        };
        next = nxttk(f)?;
    };
    out.finish = next;
    out.single = len(expr.args) == 1;
    if(out.single){
        expct(!ndef, eol, f, "invalid usage of undefined variable")?;
        match(expr.args[0]){
        case let var: *nmsp =>
            const wrp = gen_wrp(var, f, ctxt);
            fmt::fprint(&out.buffer, wrp)!;

        case let fun: *func =>
            const wrp = gen_wrp(fun, f, ctxt);
            fmt::fprint(&out.buffer, wrp)!;

        case let n: u64 =>
            fmt::fprint(&out.buffer, n: u64)!;

        case let n: i64 =>
            fmt::fprint(&out.buffer, n: i64)!;

        case let t: txt =>
            const id = pushstr(t, ctxt);
            fmt::fprint(&out.buffer, id)!;

        case let call: funcall =>
            const wrp = gen_wrp(call.fun, f, ctxt, true);
            out.exp_id = wrp;
            out.fncall = call;
            const (chdr, fname) = gen_fcall(call, ctxt, f);
            if(!out.is_ret){
                out.single = false;
                fmt::fprintf(&out, "\t{}\n", memio::string(&chdr)!)!;
            } else {
                out.single = false;
                fmt::fprintf(&out, "\t{}\n\t%{}.v ={} copy {}", memio::string(&chdr)!,
                    wrp, get_qbe_t(call.fun.retrn, 1), fname)!;
            };
        case let sub: synthexp =>
            if(sub.single){
                fmt::fprint(&out, memio::string(&sub)!)!;
                io::close(&sub)!;
            } else {
                out.single = false;
                fmt::fprint(&out, memio::string(&sub)!)!;
                io::close(&sub)!;
                out.exp_id = sub.exp_id;
            };
        };
    } else {
        const max = len(expr.oprs);
        const tpz = get_qbe_t(out.expr_t, 1);
        let hidx = 1z;
        let lfth =
                match(expr.args[0]){
                case let var: *nmsp =>
                    yield fmt::asprintf("%{}", var.name);

                case let n: u64 =>
                    yield fmt::asprintf("{}", n: u64);

                case let n: i64 =>
                    yield fmt::asprintf("{}", n: i64);

                case let call: funcall =>
                    const wrp = fmt::asprintf("%{}.v", get_qbe_t(call.fun.retrn, 1));
                    const (chdr, fname) = gen_fcall(call, ctxt, f);
                    defer io::close(&chdr)!;
                    fmt::fprintf(&out, "\t{}\n\t%{}.v ={} {}\n", memio::string(&chdr)!,
                        wrp, get_qbe_t(call.fun.retrn, 1), fname)!;
                    yield wrp;
                case let sub: synthexp =>
                    yield
                    if(sub.single){
                        defer io::close(&sub)!;
                        yield strings::dup(memio::string(&sub)!);
                    } else {
                        fmt::fprint(&out.buffer, memio::string(&sub)!)!;
                        io::close(&sub)!;
                        yield fmt::asprintf("%{}", sub.exp_id);
                    };
                case =>
                    assert(false);
                    yield "";
                };
        for(let o = 0z; o < max; o += 1){
            let hdr = "";
            const rgth =
                match(expr.args[hidx]){
                case let var: *nmsp =>
                    yield fmt::asprintf("%{}", var.name);

                case let n: u64 =>
                    yield fmt::asprintf("{}", n: u64);

                case let n: i64 =>
                    yield fmt::asprintf("{}", n: i64);

                case let call: funcall =>
                    const wrp = fmt::asprintf("%{}.v", get_qbe_t(call.fun.retrn));
                    const (chdr, fname) = gen_fcall(call, ctxt, f);
                    defer io::close(&chdr)!;
                    hdr = fmt::asprintf("{}\t{}\n\t%{}.v ={} {}\n", hdr, memio::string(&chdr)!,
                        wrp, get_qbe_t(call.fun.retrn, 1), fname);
                    yield wrp;
                case let sub: synthexp =>
                    yield
                    if(sub.single){
                        defer io::close(&sub)!;
                        yield strings::dup(memio::string(&sub)!);
                    } else {
                        hdr = fmt::asprintf("{}{}", hdr, memio::string(&sub)!);
                        io::close(&sub)!;
                        yield fmt::asprintf("%{}", sub.exp_id);
                    };
                case =>
                    assert(false);
                    yield "";
                };
            if(hidx > 1) lfth = fmt::asprintf("%{}", vid);
            hidx += 1;
            if(expr.oprs[o] == opr::ARTH_DIV){
                if(is_num(out.expr_t)){
                    fmt::fprintf(&out.buffer, "{}\t%{} ={} udiv {}, {}\n",
                        hdr, vid, tpz, lfth, rgth)!;
                } else if(is_num(out.expr_t, true)){
                    hdr = fmt::asprintf("{0}\t%{1}.r ={2} rem {3}, {4}\n\t%{1} ={2} sub {3}, %{1}.r",
                        hdr, vid, tpz, lfth, rgth);
                    fmt::fprintf(&out.buffer, "{0}\tjnz {4}, @ok{1}, @zr{1}\n@ok{1}"
                        "\n\t%{1} ={2} div {3}, {4}\n\tjmp @end{1}\n@zr{1}\n\t%{1} ={2} copy 0"
                        "\n@end{1}\n",
                        hdr, vid, tpz, lfth, rgth)!;
                };
            } else if(expr.oprs[o] == opr::ARTH_REM && is_num(out.expr_t)){
                fmt::fprintf(&out, "{}\t%{} ={} urem {}, {}\n",
                    hdr, vid, tpz, lfth, rgth)!;

            } else if(!is_cmp(expr.oprs[o])){
                fmt::fprintf(&out, "{}\t%{} ={} {} {}, {}\n",
                    hdr, vid, tpz, inst[expr.oprs[o]], lfth, rgth)!;
            } else if(is_cmp(expr.oprs[o], true)){
                if(is_num(out.expr_t)){
                    fmt::fprintf(&out, "{}\t%{} ={} cu{}{} {}, {}\n", hdr, vid, tpz,
                        inst[expr.oprs[o]], get_qbe_t(out.expr_t, 1), lfth, rgth)!;
                } else {
                    fmt::fprintf(&out, "{}\t%{} ={} cs{}{} {}, {}\n", hdr, vid, tpz,
                        inst[expr.oprs[o]], get_qbe_t(out.expr_t, 1), lfth, rgth)!;
                };
            } else if(out.expr_t != prim::UNIT){
                fmt::fprintf(&out, "{}\t%{} ={} {}{} {}, {}\n", hdr, vid, tpz,
                    inst[expr.oprs[o]], get_qbe_t(out.expr_t, 1), lfth, rgth)!;
            } else {
                fmt::fprintf(&out, "{}\t%{} ={} copy 1\n", hdr, vid, tpz)!;
            };
        };
    };
    if(is_limit(out.finish, [kwd::AND_OPER, kwd::OR__OPER])){
        if(l == 0 && c == 0){
            nxttk(f)!;
            const (lin, cln) = (f.lin + 1, f.cln + 1);
            let eval = eval_boolexp(f, ctxt, lin, cln,
                memio::dynamic(), out)?;
            fmt::fprintf(&eval, "@t.{0}.{1}\n\tjmp @phi.{0}.{1}\n@f.{0}.{1}\n\tjmp @phi.{0}.{1}\n"
                "@phi.{0}.{1}\n\t%{2} ={3} phi @t.{0}.{1} 1, @f.{0}.{1} 0\n", lin, cln, eval.exp_id,
                get_qbe_t(eval.expr_t, 1))!;
            return eval;
        } else {
            return eval_boolexp(f, ctxt, l, c,
                memio::dynamic(), out)?;
        };
    };
    return out;
};

fn solve_hand(hand: tok, f: *file, ctxt: *context)
    ((expr_h, (prim | void)) | COMP_ERR) = {
    if(cmp_tok(hand, sym::OPEN_PAR)){
        const sub = eval_exp(f, ctxt, nxttk(f)?,
            memio::dynamic(), [sym::CLOSEPAR])?;
         const cast = parse_cast(f, sub.expr_t)?;
        if(!need_extnd(sub.expr_t, cast) || sub.single){
            return (sub, cast);
        } else {
            const wrp = synthexp {
                buffer = memio::dynamic(),
                expr_t = cast,
                is_ret = false,
                single = false,
                fncall = void,
                finish = eol,
                exp_id = fmt::asprintf("{}.{}",
                    sub.exp_id, get_qbe_t(cast, 1)),
            };
            fmt::fprintf(&wrp.buffer, "\t%{} =l ext{} %{}\n", wrp.exp_id,
                get_qbe_t(sub.expr_t, 2), sub.exp_id)!;
            return (wrp, cast);
        };
    };
    if(hand is kwd){
        if(cmp_tok(hand, kwd::NOT_OPER)){
            puttk(f);
            const sub = eval_boolexp(f, ctxt,
                f.lin + 1, f.cln + 1, memio::dynamic())?;
            return (sub, sub.expr_t);
        };
        const sub = eval_statement(hand: kwd, f, ctxt, prim::ANY)?;
        return (sub, sub.expr_t);
    };
    const pos : (opr | void) =
        if(hand is opr && is_unry(hand: opr)){
            const op = hand: opr;
            hand = nxttk(f)?;
            yield op;
        };
    const fllw = ahead(f,  [opr::MODFIELD, opr::OBJFIELD])?;
    if(fllw is opr){
        if(cmp_tok(fllw: opr, opr::MODFIELD)){
            nxttk(f)!;
            const modname =
                expct(hand is idt, hand, f, "expected valid module name")?: idt;
            match(get_mod(modname, ctxt)){
            case void =>
                const msg = fmt::asprintf("the module {} is not included at this point",
                    modname);
                const tip = fmt::asprintf("try doing: {}",
                    fmt::asprintf("{}use {};{}", CMD[cmd::YEL],
                    modname, CMD[cmd::DEF]));
                return errmsg(f, msg, tip);

            case let mod: *module =>
                let next = nxttk(f)?;
                const nm = expct(next is idt, next, f,
                    "invalid valid module field")?: idt;
                match(get_nm(nm, mod)){
                case let var: *nmsp =>
                    const cast = parse_cast(f, var.vtype)?;
                    if(!need_extnd(var.vtype, cast)){
                        if(pos is void){
                            return (var, cast);
                        } else {
                            expct(is_subt(cast, prim::NUMBER) || is_subt(cast, prim::RATIO),
                                eol, f, "invalid type for unary operator",
                                fmt::asprintf("{} is a {} instance", var.name, primv[var.vtype]))?;
                            const wrp = synthexp {
                                buffer = memio::dynamic(),
                                expr_t = cast,
                                is_ret = false,
                                single = false,
                                fncall = void,
                                finish = eol,
                                exp_id = var.name,
                            };
                            if(pos is opr){
                                switch(pos as opr){
                                case opr::ARTH_PLS => void;
                                case opr::ARTH_MIN =>
                                    expct(is_num(cast), eol, f, "invalid type for unary minus operator")?;
                                    fmt::fprintf(&wrp.buffer, "\t%{0} ={1} sub 0, %{0}\n", wrp.exp_id,
                                    get_qbe_t(cast, 1))!;
                                case opr::LOGICNOT =>
                                    fmt::fprintf(&wrp.buffer, "\t%{0} ={1} not %{0}\n", wrp.exp_id,
                                        get_qbe_t(cast, 1))!;
                                case => assert(false);
                                };
                            };
                            return (wrp, cast);
                        };
                    } else {
                        const wrp = synthexp {
                            buffer = memio::dynamic(),
                            expr_t = cast,
                            is_ret = false,
                            single = false,
                            fncall = void,
                            finish = eol,
                            exp_id = fmt::asprintf("{}.{}",
                                var.name, get_qbe_t(cast, 1)),
                        };
                        fmt::fprintf(&wrp.buffer, "\t%{} =l ext{} %{}\n", wrp.exp_id,
                            get_qbe_t(var.vtype, 2), var.name)!;
                        if(pos is opr){
                            switch(pos as opr){
                            case opr::ARTH_PLS => void;
                            case opr::ARTH_MIN =>
                                expct(is_num(cast), eol, f, "invalid type for unary minus operator")?;
                                fmt::fprintf(&wrp.buffer, "\t%{0} =l sub 0, %{0}\n", wrp.exp_id)!;
                            case opr::LOGICNOT =>
                                fmt::fprintf(&wrp.buffer, "\t%{0} =l not %{0}\n", wrp.exp_id)!;
                            case => assert(false);
                            };
                        };
                        return (wrp, cast);
                    };
                case let fun: *func =>
                    if(ahead(f, sym::OPEN_PAR) is sym){
                        const call = eval_fcall(fun, f, ctxt)?;
                        const cast = parse_cast(f, call.fun.retrn)?;
                        if(!need_extnd(call.fun.retrn, cast)){
                            if(pos is void){
                                return (call, cast);
                            } else {
                                const ftp = call.fun.retrn;
                                const fnm = call.fun.name;
                                expct(is_subt(cast, prim::NUMBER) || is_subt(cast, prim::RATIO),
                                    eol, f, "invalid type for unary operator",
                                    fmt::asprintf("{} is a {} instance", fnm, primv[ftp]))?;
                                const wrp = synthexp {
                                    buffer = memio::dynamic(),
                                    expr_t = cast,
                                    is_ret = false,
                                    single = false,
                                    fncall = void,
                                    finish = eol,
                                    exp_id = fmt::asprintf("{}.{}",
                                        fnm, get_qbe_t(cast, 1)),
                                };
                                const (chdr, fname) = gen_fcall(call, ctxt, f);
                                defer io::close(&chdr)!;
                                const tpz = get_qbe_t(cast, 1);

                                fmt::fprintf(&wrp, "\t{}\n\t%{} ={} %{}\n",
                                    memio::string(&chdr)!, wrp.exp_id, tpz, fname)!;
                                if(pos is opr){
                                    switch(pos as opr){
                                    case opr::ARTH_PLS => void;
                                    case opr::ARTH_MIN =>
                                        expct(is_num(cast), eol, f, "invalid type for unary minus operator")?;
                                        fmt::fprintf(&wrp.buffer, "\t%{0} ={1} sub 0, %{0}\n", wrp.exp_id, tpz)!;
                                    case opr::LOGICNOT =>
                                        fmt::fprintf(&wrp.buffer, "\t%{0} ={1} not %{0}\n", wrp.exp_id, tpz)!;
                                    case => assert(false);
                                    };
                                };
                                return (wrp, cast);
                            };
                        } else {
                            const wrp = synthexp {
                                buffer = memio::dynamic(),
                                expr_t = cast,
                                is_ret = false,
                                single = false,
                                fncall = void,
                                finish = eol,
                                exp_id = fmt::asprintf("{}.{}",
                                    call.fun.name, get_qbe_t(cast, 1)),
                            };
                            fmt::fprintf(&wrp.buffer, "\t%{} =l ext{} %{}\n", wrp.exp_id,
                                get_qbe_t(call.fun.retrn, 2), call.fun.name)!;
                            if(pos is opr){
                                switch(pos as opr){
                                case opr::ARTH_PLS => void;
                                case opr::ARTH_MIN =>
                                    expct(is_num(cast), eol, f, "invalid type for unary minus operator")?;
                                    fmt::fprintf(&wrp.buffer, "\t%{0} ={1} sub 0, %{0}\n", wrp.exp_id,
                                    get_qbe_t(cast, 1))!;
                                case opr::LOGICNOT =>
                                    fmt::fprintf(&wrp.buffer, "\t%{0} ={1} not %{0}\n", wrp.exp_id,
                                        get_qbe_t(cast, 1))!;
                                case => assert(false);
                                };
                            };
                            return (wrp, cast);
                        };
                    };
                    return (fun, prim::FUNCTION);
                case void =>
                    return errmsg(f, "this module doesn't have this field");
                };
            };
        } else if(cmp_tok(fllw: opr, opr::OBJFIELD)){
            void;
        };
    };
    return match(hand){
    case let n: num =>
        const tp = parse_cast(f, prim::NUMBER)?;
        if(pos is opr){
            switch(pos: opr){
            case opr::ARTH_PLS =>
                return (n, tp);
            case opr::ARTH_MIN =>
                return (-(n : i64), tp);
            case opr::LOGICNOT =>
                return (~n, tp);
            case => assert(false);
            };
        };
        return (n, tp);
    case let t: txt =>
        const tp = parse_cast(f, prim::STRING)?;
        return (t, tp);
    case let i: idt =>
        match(get_nm(i, ctxt.scp)){
        case let var: *nmsp =>
            const cast = parse_cast(f, var.vtype)?;
            if(!need_extnd(var.vtype, cast)){
                return (var, cast);
            } else {
                const wrp = synthexp {
                    buffer = memio::dynamic(),
                    expr_t = cast,
                    is_ret = false,
                    single = false,
                    fncall = void,
                    finish = eol,
                    exp_id = fmt::asprintf("{}.{}", var.name,
                        get_qbe_t(cast, 1)),
                };
                fmt::fprintf(&wrp.buffer, "\t%{} =l ext{} %{}\n", wrp.exp_id,
                    get_qbe_t(var.vtype, 2), var.name)!;
                return (wrp, cast);
            };
        case let fun: *func =>
            if(ahead(f, sym::OPEN_PAR) is sym){
                const call = eval_fcall(fun, f, ctxt)?;
                const cast = parse_cast(f, call.fun.retrn)?;
                if(!need_extnd(call.fun.retrn, cast)){
                    const wrp = synthexp {
                        buffer = memio::dynamic(),
                        expr_t = cast,
                        is_ret = false,
                        single = false,
                        fncall = void,
                        finish = eol,
                        exp_id = fmt::asprintf("{}",
                            gen_wrp(call.fun, f, ctxt, true)),
                    };
                    const (chdr, fname) = gen_fcall(call, ctxt, f);
                    defer io::close(&chdr)!;
                    fmt::fprintf(&wrp.buffer, "\t{}\n", memio::string(&chdr)!)!;
                    return (wrp, cast);
                } else {
                    const wrp = synthexp {
                        buffer = memio::dynamic(),
                        expr_t = cast,
                        is_ret = false,
                        single = false,
                        fncall = void,
                        finish = eol,
                        exp_id = fmt::asprintf("{}.l",
                            gen_wrp(call.fun, f, ctxt, true)),
                    };
                    const (chdr, fname) = gen_fcall(call, ctxt, f);
                    defer io::close(&chdr)!;
                    fmt::fprintf(&wrp.buffer, "{}\n\t%{} =l ext{} {}\n",
                        memio::string(&chdr)!, wrp.exp_id,
                        get_qbe_t(call.fun.retrn, 2), fname)!;
                    return (wrp, cast);
                };
            };
            return (fun, prim::FUNCTION);
        case void =>
            expct(!ctxt.assign, eol, f,
                "invalid use of undefined variable")?;
            // TODO: local functions
            const nm = push_var(i, f, ctxt)?;
            return (nm, void);
        };
    case =>
        return (void, prim::UNIT);
    };
};

fn eval_boolexp(f: *file, ctxt: *context, lin: size, cln: size, buff: memio::stream,
    frst: (synthexp | void) = void) (synthexp | COMP_ERR) = {
    static let exp_cnt = 0z;
    exp_cnt += 1;

    assert(cln != 15);

    const idx = fmt::asprintf("{:x}", exp_cnt);
    const exp_id = fmt::asprintf(".{}.{}", lin, cln);

    const (exp, next, not): (synthexp, tok, bool) =
        match(frst){
        case void =>
            let next = nxttk(f)?;
            const not =
                if(cmp_tok(next, kwd::NOT_OPER)){
                    next = nxttk(f)?;
                    yield true;
                } else {
                    yield false;
                };
            const e = eval_exp(f, ctxt, next, memio::dynamic(),
                [ kwd::AND_OPER, kwd::OR__OPER ], lin, cln)?;
            yield (e, e.finish, not);
        case let e: synthexp =>
            yield (e, e.finish, false);
        };
    defer io::close(&exp)!;

    const tpz = get_qbe_t(exp.expr_t, 1);
    let (eval, hdr): (str, str) =
        if(!exp.single){
            const id = fmt::asprintf("%{}", exp.exp_id);
            yield (id, memio::string(&exp)!);
        // TODO: update this for structures
        } else if(is_obj(exp.expr_t)){
            const id = "%l.v";
            const h = fmt::asprintf("\t%l.v =l loadl {}\n",
                memio::string(&exp)!);
            yield (id, h);
        } else if(exp.expr_t == prim::UNIT){
                yield ("0", "");
        } else {
            yield (memio::string(&exp)!, "");
        };
    if(!not){
        fmt::fprintf(&buff, "{}\t%{}.e ={} copy {}\n",
            hdr, exp_id, tpz, eval)!;
    } else {
        fmt::fprintf(&buff, "{}\t%{}.e ={} ceql {}, 0\n",
            hdr, exp_id, tpz, eval)!;
    };
    match(next){
    case let k: kwd =>
        expct(cmp_tok(k, kwd::AND_OPER) || cmp_tok(k, kwd::OR__OPER),
            k, f, "unexpected keyword found here")?;

        const rgt = eval_boolexp(f, ctxt, lin, cln, memio::dynamic())?;
        defer io::close(&rgt)!;
        if(k == kwd::AND_OPER){
            fmt::fprintf(&buff, "\tjnz {0}, @c{3}.{4}, @f{3}\n@c{3}.{4}\n{1}\t%{3}.e ={5} copy %{2}\n",
                eval, memio::string(&rgt)!, rgt.exp_id, exp_id, idx, tpz)!;
        } else {
            fmt::fprintf(&buff, "\tjnz {0}, @t{3}, @c{3}.{4}\n@c{3}.{4}\n{1}\t%{3}.e ={5} copy %{2}\n",
                eval, memio::string(&rgt)!, rgt.exp_id, exp_id, idx, tpz)!;
        };
        next = rgt.finish;
    case => void;
    };
    return synthexp {
        buffer = buff,
        expr_t = exp.expr_t,
        is_ret = false,
        single = false,
        fncall = void,
        finish = next,
        exp_id = fmt::asprintf("{}.e", exp_id),
    };
};

fn eval_statement(stt: kwd, f: *file, ctxt: *context, ret_tp: prim,
    limit: []tok = [eos]) (synthexp | COMP_ERR) = {
    const safe = ctxt.branch;
    ctxt.branch = true;
    let out = synthexp {
        buffer = memio::dynamic(),
        expr_t = ret_tp,
        is_ret = false,
        single = false,
        fncall = void,
        finish = eol,
        exp_id = fmt::asprintf(".{}.{}.eval", f.lin, f.cln),
    };
    let next = stt: tok;
    switch(stt){
    case kwd::IF___BLK =>
        let over = ctxt.scp;
        let if_scp = scope {
            pos = (f.lin, f.cln),
            over = over,
            vars = [],
            funs = [],
        };
        defer free_scp(&if_scp);
        ctxt.scp = &if_scp;
        defer ctxt.scp = over;

        let brets = false;
        let exhst = true;
        const (l, c) = (f.lin + 1, f.cln + 1);
        for(cmp_tok(next, kwd::IF___BLK)){
            exhst = false;
            const bexp = eval_boolexp(f, ctxt, l, c, memio::dynamic())?;
            defer io::close(&bexp)!;
            const (ifbody, iftp, if_ret) = eval_body(f, ctxt, ret_tp, out.exp_id)?;
            defer io::close(&ifbody)!;
            if(brets){
                expct(if_ret || iftp == prim::UNIT, eol, f,
                    "not all branches produce values")?;
            } else {
                brets = if_ret;
            };
            expct(is_subt(iftp, ret_tp), eol, f, "mismatch between statement and reciever types",
                cast_err(iftp, ret_tp))?;

            fmt::fprintfln(&out, "{2}\tjnz %{3}, @t.{0}.{1}, @f.{0}.{1}\n@t.{0}.{1}\n{4}\tjmp @end.{0}.{1}\n@f.{0}.{1}",
                l, c, memio::string(&bexp)!, bexp.exp_id, memio::string(&ifbody)!)!;

            next = nxttk(f)?;
            if(cmp_tok(next, kwd::ELSE_BLK)){
                exhst = true;
                if(ahead(f, kwd::IF___BLK) is kwd){
                    next = nxttk(f)!;
                    continue;
                } else {
                    const (elbody, eltp, el_ret) = eval_body(f, ctxt, ret_tp, out.exp_id)?;
                    defer io::close(&elbody)!;
                    if(brets){
                        expct(el_ret || eltp == prim::UNIT, eol, f,
                            "not all branches produce values")?;
                    } else {
                        brets = el_ret;
                    };
                    expct(is_subt(eltp, ret_tp), eol, f, "mismatch between statement and reciever types",
                        cast_err(eltp, ret_tp))?;

                    fmt::fprint(&out, memio::string(&elbody)!)!;
                };
                out.finish = nxttk(f)?;
            } else {
                out.finish = next;
            };
            fmt::fprintfln(&out, "\tjmp @end.{0}.{1}\n@end.{0}.{1}", l, c)!;
        };
        out.is_ret = !is_limit(out.finish, limit);
        if(out.is_ret || (brets && !safe)){
            expct(exhst, eol, f,
                "not all code branches produce values")?;
        };
    case kwd::MATCHBLK => void;
    case kwd::TODO_HLT =>
        const val = getdefval(ret_tp);
        fmt::fprintfln(&out, "\tret {}", val)!;
        out.expr_t = prim::VOID;
        out.finish = nxttk(f)?;
        out.is_ret = true;
        expct(cmp_tok(out.finish, sym::CLS_CRLY), out.finish, f,
            "void statements cannot be followed by more code")?;
    case kwd::FAIL_HLT => void;
    case kwd::UNIT_LIT =>
        return synthexp {
            buffer = memio::dynamic(),
            expr_t = prim::UNIT,
            is_ret = false,
            single = true,
            fncall = void,
            finish = eol,
            exp_id = "",
        };
    case =>
        return errmsg(f, "expected valid statement");
    };
    ctxt.branch = safe;
    if(is_type(out.finish)){
        out.expr_t = cast_to(out.expr_t,
            kwd_to_tp(out.finish: kwd), out.finish, f)?;
    };
    return out;
};

fn eval_fcall(fun: *func, f: *file, ctxt: *context) (funcall | COMP_ERR) = {
    check_efx(f, fun, ctxt)?;

    let next = nxttk(f)!;
    assert(next: sym == sym::OPEN_PAR);

    next = nxttk(f)?;
    let call = funcall {
        fun = fun,
        args = [],
    };
    let argc = 0z;
    const p_len = len(fun.param);
    const limit = [ sym::SYMCOMMA, sym::CLOSEPAR ]: []tok;
    for(!is_limit(next, [sym::CLOSEPAR])){
        if(argc == p_len)
            return errmsg(f, "too many arguments given",
                fmt::asprintf("the fuction {} takes {}, but recieved {}", fun.name,
                plural("{} argument", p_len), plural("{} argument", argc)));
        const exp = eval_exp(f, ctxt, next, memio::dynamic(), limit)?;
        append(call.args, exp);

        expct(is_subt(exp.expr_t, fun.param[argc].1), next, f,
            "mismatch between parameter and argument types",
            cast_err(exp.expr_t, fun.param[argc].1, false, argc + 1))?;

        argc += 1;
        if(cmp_tok(exp.finish, sym::CLOSEPAR)){
            break;
        };
        next = nxttk(f)?;
    };
    return call;
};

fn gen_args(call: funcall) (memio::stream, memio::stream) = {
    let argl = memio::dynamic();
    let header = memio::dynamic();
    const argc = len(call.args);
    for(let a = 0z; a < argc; a += 1){
        defer io::close(&call.args[a])!;
        const id =
            if(!need_extnd(call.args[a].expr_t, call.fun.param[a].1)){
                yield
                if(call.args[a].single){
                    yield memio::string(&call.args[a])!;
                } else {
                    fmt::fprint(&header, memio::string(&call.args[a])!)!;
                    yield fmt::asprintf("%{}", call.args[a].exp_id);
                };
            } else {
                const wrp = fmt::asprintf("%.{}.l", a);
                fmt::fprintf(&header, "{} =l ext{} {}\n", wrp,
                    get_qbe_t(call.args[a].expr_t, 2), memio::string(&call.args[a])!)!;
                yield wrp;
            };
        if(a > 0){
            fmt::fprintf(&argl, ", {} {}",
                get_qbe_t(call.fun.param[a].1, 1), id)!;
        } else {
            fmt::fprintf(&argl, "{} {}",
                get_qbe_t(call.fun.param[a].1), id)!;
        };
    };
    return (argl, header);
};

fn gen_params(params: [](idt, prim)) memio::stream = {
    let buff = memio::dynamic();
    const max = len(params);
    for(let p = 0z; p < max; p += 1){
        const prm = params[p];
        if(p > 0){
            fmt::fprintf(&buff, ", {} %{}",
                get_qbe_t(prm.1, 1), prm.0: str)!;
        } else {
            fmt::fprintf(&buff, "{} %{}",
                get_qbe_t(prm.1, 1), prm.0: str)!;
        };
    };
    return buff;
};

fn gen_fcall(call: funcall, ctxt: *context, f: *file) (memio::stream, str) = {
    const (args_l, call_h) = gen_args(call);
    defer io::close(&args_l)!;
    defer io::close(&call_h)!;
    const argl = memio::string(&args_l)!;
    const chdr = memio::string(&call_h)!;

    let buf = memio::dynamic();
    const wrp = gen_wrp(call.fun, f, ctxt, true);
    if(len(chdr) > 0){
        fmt::fprintf(&buf, "{0}\t%{1} ={2} call ${1}({3})", chdr,
            wrp, get_qbe_t(call.fun.retrn, 1), argl)!;
    } else {
        fmt::fprintf(&buf, "%{0} ={1} call ${0}({2})", wrp,
            get_qbe_t(call.fun.retrn, 1), argl)!;
    };
    if(is_obj(call.fun.retrn)){
        void;//fmt::fprintf(&buf, "\n\t%{0} =l call $rt.movstk(l %{0})", wrp)!;
    };
    return (buf, fmt::asprintf("%{}", wrp));
};

fn is_limit(tkn: tok, lmt: []tok) bool = {
    for(let l .. lmt){
        if(cmp_tok(tkn, l)) return true;
    };
    return false;
};

fn plural(pat: str, cnt: u64) str = {
    if(cnt == 1){
        return fmt::asprintf(pat, cnt);
    } else {
        return strings::concat(fmt::asprintf(pat, cnt), "s");
    };
};

fn ordnum(n: u64) str = {
    switch(n){
    case 1 => return "first";
    case 2 => return "second";
    case 3 => return "third";
    case => return fmt::asprintf("{}th", n);
    };
};

fn ftomod(file: str) str = {
    const (name, _) = rem_path(file);
    return strings::replace(name, ".ms", "");
};

fn check_uof(f: *file, val: num, expr_t: prim) (void | COMP_ERR) = {
    if(is_num(expr_t)){
        const n = val;
        switch(expr_t){
        case prim::U8 =>
            if(n > (~0: u8): u64){
                return errmsg(f, "numberic literal overflows dest type (i8)"): SNTX_ERR;
            };
        case prim::U16 =>
            if(n > (~0: u16): u64){
                return errmsg(f, "numberic literal overflows dest type (u16)"): SNTX_ERR;
            };
        case prim::U32 =>
            if(n > (~0: u32): u64){
                return errmsg(f, "numberic literal overflows dest type (u32)"): SNTX_ERR;
            };
        case prim::U64, prim::NUMBER => return;
        case =>
            assert(false);
        };
    } else {
        const n =
            if(val >= (1 << 64 / 2 - 1): u64){
                return errmsg(f, "numberic literal overflows dest type (i32)"): SNTX_ERR;
            } else {
                yield val: i64;
            };
        switch(expr_t){
        case prim::I8 =>
            if(n < -(1 << 7): i64 || n > ((1 << 7) - 1): i64){
                return errmsg(f, "numberic literal overflows dest type (i8)"): SNTX_ERR;
            };
        case prim::I16 =>
            if(n < -(1 << 15): i64 || n > ((1 << 15) - 1): i64){
                return errmsg(f, "numberic literal overflows dest type (i16)"): SNTX_ERR;
            };
        case prim::I32 =>
            if(n < -(1 << 31): i64 || n > ((1 << 31) - 1): i64){
                return errmsg(f, "numberic literal overflows dest type (i32)"): SNTX_ERR;
            };
        case prim::I64 =>
            if(n < -(1 << 63): i64 || n > ((1 << 63) - 1): i64){
                return errmsg(f, "numberic literal overflows dest type (i64)"): SNTX_ERR;
            };
        case prim::NUMBER => return;
        case =>
            assert(false);
        };
    };
};

fn check_efx(f: *file, fun: *func, ctxt: *context) (void | COMP_ERR) = {
    if(!fun.impure) return;
    const effect = ftomod(fun.origin);
    if(fun.origin == f.name){
        for(let f_efx .. fun.effect){
            for(let tag .. ctxt.effect){
                if(f_efx == tag) return;
            };
        };
        return errmsg(f, "the host function is not tagged with all effects produced by this call",
            get_efx(fun, "", ctxt.effect)): SNTX_ERR;
    } else {
        for(let tag .. ctxt.effect){
            if(tag == effect) return;
        };
        return errmsg(f, "the host function is not tagged with all effects produced by this call",
            get_efx(fun, effect, ctxt.effect)): SNTX_ERR;
    };
};

fn get_efx(fun: *func, mod: str, host: []str) str = {
    let first = true;
    assert(len(fun.effect) > 0);
    let out = "";
    if(mod == ""){
        out = fmt::asprintf("the function {} produces these effects:", fun.name);
        for(let efx .. fun.effect){
            if(first){
                out = fmt::asprintf("{} {}{}", out, CMD[cmd::YEL], efx);
                first = false;
            } else {
                out = fmt::asprintf("{}, {}", out, efx);
            };
        };
        out = fmt::asprintf("{}{}", out, CMD[cmd::DEF]);
    } else {
        out = fmt::asprintf("the function {} is from the module {} and uses this name as effect tag",
            fmtc(fun.name, cmd::YEL), fmtc(ftomod(fun.origin), cmd::YEL));
    };
    if(len(host) > 0){
        out = fmt::asprintf("{}\nthe host function is tagged with:", out);
        first = true;
        for(let efx .. host){
            if(first){
                out = fmt::asprintf("{} {}{}", out, CMD[cmd::YEL], efx);
                first = false;
            } else {
                out = fmt::asprintf("{}, {}", out, efx);
            };
        };
        out = fmt::asprintf("{}{}", out, CMD[cmd::DEF]);
    } else {
        out = fmt::asprintf("{}\nthe host function has no effect tags", out);
    };
    return out;
};

fn operable(lft: prim, rgt: prim, oper: opr) bool = {
    if(lft == prim::NUMBER) lft = rgt;
    if(rgt == prim::NUMBER) rgt = lft;
    switch(oper){
    case opr::BOOL_LSS, opr::BOOL_GRT, opr::BOOL_LEQ, opr::BOOL_GEQ,
        opr::BOOL_EQL, opr::BOOL_DIF =>
        return lft == rgt;
    case =>
        return is_subt(lft, prim::NUMBER) &&
            is_subt(rgt, prim::NUMBER) && lft == rgt;
    };
};

fn is_subt(tp: prim, set: prim) bool = {
    if(set == prim::ANY) return true;
    switch(set){
    case prim::U8, prim::U16, prim::U32, prim::U64 =>
        return is_num(tp) && (tp <= set || tp == prim::NUMBER);
    case prim::I8, prim::I16, prim::I32, prim::I64 =>
        if(is_num(tp, true)) return tp <= set || tp == prim::NUMBER;
        return false;
    case prim::STRING =>
        return tp == set;
    case prim::NUMBER =>
        return is_num(tp) || is_num(tp, true);
    case prim::RATIO =>
        return tp == prim::F32 || tp == prim::F64 || tp == prim::NUMBER;
    case prim::UNIT, prim::VOID =>
        return tp == set;
    case =>
        fmt::fatal("is_subt: unreachable");
    };
};

fn is_num(tp: prim, sign: bool = false) bool = {
    if(tp == prim::NUMBER) return true;
    if(!sign){
        return prim::U8 <= tp && tp <= prim::U64;
    } else {
        return prim::I8 <= tp && tp <= prim::I64;
    };
};

fn is_untyped(tp: prim) bool = {
    return tp == prim::NUMBER || tp == prim::RATIO;
};

fn need_extnd(src: prim, dst: prim) bool = {
    if(src == prim::NUMBER || src == prim::UNIT
        || src == prim::VOID) return false;
    return get_t_len(src) <= 4 && get_t_len(dst) == 8;
};

fn sign_mismtch(l: prim, r: prim) bool = {
    return (is_num(l) && is_num(r, true)) || (is_num(r) && is_num(l, true));
};

fn parse_cast(f: *file, src: prim) (prim | COMP_ERR) = {
    let out_t = src;
    const next = nxttk(f, true)?;
    if(is_type(next)){
        out_t = cast_to(src, kwd_to_tp(next: kwd), next, f)?;
    } else {
        setptr(f, true);
    };
    return out_t;
};

fn cast_to(s: prim, d: prim, t: tok, f: *file) (prim | COMP_ERR) = {
    expct(castable(s, d), t, f,
        "mismatch between member types", cast_err(s, d))?;
    return d;
};

fn castable(s: prim, d: prim) bool = {
    if(d == prim::ANY || s == prim::ANY) return true;
    if((is_num(s) || is_num(s, true)) &&
        (is_num(d) || is_num(d, true))) return true;
    return s == d;
};

fn cast_err(s: prim, d: prim, oper: bool = false, num: size = 0) str = {
    if(oper){
        return fmt::asprintf("lefthand type is {}, but righthand type is {}", primv[s], primv[d]);
    } else {
        if(num == 0){
            return fmt::asprintf("source type is {}, but dest type is {}", primv[s], primv[d]);
        } else {
            return fmt::asprintf("the {} parameter takes a {}, but the given argument is a {}",
                ordnum(num), primv[d], primv[s]);
        };
    };
};

fn within_self(call: funcall, ctxt: *context) bool = {
    if(ctxt.fnname is str && call.fun.name == ctxt.fnname: str){
        return true;
    } else {
        return false;
    };
};
