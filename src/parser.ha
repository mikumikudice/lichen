use fmt;
use strlib;
use strings;

fn todo(f: *file, msg: str) (void | CMP_ERR) = {
    fmt::printfln("TODO: {} at {}:{}:{}",
        msg, f.name, f.lin + 1, f.cln + 1)!;
    let t = nxttk(f)?;
    for(!(t is eol)){
        t = nxttk(f)?;
    };
};

@test fn type_system() void = {
    assert(is_subt(kwd::U16_TYPE, kwd::U16_TYPE) == true);
    assert(is_subt(kwd::U8__TYPE, kwd::U64_TYPE) == true);
    assert(is_subt(kwd::U32_TYPE, kwd::I32_TYPE) == false);
    assert(is_subt(kwd::U32_TYPE, kwd::U16_TYPE) == false);
    assert(is_subt(kwd::I32_TYPE, kwd::U32_TYPE) == false);
    assert(is_subt(kwd::I8__TYPE, kwd::U64_TYPE) == false);
};

// returns the default value for each primitive type
fn getdefval(vtp: kwd) str = {
    switch(vtp){
    case kwd::U8__TYPE, kwd::I8__TYPE =>
        return "0";
    case kwd::U16_TYPE, kwd::I16_TYPE =>
        return "0";
    case kwd::U32_TYPE, kwd::I32_TYPE =>
        return "0";
    case kwd::U64_TYPE, kwd::I64_TYPE,
        kwd::RATIO__T =>
        return "0";
    case kwd::STRING_T, kwd::ARRAY__T =>
        return "0";
    case kwd::UNITTYPE =>
        return "0xcafe0000";
    case =>
        assert(false);
        return "";
    };
};

// converts moss types to qbe types i.e. type length
fn tptob(vtp: kwd) str = {
    switch(vtp){
    case kwd::U8__TYPE, kwd::I8__TYPE =>
        return "b";
    case kwd::I16_TYPE, kwd::U16_TYPE =>
        return "h";
    case kwd::U32_TYPE, kwd::I32_TYPE,
        kwd::NOT_KWRD, kwd::NUMBER_T =>
        return "w";
    case kwd::U64_TYPE, kwd::I64_TYPE, kwd::RATIO__T,
        kwd::STRING_T, kwd::RAW_TYPE, kwd::ARRAY__T =>
        return "l";
    case =>
        fmt::errorfln("unknown type {}", vtp: int)!;
        assert(false);
        return "";
    };
};

// returns size in bytes of a type
fn tptoz(vtp: kwd) str = {
    switch(vtp){
    case kwd::U8__TYPE, kwd::I8__TYPE =>
        return "1";
    case kwd::I16_TYPE, kwd::U16_TYPE =>
        return "2";
    case kwd::U32_TYPE, kwd::I32_TYPE =>
        return "4";
    case kwd::U64_TYPE, kwd::I64_TYPE,
        kwd::RATIO__T =>
        return "8";
    case =>
        assert(false);
        return "";
    };
};


let datasec = "";
let str_lit = []: []str;
fn pushstr(l: str) str = {
    const max = len(str_lit);
    for(let i = 0z; i < max; i += 1){
        if(l == str_lit[i]){
            return fmt::asprintf("$.{}", i);
        };
    };
    append(str_lit, l);
    datasec = fmt::asprintf("{}data $.{} = {{ w {}, b \"{}\" }}\n",
        datasec, max, len(l), l);
    return fmt::asprintf("$.{}", max);
};

fn pushref(id: str, f: *file, scp: *scope, add: *[]idref) (void | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("pushing new reference to \"{}\" at {}:{}:{}", id, f.name, f.lin + 1, f.cln + 1)!;
    const max = len(add);
    const nm =
        match(get_idt(id, f, scp)?){
        case let i: *nmsp =>
            yield i;
        case =>
            const err = fmt::asprintf("namespace \"{}\" should be defined", id);
            return (err, f): UNREACH;
        };
    // value is already loaded
    if(nm.param) return;

    for(let i = 0z; i < max; i += 1){
        if(add[i].idt == id){
            return;
        };
    };
    append(add, idref {
        idt = id,
        vtp = nm.vtype,
        mod = false,
    });
};

fn pushgref(id: str, tp: kwd, add: *[]idref) void = {
    const max = len(add);
    for(let i = 0z; i < max; i += 1){
        if(add[i].idt == id && add[i].mod){
            return;
        };
    };
    append(add, idref {
        idt = id,
        vtp = tp,
        mod = true,
    });
};

fn solve_ref(refs: *[]idref) str = {
    let hdr = "";
    const max = len(refs);
    for(let i = 0z; i < max; i += 1){
        if(refs[i].mod){
            hdr = fmt::asprintf("{0}    %{1}.gv ={2} load{2} ${1}\n",
                hdr, refs[i].idt, tptob(refs[i].vtp));
        } else {
            hdr = fmt::asprintf("{0}    %{1}.v ={2} load{2} %{1}\n",
                hdr, refs[i].idt, tptob(refs[i].vtp));
        };
    };
    return hdr;
};

fn get_idpos(id: (*nmsp | *func)) str = {
    match(id){
    case let var: *nmsp =>
        const orign =
            match(var.orign){
            case let fname: str =>
                yield fname;
            case let kid: kernel =>
                yield krnls[kid];
            };
        return fmt::asprintf("{}:{}:{}", orign, var.lin + 1, var.cln + 1);
    case let fun: *func =>
        const orign =
            match(fun.orign){
            case let fname: str =>
                yield fname;
            case let kid: kernel =>
                yield krnls[kid];
            };
        return fmt::asprintf("{}:{}:{}", orign, fun.lin + 1, fun.cln + 1);
    };
};

fn push_idt(nm: idt, mut: bool, f: *file, scp: *scope) ((*nmsp | *func) | IDTCDUP) = {
    if(stacktrace)
        fmt::printfln("pushing identifier \"{}\"", nm)!;
    match(get_idt(nm, f, scp, true)){
    case let var: *nmsp =>
        return bi_msg {
            lft = nm: str,
            rgt = get_idpos(var),
            tip = void,
            ptr = f,
        }: IDTCDUP;
    case let fun: *func =>
        // only push_fun effectively pushes functions
        return fun;
    case =>
        const new = alloc(nmsp {
            ident = nm: str,
            vtype = kwd::NOT_KWRD,
            mutbl = mut,
            asgnd = false,
            param = false,
            orign = f.name,
            lin = f.lin,
            cln = f.cln,
        });
        append(scp.defs, new);
        return new;
    };
};

fn get_idt(nm: idt, f: *file, scp: *scope, notmod: bool = false) (*nmsp | *func | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("getting identifier \"{}\"", nm)!;

    if(!notmod){
        let next = nxttk(f, true)?;
        if(cmp_tok(next, opr::MODFIELD)){
            return parse_field(nm, f, scp)?;
        } else {
            setptr(f, true);
        };
    };

    for(let n ..& scp.defs){
        if(n.ident == nm: str) return n;
    };
    for(let f ..& scp.funs){
        if(f.fname == nm: str) return f;
    };
    if(!(scp.over is void)){
        return get_idt(nm, f, scp.over: *scope, true)?;
    };

    return unimsg {
        msg = nm: str,
        tip = void,
        ptr = f,
    }: UNDEFNS;
};

fn push_fun(name: idt, f: *file, parm_l: []kwd, parm_n : []idt, retrn: kwd, scp: *scope) (*func | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("pushing function \"{}\" at {}:{}:{}", name, f.name, f.lin + 1, f.cln + 1)!;
    assert(scp.over is void);
    match(get_idt(name, f, scp, true)){
    case let var: *nmsp =>
        return bi_msg {
            lft = name: str,
            rgt = get_idpos(var),
            tip = void,
            ptr = f,
        }: IDTCDUP;

    case let fun: *func =>
        return bi_msg {
            lft = name: str,
            rgt = get_idpos(fun),
            tip = void,
            ptr = f,
        }: IDTCDUP;

    case =>
        const fun = alloc(func {
            fname = name: str,
            param = parm_l,
            prm_n = parm_n,
            retrn = retrn,
            ret_n = "",
            orign = f.name,
            lin = f.lin,
            cln = f.cln,
        });
        append(scp.funs, fun);
        return fun;
    };
};

// TODO: create a module for each global parsed file
// TODO: push defined functions to this said module
let ldd_mods = []: []module;

// parses a source. if `from` is a string, opens the file and parses its contents, if the file
// itself, parses a new scope withih `within`. returns a header containing global definitions,
// the parsed source itself in the QBE IR and the final type of return, in the case of parsing
// a function body. in case of any parsing error, returns a compilation error
fn parse(from: (str | *file), scp: *scope, stop: size = 0) ((str, kwd) | CMP_ERR) = {
    let out = "";
    let ret_tp = kwd::UNITTYPE;
    let f =
        match(from){
        case let fname: str =>
            if(stacktrace)
                fmt::printfln("parsing file \"{}\"", fname)!;

            const _f =  load(fname)?;
            parse_globl(_f, scp)?;
            yield _f;
        case let _f: *file =>
            if(stacktrace)
                fmt::printfln("parsing function at {}:{}:{}",
                    _f.name, _f.lin + 1, _f.cln + 1)!;
            yield _f;
        };
    const max = len(f.src);

    for(f.ptr < max){
        let next = nxttk(f)?;
        if(next is eol) continue;
        if(next is eof) break;

        //fmt::println(tktostr(next: tok, true))!;

        match(next: tok){
        case let k: kwd =>
            switch(k){
            // "pub", [ "type", ] idt, "=", expr
            case kwd::PUBFIELD =>
                if(!(scp.over is void)){
                    return unimsg {
                        msg = "export public fields within functions",
                        tip = "try moving it to the global scope",
                        ptr = f,
                    }: CANT_DO;
                };
                next = nxttk(f)?;
                const obj = expct(next is kwd || next is idt,
                    next, f, void: EXPECTD, "type or variable definition")?;

                match(obj){
                case let k: kwd =>
                    todo(f, "type definition")?;
                case let i: idt =>
                    const (exp, _) = parse_asg(f, i: str, scp)?;
                    out = fmt::asprintf("{}export {}", out, exp);
                };
            case kwd::DMUTABLE =>
                if(scp.over is void){
                    return unimsg {
                        msg = "define mutable variables at global scope",
                        tip = "try moving it to inside a function",
                        ptr = f,
                    }: CANT_DO;
                };
                next = nxttk(f)?;
                const i = expct(next is idt,
                    next, f, void: EXPECTD, "variable definition")?: idt;

                const nm =
                    match(push_idt(i: str, false, f, scp)?){
                        case let var: *nmsp =>
                            yield var;
                        case *func =>
                            return ("unhandled mutable function case", f): UNREACH;
                    };
                nm.mutbl = true;
                next = nxttk(f, true)?;
                const oper = expct(next is opr, next, f, void: EXPECTD,
                    "declaration or assignment")?: opr;
                
                switch(oper){
                case opr::CASTTOTP =>
                    next = nxttk(f)?;
                    const tp = expct(is_type(next), next, f, void: EXPECTD,
                        "valid type notation")?: kwd;
                    nm.vtype = tp;
                    out = fmt::asprintf("{0}    %{1} =l alloc4 {2}\n    store{3} {4}, %{1}\n",
                        out, i: str, tptoz(tp), tptob(tp), getdefval(tp));

                    finsh(f, void: EXPECTD, "end of declaration")?;

                case opr::ASSIGNMT =>
                    setptr(f, true);
                    const (exp, tp) = parse_asg(f, i: str, scp)?;
                    nm.vtype = tp;
                    nm.asgnd = true;
                    out = fmt::asprintf("{}    %{} =l alloc4 {}\n{}",
                        out, i: str, tptoz(tp), exp);
                case =>
                    return bi_msg {
                        lft = "declaration or assignment",
                        rgt = tktostr(oper),
                        tip = void,
                        ptr = f,
                    }: EXPECTD;
                };
            case kwd::USE__MOD =>
                if(!(scp.over is void)){
                    return unimsg {
                        msg = "require external modules within functions",
                        tip = "try moving it to the global scope",
                        ptr = f,
                    }: CANT_DO;
                };
                next = nxttk(f)?;
                const mod = expct(next is idt, next, f, void: EXPECTD,
                    "module name identifier")?: idt;
                
                match(strlib::findl(krnls, mod: str)){
                case let i: size =>
                    // TODO: un-hardcode these definitions
                    switch(i){
                    case kernel::IO =>
                        const mod_io = module {
                            name = mod: str,
                            funs =
                                [ func { // read = fn(handle : u32, size: u32) : @str
                                    fname = "read",
                                    param = [ kwd::U32_TYPE, kwd::U32_TYPE ],
                                    retrn = kwd::STRING_T, // TODO: this should be an union (@str ! u32)
                                    ret_n = "",
                                    orign = kernel::IO,
                                    ...
                                }
                                , func { // write = fn(handle : u32, data : str) : u32
                                    fname = "write",
                                    param = [ kwd::U32_TYPE, kwd::STRING_T ],
                                    retrn = kwd::UNITTYPE,  // TODO: this should be an union (unit ! u32)
                                    ret_n = "",
                                    orign = kernel::IO,
                                    ...
                                }
                                ],
                            vars =
                                [ nmsp {
                                    ident = "stdin",
                                    vtype = kwd::U32_TYPE,
                                    mutbl = false,
                                    asgnd = true,
                                    orign = kernel::IO,
                                    ...
                                }
                                , nmsp {
                                    ident = "stdout",
                                    vtype = kwd::U32_TYPE,
                                    mutbl = false,
                                    asgnd = true,
                                    orign = kernel::IO,
                                    ...
                                }
                                , nmsp {
                                    ident = "stderr",
                                    vtype = kwd::U32_TYPE,
                                    mutbl = false,
                                    asgnd = true,
                                    orign = kernel::IO,
                                    ...
                                }
                                ],
                        };
                        append(ldd_mods, mod_io);
                    case kernel::MEM =>
                        const mod_mem = module {
                            name = mod: str,
                            funs =
                                [ func { // alloc = fn(size: u32) : @raw
                                    fname = "alloc",
                                    param = [ kwd::U32_TYPE ],
                                    retrn = kwd::RAW_TYPE,
                                    ret_n = "",
                                    orign = kernel::MEM,
                                    ...
                                }
                                , func { // free = fn(obj : @raw) : unit
                                    fname = "free",
                                    param = [ kwd::RAW_TYPE ],
                                    retrn = kwd::UNITTYPE,
                                    ret_n = "",
                                    orign = kernel::MEM,
                                    ...
                                }
                                , func { // copy = fn(dest : @raw, src : raw, size : u32) : @raw
                                    fname = "copy",
                                    param = [ kwd::RAW_TYPE, kwd::RAW_TYPE, kwd::U32_TYPE ],
                                    retrn = kwd::RAW_TYPE,
                                    ret_n = "",
                                    orign = kernel::MEM,
                                    ...
                                }
                                ],
                            vars = [],
                        };
                        append(ldd_mods, mod_mem);
                    case =>
                        const err = fmt::asprintf("module {} not matched", mod: str);
                        return (err, f): UNREACH;
                    };
                case void =>
                    todo(f, "local modules not implemented yet")?;
                };
            case kwd::RETURNTO =>
                let add = []: []idref;
                const dup = alloc(*f);
                const (exp, expr_t) = parse_exp(f, "", scp, &add)?;
                
                if(ret_tp == kwd::UNITTYPE){
                    ret_tp = expr_t;
                } else {
                    expct(is_subt(expr_t, ret_tp), expr_t, dup, void: MISMTCH,
                        "return types", "union types are not implemented yet")?;
                };
                free(dup);
                out = fmt::asprintf("{}{}{}    ret %.val\n", out, solve_ref(&add), exp);
            case =>
                todo(f, "uncovered rule")?;
            };
        case let i: idt =>
            match(get_idt(i, f, scp)){
            case =>
                const nm = push_idt(i: str, false, f, scp)!: *nmsp;
                next = nxttk(f, true)?;
                const oper = expct(next is opr, next, f, void: EXPECTD,
                    "declaration or assignment")?: opr;
                
                switch(oper){
                case opr::CASTTOTP =>
                    next = nxttk(f)?;
                    const tp = expct(is_type(next), next, f, void: EXPECTD,
                        "valid type notation")?: kwd;
                    nm.vtype = tp;
                    out = fmt::asprintf("{0}    %{1} =l alloc4 {2}\n    store{3} {4}, %{1}\n",
                        out, i: str, tptoz(tp), tptob(tp), getdefval(tp));
                    
                    finsh(f, void: EXPECTD, "end of declaration")?;

                case opr::ASSIGNMT =>
                    setptr(f, true);
                    const (exp, tp) = parse_asg(f, i: str, scp)?;
                    nm.vtype = tp;
                    nm.asgnd = true;
                    out = fmt::asprintf("{}    %{} =l alloc4 {}\n{}",
                        out, i: str, tptoz(tp), exp);
                case =>
                    return bi_msg {
                        lft = "declaration or assignment",
                        rgt = tktostr(oper),
                        tip = void,
                        ptr = f,
                    }: EXPECTD;
                };
            case let nm: *nmsp =>
                if(!nm.asgnd){
                    const dup = alloc(*f);
                    const (exp, tp) = parse_asg(f, i: str, scp)?;
                    nm.asgnd = true;

                    expct(is_subt(tp, nm.vtype), tp, dup, void: MISMTCH,
                        "variable and assignment types", cast_err(tp, nm.vtype))?;
                    free(dup);

                    out = fmt::asprintf("{0}{4}    store{2} %.val, %{1}\n",
                        out, i: str, tptob(tp), tptoz(tp), exp);
                } else if(nm.mutbl){
                    const dup = alloc(*f);
                    const (exp, tp) = parse_asg(f, i: str, scp)?;

                    expct(is_subt(tp, nm.vtype), tp, dup, void: MISMTCH,
                        "variable and assignment types", cast_err(tp, nm.vtype))?;
                    free(dup);

                    if(tp < nm.vtype){
                        out = fmt::asprintf("{0}{1}    %.f ={2} copy %.val\n    store{2} %.f, %{3}\n",
                            out, exp, tptob(nm.vtype), nm.ident);
                    } else {
                        out = fmt::asprintf("{}{}    store{} %.val, %{}\n",
                            out, exp, tptob(nm.vtype), nm.ident);
                    };
                } else {
                    return unimsg {
                        msg = "redefine a value of a immutable variable",
                        tip = void,
                        ptr = f,
                    }: CANT_DO;
                };
            case let fun: *func =>
                next = nxttk(f, true)?;
                if(cmp_tok(next, opr::ASSIGNMT)){
                    setptr(f, true);
                    const (exp, _) = parse_asg(f, i: str, scp)?;
                    out = fmt::asprintf("{}{}", out, exp);

                } else if(scp.over is void){
                    const (refs, exp) = parse_fcall(fun, f, scp)?;
                    out = fmt::asprintf("{}{}", solve_ref(refs), exp);
                    free(refs);
                    finsh(f, void: EXPECTD, "end of expression")?;

                } else {
                    todo(f, "local functions")?;
                };
            };
        case let s: sym =>
            switch(s){
            case sym::CLS_CRLY =>
                if(stop > 0 && f.ptr >= stop) break;
            case =>
                todo(f, fmt::asprintf("uncovered symbol {}", tktostr(s, true)))?;
            };
        case =>
            todo(f, "uncovered statement")?;
        };
    };
    if(scp.over is void) return (strings::concat(datasec, out), kwd::NOT_KWRD);
    return (out, ret_tp);
};

fn parse_globl(_f: *file, scp: *scope) (void | CMP_ERR) = {
    if(stacktrace)
        fmt::println("parsing global definitions")!;
    const f = alloc(*_f);
    const max = len(f.src);
    for(f.ptr < max){
        let next = nxttk(f)?;
        if(next is eol) continue;
        match(next: tok){
        case let i: idt =>
            next = nxttk(f)?;
            if(!cmp_tok(next, opr::ASSIGNMT)){
                jmpto(eol, f)?;
                continue;
            };
            next = nxttk(f)?;
            if(!cmp_tok(next, kwd::FUNCTION)){
                jmpto(eol, f)?;
                continue;
            };
            parse_fun(f, i, scp, true)?;
        case let k: kwd =>
            // TODO: parse typedefs
            switch(k){
            case kwd::PUBFIELD =>
                next = nxttk(f)?;
                const nm =
                    if(next is idt){
                        yield next: idt;
                    } else {
                        jmpto(eol, f)?;
                        continue;
                    };
                next = nxttk(f)?;
                if(!cmp_tok(next, opr::ASSIGNMT)){
                    jmpto(eol, f)?;
                    continue;
                };
                next = nxttk(f)?;
                if(!cmp_tok(next, kwd::FUNCTION)){
                    jmpto(eol, f)?;
                    continue;
                };
                parse_fun(f, nm, scp, true)?;
            case kwd::DMUTABLE =>
                next = nxttk(f)?;
                const nm =
                    if(next is idt){
                        yield next: idt;
                    } else {
                        jmpto(eol, f)?;
                        continue;
                    };
                next = nxttk(f)?;
                if(!cmp_tok(next, opr::ASSIGNMT)){
                    jmpto(eol, f)?;
                    continue;
                };
                next = nxttk(f)?;
                if(cmp_tok(next, kwd::FUNCTION)){
                    return unimsg {
                        msg = "define a function as mutable",
                        tip = "try removing the \"mut\" at the beginning of the assignment",
                        ptr = f,
                    }: CANT_DO;
                };
            case => jmpto(eol, f)?;
            };
        case => jmpto(eol, f)?;
        };
    };
    free(f);
    if(stacktrace)
        fmt::println("end of global definitions")!;
};

fn parse_field(mod: idt, f: *file, scp: *scope) (*nmsp | *func | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing mod field access")!;

    for(let m .. ldd_mods){
        if(m.name == mod: str){
            let next = nxttk(f)?;
            const field = expct(next is idt,
                next, f, void: EXPECTD, "field name")?: idt;
            let max = len(m.funs);
            for(let i = 0z; i < max; i += 1){
                const fun = &m.funs[i];
                if(field == fun.fname){
                    return fun;
                };
            };
            let max = len(m.vars);
            for(let i = 0z; i < max; i += 1){
                const var = &m.vars[i];
                if(field: str == var.ident){
                    return var;
                };
            };
            return unimsg {
                msg = fmt::asprintf("this field is not defined in the \"{}\" module", mod: str),
                tip = void,
                ptr = f,
            }: GENERIC;
        };
    };
    return unimsg {
        msg = fmt::asprintf("the module {} is not defined at this point", mod: str),
        tip = void,
        ptr = f,
    }: GENERIC;
};

fn parse_fcall(fun: *func, f: *file, scp: *scope) ((*[]idref, str) | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing function call")!;
    let out = fmt::asprintf("call ${}(", fun.fname);
    let add = alloc([]: []idref);

    let next = nxttk(f)?;
    expct(cmp_tok(next, sym::OPEN_PAR), next, f, void: EXPECTD,
        "function argument list")?;

    let argc = 0z;
    let swtch = false;
    const max = len(fun.param);
    for(!cmp_tok(next, sym::CLOSEPAR)){
        // too many args
        if(argc > max){
            return unimsg {
                msg = "too many arguments on function call",
                tip = void,
                ptr = f,
            }: GENERIC;
        };
        next = nxttk(f)?;
        if(!swtch){
            const arg = expct(next is num || next is txt || next is idt, next, f,
                void: EXPECTD, "literal or namespace")?;
            match(arg){
            case let n: num =>
                if(is_subt(kwd::NUMBER_T, fun.param[argc])){
                    if(argc == 0){
                        out = fmt::asprintf("{}w {}", out, n: u32);
                    } else {
                        out = fmt::asprintf("{}, w {}", out, n: u32);
                    };
                } else {
                    return unimsg {
                        msg = "argument and parameter types",
                        tip = cast_err(kwd::NUMBER_T, fun.param[argc]),
                        ptr = f,
                    }: MISMTCH;
                };
            case let t: txt =>
                if(is_subt(kwd::STRING_T, fun.param[argc])){
                    const val = tostr(t);
                    const ref = pushstr(val);
                    if(argc == 0){
                        out = fmt::asprintf("{}l {}", out, ref);
                    } else {
                        out = fmt::asprintf("{}, l {}", out, ref);
                    };
                } else {
                    return unimsg {
                        msg = "argument and parameter types",
                        tip = cast_err(kwd::NUMBER_T, fun.param[argc]),
                        ptr = f,
                    }: MISMTCH;
                };
            case let i: idt =>
                const nm = get_idt(i, f, scp)?;
                // TODO: handle optional casting
                match(nm){
                case let var: *nmsp =>
                    if(is_subt(var.vtype, fun.param[argc])){
                        const id =
                            if(var.orign is kernel){
                                pushgref(var.ident, var.vtype, add);
                                yield fmt::asprintf("%{}.gv", var.ident);
                            } else {
                                pushref(var.ident, f, scp, add)?;
                                yield fmt::asprintf("%{}.v", var.ident);
                            };
                        if(argc == 0){
                            out = fmt::asprintf("{}{} {}", out, tptob(var.vtype), id);
                        } else {
                            out = fmt::asprintf("{}, {} {}", out, tptob(var.vtype), id);
                        };
                    } else {
                        return unimsg {
                            msg = "argument and parameter types",
                            tip = cast_err(kwd::NUMBER_T, fun.param[argc]),
                            ptr = f,
                        }: MISMTCH;
                    };
                case let fun: *func =>
                    const (refs, exp) = parse_fcall(fun, f, scp)?;
                    append(add, (*refs)...);
                    if(argc == 0){
                        out = fmt::asprintf("{}{} {}", out, tptob(fun.retrn), exp);
                    } else {
                        out = fmt::asprintf("{}, {} {}", out, tptob(fun.retrn), exp);
                    };
                };
            case =>
                const err = fmt::asprintf("argument should be literal or identifier, but is {}",
                    tktostr(arg));
                return (err, f): UNREACH;
            };
            argc += 1;
            swtch = true;
        } else {
            expct(next is sym && (next: sym == sym::SYMCOMMA || next: sym == sym::CLOSEPAR),
                next, f, void: EXPECTD, "comma or end of argument list")?;
            swtch = false;
        };
    };
    for(argc < max){
        // TODO: default values for function parameters
        if(argc == 0){
            out = fmt::asprintf("{}{} {}", out, tptob(fun.param[argc]), getdefval(fun.param[argc]));
        } else {
            out = fmt::asprintf("{}, {} {}", out, tptob(fun.param[argc]), getdefval(fun.param[argc]));
        };
    };
    return (add, strings::concat(out, ")\n"));
};

fn parse_exp(f: *file, dest: idt, scp: *scope, add: *[]idref, limit: tok = eol) ((str, kwd) | CMP_ERR) = {
    let out = "";
    let expr_t = kwd::NOT_KWRD;
    let next = nxttk(f)?;
    // TODO: handle idt, opr, "+" | "-" | "~"
    // TODO: handle literals of records and lists
    // TODO: handle statements as valid hands
    const vall = expct(next is num || next is txt || next is idt,
        next, f, void: EXPECTD, "valid righthand")?: (num | txt | idt);
    match(vall){
    case let n: num =>
        out = fmt::asprintf("    %.val =w copy {}\n", n: u32);
        expr_t = cast_to(expr_t, kwd::U32_TYPE, vall, f)?;
    case let t: txt => void;
        const val = tostr(t);
        const idx = pushstr(val);
        out = fmt::asprintf("    %.val =l copy {}\n", idx);

        finsh(f, void: CANT_DO, "perform operations on string literals")?;
        return (out, kwd::STRING_T);

    case let i: idt => void;
        match(get_idt(i: str, f, scp)?){
        case let nm: *nmsp =>
            pushref(i: str, f, scp, add)?;
            out = fmt::asprintf("    %.val ={0} copy %{1}.v\n", tptob(nm.vtype), i: str);
            expr_t = cast_to(nm.vtype, expr_t, vall, f)?;
            // TODO: assert for composite types
        case let fun: *func =>
            const (refs, exp) = parse_fcall(fun, f, scp)?;
            append(add, (*refs)...);
            free(refs);
            out = fmt::asprintf("    %.val ={} {}\n", tptob(fun.retrn), exp);
            expr_t = cast_to(fun.retrn, expr_t, vall, f)?;
        };
    };
    // keep reading until end of expression
    next = nxttk(f)?;
    for(!(!(next is eof) && cmp_tok(next: tok, limit)); next = nxttk(f)?){
        expct(next is opr || next is eol, next, f,
            void: EXPECTD, "operator or end of expression")?;
        if(next is opr){
            // cast value
            if(next: opr == opr::CASTTOTP){
                next = nxttk(f)?;
                const cast = expct(is_type(next), next, f, void: EXPECTD,
                    "valid casting type")?: kwd;

                expct(castable(expr_t, cast), cast, f, void: EXPECTD,
                    "valid casting", cast_err(expr_t, cast))?: kwd;
                // TODO: actually cast values
                expr_t = cast;
                continue;
            };
            const tmp = alloc(*f);
            const (exp, tp) = parse_opr(f, next: opr, expr_t, scp, add)?;
            
            expct(is_subt(tp, expr_t), next, tmp, void: MISMTCH,
                "member types", cast_err(tp, expr_t))?;
            free(tmp);
            out = strings::concat(out, exp);
        };
    };
    assert(expr_t != kwd::NUMBER_T);
    return (out, expr_t);
};

fn parse_asg(f: *file, dest: idt, scp: *scope, defn: bool = false, limit: tok = eol) ((str, kwd) | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing assignment to \"{}\"", dest)!;

    let next = nxttk(f)?;
    let defn = false;
    const oper = expct(next is opr, next,
            f, void: EXPECTD, "assigment")?: opr;
    const dup = alloc(*f);
    switch(oper){
        case opr::ASSIGNMT =>
            defn = true;
        case opr::INCREMNT, opr::DECREMNT =>
            void;
        case =>
            return unimsg {
                msg = "assignment operator",
                tip = void,
                ptr = f,
            }: INVALID;
        };
    let out = "";
    let add = []: []idref;
    const nm_def =
        match(get_idt(dest, f, scp)){
        case let nm: *nmsp =>
            yield nm;
        case *func => void; // case handled by parse_glob
        case => void;
        };
    let dest_t =
        match(nm_def){
        case void => yield kwd::NOT_KWRD;
        case let nm: *nmsp => yield nm.vtype;
        };
    let expr_t = kwd::NOT_KWRD;
    next = nxttk(f)?;
    // TODO: handle idt, opr, "+" | "-" | "~"
    // TODO: handle literals of records and lists
    // TODO: handle statements as valid hands
    const vall = expct(next is num || next is txt || next is idt || next is kwd,
        next, f, void: EXPECTD, "valid righthand")?;
    match(vall){
    case let n: num =>
        if(!defn){
            out = fmt::asprintf("    %.val =w copy {}\n", n: u32);
        } else {
            out = fmt::asprintf("    storew {}, %{}\n", n: u32, dest);
        };
        expr_t = cast_to(expr_t, kwd::U32_TYPE, vall, f)?;
    case let t: txt => void;
        const val = tostr(t);
        const idx = pushstr(val);
        out = fmt::asprintf("    %.val =l copy {}\n", idx);

        finsh(f, void: CANT_DO, "perform operations on string literals")?;
        expct(is_subt(kwd::STRING_T, dest_t), vall, dup, void: MISMTCH, "member types",
            cast_err(kwd::STRING_T, dest_t))?;
        return (out, kwd::STRING_T);

    case let i: idt => void;
        match(get_idt(i: str, f, scp)?){
        case let nm: *nmsp =>
            pushref(i: str, f, scp, &add)?;
            out = fmt::asprintf("    %.val ={0} copy %{1}.v\n", tptob(nm.vtype), i: str);
            expr_t = cast_to(nm.vtype, expr_t, vall, f)?;
            // TODO: assert for composite types
        case let fun: *func =>
            const (refs, exp) = parse_fcall(fun, f, scp)?;
            append(add, (*refs)...);
            free(refs);

            if(!defn){
                expct(is_subt(dest_t, fun.retrn), i, dup, void: MISMTCH,
                    "member types", cast_err(dest_t, fun.retrn))?;
                out = fmt::asprintf("    %.val ={} {}\n", tptob(fun.retrn), exp);
            } else {
                out = fmt::asprintf("    %.val ={0} {1}\n    store{0} %.val, %{2}\n", tptob(fun.retrn), exp, dest);
            };
            expr_t = cast_to(fun.retrn, expr_t, vall, f)?;
        };
    case let k: kwd =>
        if(k == kwd::FUNCTION){
            if(dest_t != kwd::NOT_KWRD){
                return bi_msg {
                    lft = dest,
                    rgt = get_idpos(nm_def: *nmsp),
                    tip = void,
                    ptr = f,
                }: IDTCDUP;
            };
            if(defn){
                out = parse_fun(f, dest, scp)?;
                return (out, k);
            };
            return unimsg {
                msg = "perform arithmetic operations on functions",
                tip = void,
                ptr = f,
            }: CANT_DO;
        };
        return bi_msg {
            lft = "valid righthand",
            rgt = tktostr(k, true),
            tip = void,
            ptr = f,
        }: EXPECTD;
    };
    // keep reading until end of expression
    next = nxttk(f)?;
    for(!(!(next is eof) && cmp_tok(next: tok, limit)); next = nxttk(f)?){
        expct(next is opr || next is eol, next, f,
            void: EXPECTD, "operator or end of expression")?;
        if(next is opr){
            // cast value
            if(next: opr == opr::CASTTOTP){
                next = nxttk(f)?;
                const cast = expct(is_type(next), next, f, void: EXPECTD,
                    "valid casting type")?: kwd;

                expct(castable(expr_t, cast), cast, f, void: EXPECTD,
                    "valid casting", cast_err(expr_t, cast))?: kwd;
                // TODO: actually cast values
                expr_t = cast;
                continue;
            };
            const tmp = alloc(*f);
            const (exp, tp) = parse_opr(f, next: opr, expr_t, scp, &add)?;
            
            expct(is_subt(tp, expr_t), next, tmp, void: MISMTCH,
                "member types", cast_err(tp, expr_t))?;
            free(tmp);
            out = strings::concat(out, exp);
        };
    };
    assert(expr_t != kwd::NUMBER_T);
    expct(is_subt(expr_t, dest_t), oper, dup,
        void: MISMTCH, "member types", cast_err(expr_t, dest_t))?;
    free(dup);

    if(dest_t == kwd::NOT_KWRD) dest_t = expr_t;

    let hdr = "";
    const max = len(add);
    for(let i = 0z; i < max; i += 1){
        hdr = fmt::asprintf("{0}    %{1}.v ={2} load{2} %{1}\n",
            hdr, add[i].idt, tptob(add[i].vtp));
    };
    return (strings::concat(hdr, out), expr_t);
};

fn parse_opr(f: *file, oper: opr, tp: kwd, scp: *scope, add: *[]idref) ((str, kwd) | CMP_ERR) = {
    let next = nxttk(f)?;
    const rgth = expct(next is num || next is idt, next, f,
        void: EXPECTD, "numeric literal or identifier")?;

    static const inst =
        [ "neg", "and", "or"
        , "sar", "shl", "ceq", "cne"
        , "clt", "cgt", "cle", "cge"
        , "add", "sub", "mul", "div", "rem"
        ];
    match(rgth){
    case let n: num =>
        if(is_subt(tp, kwd::NUMBER_T)){
            const exp = fmt::asprintf("    %.val ={} {} %.val, {}\n",
                tptob(tp), inst[oper], n: u32);
            return (exp, tp);
        } else {
            return unimsg {
                msg = "member types",
                tip =  cast_err(tp, kwd::NUMBER_T),
                ptr = f,
            }: MISMTCH;
        };
    case let i: idt =>
        if(is_subt(tp, kwd::NUMBER_T)){
            pushref(i: str, f, scp, add)?;
            const exp = fmt::asprintf("    %.val ={} {} %.val, %{}.v\n",
                tptob(tp), inst[oper], i: str);
            return (exp, tp);
        } else {
            return unimsg {
                msg = "member types",
                tip =  cast_err(tp, kwd::NUMBER_T),
                ptr = f,
            }: MISMTCH;
        };
    case =>
        return ("righthand should be number or identifier", f): UNREACH;
    };
};

fn parse_fun(f: *file, dest: idt, scp: *scope, skip: bool = false) (str | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing function \"{}\" at {}:{}:{}",
            dest: str, f.name, f.lin + 1, f.cln + 1)!;

    let out = "";
    let next = nxttk(f)?;
    expct(cmp_tok(next, sym::OPEN_PAR), next, f, void: EXPECTD,
        "function parameter list declaration")?;

    let params = []: []kwd;
    let parm_n = []: []idt;
    let defs = []: []*nmsp;
    let swtch = false;

    next = nxttk(f)?;
    const args = alloc(*f);
    // parse parameter list
    for(!cmp_tok(next, sym::CLOSEPAR); next = nxttk(f)?){
        if(!swtch){
            const prm = expct(next is idt, next, f,
                void: EXPECTD, "function parameter definition")?: idt;
            const cln = f.cln;
            
            append(parm_n, prm);

            next = nxttk(f)?;
            expct(cmp_tok(next, opr::CASTTOTP), next, f, void: EXPECTD,
                "parameter type definition")?;
            
            next = nxttk(f)?;
            const tp = expct(is_type(next), next, f, void: EXPECTD,
                "parameter type definition")?: kwd;

            append(params, tp);
            append(defs, alloc(nmsp {
                ident = prm,
                vtype = tp,
                mutbl = false,
                asgnd = true,
                param = true,
                orign = f.name,
                lin = f.lin,
                cln = cln,
            }));
            swtch = true;
        } else {
            expct(cmp_tok(next, sym::SYMCOMMA),
                next, f, void: EXPECTD, "comma or end of parameter list definition")?;
            swtch = false;
        };
    };
    
    next = nxttk(f)?;
    expct(cmp_tok(next, opr::CASTTOTP), next, f, void: EXPECTD,
        "function return type declaration")?;
    
    next = nxttk(f)?;
    const dup = alloc(*f);
    const ret = expct(is_type(next), next, f, void: EXPECTD,
        "valid function return type")?: kwd;
    
    if(skip){
        push_fun(dest, dup, params, parm_n, ret, scp)?;
        jmpto(sym::OPN_CRLY, f)?;
        mtchs(sym::OPN_CRLY, f, false)?;
        return "";
    };

    // TODO: effect tags
    // TODO: enforce 0 parameters for main
    if(dest: str == "main"){
        expct(len(defs) == 0, dest, args, void: GENERIC,
            "the main function recieves no arguments")?;

        if(ret == kwd::UNITTYPE){
            // TODO: implement ctxt variable here
            let fn_scp = scope {
                over = scp,
                defs = [],
                funs = [],
            };
            next = nxttk(f)?;
            const bgn = expct(cmp_tok(next, sym::OPN_CRLY), next, f, void: EXPECTD,
                "function body declaration")?: sym;

            const (body, ret_tp) = parse(f, &fn_scp, mtchs(bgn, f)?)?;
            expct(cmp_tok(ret_tp, kwd::UNITTYPE), ret_tp, dup, void: GENERIC,
                "the expected return type for main is `unit`")?;
            free(dup);

            out = fmt::asprintf("function $main(){{\n@start\n{}    call $exit(l 0)\n    ret\n}}\n", body);
        } else {
            return unimsg {
                msg = "main function must be of `unit` type",
                tip = fmt::asprintf("you defined it as `{}`", kwdv[ret]),
                ptr = f,
            }: GENERIC;
        };
    } else {
        // TODO: implement ctxt variable here
        let fn_scp = scope {
            over = scp,
            defs = defs,
            funs = [],
        };
        next = nxttk(f)?;
        const bgn = expct(cmp_tok(next, sym::OPN_CRLY), next, f, void: EXPECTD,
            "function body declaration")?: sym;

        const (body, ret_tp) = parse(f, &fn_scp, mtchs(bgn, f)?)?;
        expct(is_subt(ret_tp, ret), ret_tp, dup, void: MISMTCH,
            "function return type and body type", cast_err(ret_tp, ret))?;
        free(dup);

        const (prml, prmd) = gen_params(params, parm_n);
        out = fmt::asprintf("function {} ${}({}){{\n@start\n{}{}}}\n", tptob(ret), dest, prml, prmd, body);
    };
    return out;
};

fn gen_params(param_t: []kwd, param_n: []idt) (str, str) = {
    let param_lst = "";
    let param_def = "";

    const max = len(param_t);
    assert(max == len(param_n));
    for(let arg = 0z; arg < max; arg += 1){
        if(arg == 0){
            param_lst = fmt::asprintf("{} %{}.v",
                tptob(param_t[arg]), param_n[arg]);
        } else {
            param_lst = fmt::asprintf("{}, {} %{}.v", param_lst,
                tptob(param_t[arg]), param_n[arg]);
        };
        param_def = fmt::asprintf("{0}    %{1} =l alloc4 {2}\n    store{3} %{1}.v, %{1}\n",
            param_def, param_n[arg], tptoz(param_t[arg]), tptob(param_t[arg]));
    };
    return (param_lst, param_def);
};

fn is_type(_tp: (tok | eof)) bool = {
    if(!(_tp is kwd)) return false;
    const tp = _tp: kwd;
    switch(tp){
    case kwd::U8__TYPE, kwd::U16_TYPE, kwd::U32_TYPE, kwd::U64_TYPE, kwd::I8__TYPE,
        kwd::I16_TYPE, kwd::I32_TYPE, kwd::I64_TYPE, kwd::RATIO__T, kwd::STRING_T, kwd::UNITTYPE =>
        return true;
    case => return false;
    };
};

fn is_subt(tp: kwd, set: kwd) bool = {
    switch(set){
    case kwd::RAW_TYPE =>
        return tp == set;
    case kwd::U8__TYPE, kwd::U16_TYPE, kwd::U32_TYPE,
        kwd::U64_TYPE =>
        return is_num(tp) && tp <= set || tp == kwd::NUMBER_T;
    case kwd::I8__TYPE, kwd::I16_TYPE, kwd::I32_TYPE,
        kwd::I64_TYPE, kwd::NUMBER_T =>
        if(is_num(tp)) return tp < set - stou;
        if(is_num(tp, true)) return tp <= set;
        return  tp == kwd::NUMBER_T;
    case kwd::ARRAY__T, kwd::STRING_T =>
        return tp == set;
    case kwd::NOT_KWRD =>
        return true;
    case =>
        assert(false);
        return false;
    };
};

fn castable(s: kwd, d: kwd) bool = {
    if(s == kwd::NOT_KWRD || s == kwd::RAW_TYPE) return true;
    if((is_num(s) || is_num(d, true)) &&
        (is_num(s) || is_num(d, true))) return true;
    return s == d;
};

fn cast_to(s: kwd, d: kwd, t: tok, f: *file) (kwd | CMP_ERR) = {
    if(s == kwd::NOT_KWRD){
        return d;
    } else {
        expct(is_subt(s, d), t, f, void: MISMTCH,
            "member types", cast_err(s, d))?;
        if(d != kwd::NOT_KWRD) return d;
        return s;
    };
};

fn cast_err(s: kwd, d: kwd) str = {
    assert(s != kwd::NOT_KWRD);
    // result will never be used
    if(d == kwd::NOT_KWRD) return "";
    const src =
        if(s == kwd::NUMBER_T){
            yield "numberical type";
        } else if(s == kwd::STRING_T){
            yield "string";
        } else if(s == kwd::ARRAY__T){
            yield "list";
        } else {
            yield kwdv[s];
        };
    const dst =
        if(d == kwd::NUMBER_T){
            yield "numberical type";
        } else if(d == kwd::STRING_T){
            yield "string";
        } else if(d == kwd::ARRAY__T){
            yield "list";
        } else {
            yield kwdv[d];
        };
    return fmt::asprintf("source type is {}, but dest type is {}", src, dst);
};

fn is_num(tp: kwd, sign: bool = false) bool = {
    if(tp == kwd::NUMBER_T) return true;
    if(!sign){
        return kwd::U8__TYPE <= tp && tp <= kwd::U64_TYPE;
    } else {
        return kwd::I8__TYPE <= tp && tp <= kwd::I64_TYPE;
    };
};
