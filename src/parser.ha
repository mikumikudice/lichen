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
    case kwd::RATIO__T =>
        return "0"; // TODO
    case kwd::STRING_T, kwd::ARRAY__T =>
        return "$empty.arr";
    case kwd::UNITTYPE =>
        return "0xcafe0000";
    case =>
        return "0";
    };
};

// converts moss types to qbe types i.e. type length
fn get_qbe_t(vtp: kwd, mode: int = 0) str = {
    if(mode == 1)
    if(vtp == kwd::U8__TYPE || vtp == kwd::I8__TYPE ||
        vtp == kwd::U16_TYPE || vtp == kwd::I16_TYPE){
        return "w";
    };
    switch(vtp){
    case kwd::U8__TYPE, kwd::I8__TYPE =>
        if(mode == 2) return "ub";
        return "b";
    case kwd::I16_TYPE, kwd::U16_TYPE =>
        if(mode == 2) return "uh";
        return "h";
    case kwd::U32_TYPE, kwd::I32_TYPE,
        kwd::NOT_KWRD, kwd::NUMBER_T =>
        if(mode == 2) return "uw";
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
fn get_t_len(vtp: kwd) str = {
    switch(vtp){
    case kwd::U8__TYPE, kwd::I8__TYPE =>
        return "1";
    case kwd::I16_TYPE, kwd::U16_TYPE =>
        return "2";
    case kwd::U32_TYPE, kwd::I32_TYPE =>
        return "4";
    case kwd::U64_TYPE, kwd::I64_TYPE, kwd::RATIO__T,
        kwd::STRING_T, kwd::ANY_TYPE, kwd::RAW_TYPE,
        kwd::UNITTYPE, kwd::ARRAY__T, kwd::NUMBER_T  =>
        return "8";
    case =>
        assert(false);
        return "";
    };
};

fn get_t_tag(vtp: kwd) str = {
    switch(vtp){
    case kwd::UNITTYPE =>
        return "$t.unt";
    case kwd::STRING_T =>
        return "$t.str";
    case kwd::ARRAY__T =>
        return "$t.arr";
    case kwd::RECORD_T =>
        return "$t.rec";
    case kwd::FUNCTION =>
        return "$t.fun";
    case =>
        return "$t.num";
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
    datasec = fmt::asprintf("{}data $.{} = {{ l {}, b \"{}\" }}\n",
        datasec, max, truelen(l), l);
    return fmt::asprintf("$.{}", max);
};

fn cmp_orign(ths: (str | kernel), tht: (str | kernel)) bool = {
    if(ths is str && tht is str) return ths: str == tht: str;
    if(ths is kernel && tht is kernel) return ths: kernel == tht: kernel;
    return false;
};

fn pushref(nm : *nmsp, f: *file, scp: *scope, add: *[]idref) (kwd | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("pushing new reference to \"{}\" at {}", nm.ident, gen_pos(f))!;

    const max = len(add);
    // value is already loaded
    if(nm.param) return nm.vtype;

    for(let i = 0z; i < max; i += 1){
        if(add[i].idt == nm.ident && cmp_orign(add[i].orign, nm.orign)){
            return add[i].vtp;
        };
    };
    append(add, idref {
        idt = nm.ident,
        vtp = nm.vtype,
        orign = nm.orign
    });
    return nm.vtype;
};

fn solve_ref(refs: *[]idref) str = {
    let hdr = "";
    const max = len(refs);
    for(let i = 0z; i < max; i += 1){
        if(refs[i].orign is kernel){
            hdr = fmt::asprintf("{0}    %{1}.{2}.g ={3} load{3} ${1}\n",
                hdr, refs[i].idt, get_qbe_t(refs[i].vtp), get_qbe_t(refs[i].vtp, 1));
        } else {
            hdr = fmt::asprintf("{0}    %{1}.{2} ={3} load{3} %{1}\n",
                hdr, refs[i].idt, get_qbe_t(refs[i].vtp), get_qbe_t(refs[i].vtp, 1));
        };
    };
    return hdr;
};

fn get_idpos(id: (*nmsp | *func)) str = {
    match(id){
    case let var: *nmsp =>
        match(var.orign){
        case let fname: str =>
            return fmt::asprintf("{}:{}:{}", fname, var.lin + 1, var.cln + 1);
        case let kid: kernel =>
            return fmt::asprintf("the {} kernel", krnls[kid]);
        };
    case let fun: *func =>
        match(fun.orign){
        case let fname: str =>
            return fmt::asprintf("{}:{}:{}", fname, fun.lin + 1, fun.cln + 1);
        case let kid: kernel =>
            return fmt::asprintf("the {} kernel", krnls[kid]);
        };
    };
};

fn push_idt(nm: idt, mut: bool, tp: kwd, f: *file, scp: *scope) (*nmsp | IDTCDUP) = {
    if(stacktrace)
        fmt::printfln("pushing identifier \"{}\" at {}", nm, gen_pos(f))!;

    match(get_idt(nm, f, scp, true)){
    case let var: *nmsp =>
        return bi_msg {
            lft = nm: str,
            rgt = get_idpos(var),
            tip = void,
            ptr = f,
        }: IDTCDUP;
    case let fun: *func =>
        return bi_msg {
            lft = nm: str,
            rgt = get_idpos(fun),
            tip = void,
            ptr = f,
        }: IDTCDUP;
    case =>
        const new = alloc(nmsp {
            ident = nm: str,
            vtype = tp,
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

fn get_idt(nm: idt, f: *file, scp: *scope, nomods: bool = false) (*nmsp | *func | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("getting identifier \"{}\" at {}", nm, gen_pos(f))!;

    let next = nxttk(f, true)?;
    if(cmp_tok(next, opr::MODFIELD)){
        return parse_field(nm, f, scp)?;
    };
    setptr(f, true);

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
        fmt::printfln("pushing function \"{}\" at {}", name, gen_pos(f))!;
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
                fmt::printfln("parsing function at {}", gen_pos(_f))!;
            yield _f;
        };
    const max = len(f.src);

    for(f.ptr < max){
        let next = nxttk(f)?;
        if(next is eol) continue;

        match(next: tok){
        case let k: kwd =>
            switch(k){
            // "pub", [ "type", ] idt, "=", expr
            case kwd::PUBFIELD =>
                if(stacktrace)
                    fmt::printfln("parsing pubdef at {}", gen_pos(f))!;
                if(!(scp.over is void)){
                    return unimsg {
                        msg = "export public fields within functions",
                        tip = "try moving it to the global scope",
                        ptr = f,
                    }: CANT_DO;
                };
                next = nxttk(f)?;
                const i = expct(next is idt, next, f, void: EXPECTD,
                    "type or variable definition")?: idt;

                next = nxttk(f, true)?;
                if(is_asg_opr(next)){
                    setptr(f, true);
                    const asg = parse_asg(f, i, next: opr, scp)?;
                    out = fmt::asprintf("{}export {}", out, asg);
                } else if(cmp_tok(next, opr::CASTTOTP)){
                    todo(f, "typedefs")?;
                } else {
                    return bi_msg {
                        lft = "namespace definition",
                        rgt = tktostr(next, false),
                        tip = void,
                        ptr = f,
                    }: EXPECTD;
                };
            case kwd::DMUTABLE =>
                if(stacktrace)
                    fmt::printfln("parsing mutdef at {}", gen_pos(f))!;
                next = nxttk(f)?;
                const i = expct(next is idt,
                    next, f, void: EXPECTD, "variable definition")?: idt;

                const asg = parse_asg(f, i, next: opr, scp, void, true)?;
                out = fmt::asprintf("{}{}", out, asg);
            case kwd::USE__MOD =>
                if(stacktrace)
                    fmt::printfln("parsing mod req at {}", gen_pos(f))!;
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
                                    retrn = kwd::U32_TYPE,
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
                if(stacktrace)
                    fmt::printfln("parsing return at {}", gen_pos(f))!;
                let add = []: []idref;
                const dup = alloc(*f);
                const (exp, expr_t, val_id) = parse_exp(f, scp, &add)?;
                
                if(ret_tp == kwd::UNITTYPE){
                    ret_tp = expr_t;
                } else {
                    expct(is_subt(expr_t, ret_tp), expr_t, dup, void: MISMTCH,
                        "return types", "union types are not implemented yet")?;
                };
                free(dup);
                out = fmt::asprintf("{}{}{}    ret %.val.{}\n", out, solve_ref(&add), exp, val_id);
            case =>
                todo(f, "uncovered rule")?;
            };
        case let i: idt =>
            next = nxttk(f, true)?;
            // TODO: handle typedefs
            const oper = expct(next is opr || cmp_tok(next, sym::OPEN_PAR), next, f, void: EXPECTD,
                "declaration, assignment or function call")?;

            if(is_asg_opr(oper) || cmp_tok(oper, opr::CASTTOTP)){
                setptr(f, true);
                let refs = []: []idref;
                match(get_idt(i, f, scp)){
                case =>
                    const asg = parse_asg(f, i, next: opr, scp)?;
                    out = fmt::asprintf("{}{}", out, asg);
                case let nm: *nmsp =>
                    const asg = parse_asg(f, i, next: opr, scp, nm)?;
                    out = fmt::asprintf("{}{}", out, asg);
                case let fun: *func =>
                    if(fun.orign is kernel){
                        skip_field(f)?;
                        const call = parse_fcall(fun, f, scp, &refs)?;
                        out = fmt::asprintf("{}{}    {}\n", out, solve_ref(&refs), call);
                        continue;
                    };
                    next = nxttk(f, true)?;
                    if(is_asg_opr(next)){
                        setptr(f, true);
                        const asg = parse_asg(f, i, next: opr, scp, fun)?;
                        out = fmt::asprintf("{}{}", out, asg);
                    } else {
                        setptr(f, true);
                        const call = parse_fcall(fun, f, scp, &refs)?;
                        out = fmt::asprintf("{}{}    {}\n", out, solve_ref(&refs), call);
                    };
                };
            } else {
                setptr(f, true);
                let refs = []: []idref;
                const id = get_idt(i, f, scp)?;
                expct(id is *func, i, f, void: NOTCALL, i)?;
                const fun = id: *func;
                if(fun.orign is kernel){
                    skip_field(f)?;
                };
                const call = parse_fcall(fun, f, scp, &refs)?;
                out = fmt::asprintf("{}{}    {}\n", out, solve_ref(&refs), call);
            };
        case let s: sym =>
            switch(s){
            case sym::CLS_CRLY =>
                if(stop > 0 && f.ptr >= stop){
                    if(stacktrace)
                        fmt::printfln("end of scope at {}", gen_pos(f))!;
                    break;
                };
            case =>
                todo(f, fmt::asprintf("uncovered symbol {}", tktostr(s, true)))?;
            };
        case =>
            todo(f, "uncovered statement")?;
        };
    };
    if(scp.over is void){
        return (strings::concat(datasec, out), kwd::NOT_KWRD);
    };
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

fn parse_fcall(fun: *func, f: *file, scp: *scope, refs: *[]idref) (str | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing function call at {}", gen_pos(f))!;

    let out = fmt::asprintf("call ${}(", fun.fname);
    let hdr ="";
    let next = nxttk(f)?;
    expct(cmp_tok(next, sym::OPEN_PAR), next, f, void: EXPECTD,
        "function argument list")?;

    const limit = [ sym::SYMCOMMA, sym::CLOSEPAR ]: []tok;

    let argc = 0z;
    const argmax = len(fun.param);

    if(argmax == 0){
        next = nxttk(f)?;
        expct(cmp_tok(next, sym::CLOSEPAR), next, f, void: GENERIC, "too many parameters on function call",
            fmt::asprintf("the function \"{}\" takes {} arguments", fun.fname, argmax))?;
    };
    const max = len(f.src);
    for(f.ptr < max){
        next = nxttk(f, true)?;
        if(is_limit(next, limit)) break;
        setptr(f, true);

        const (exp, tp, arg) = parse_exp(f, scp, refs, limit)?;
        if(argc == 0){
            out = fmt::asprintf("{}{} {}", out, get_qbe_t(tp, 1), arg);
        } else {
            out = fmt::asprintf("{}, {} {}", out, get_qbe_t(tp, 1), arg);
        };
        hdr = fmt::asprintf("{}{}\n", hdr, exp);
        argc += 1;
        if(argc > argmax){
            next = nxttk(f)?;
            expct(cmp_tok(next, sym::CLOSEPAR), next, f, void: GENERIC, "too many parameters on function call",
                fmt::asprintf("the function \"{}\" takes {} arguments", fun.fname, argmax))?;
        };
    };
    for(argc < argmax; argc += 1){
        // TODO: default values for function parameters
        if(argc == 0){
            out = fmt::asprintf("{}{} {}", out, get_qbe_t(fun.param[argc]), getdefval(fun.param[argc]));
        } else {
            out = fmt::asprintf("{}, {} {}", out, get_qbe_t(fun.param[argc]), getdefval(fun.param[argc]));
        };
    };
    return strings::concat(out, ")");
};

fn parse_asg(f: *file, dest: idt, oper: opr, scp: *scope, defn: (*nmsp | *func | void) = void, mutbl: bool = false) (str | CMP_ERR) = {
    if(stacktrace){
        if(defn is void){
            fmt::printfln("parsing assignment to \"{}\" at {}", dest, gen_pos(f))!;
        } else {
            fmt::printfln("parsing definition and assignment to \"{}\" at {}", dest, gen_pos(f))!;
        };
    };
    const global = scp.over is void;
    if(global && mutbl){
        return unimsg {
            msg = "define mutable variables at global scope",
            tip = "try moving it to inside a function",
            ptr = f,
        }: CANT_DO;
    };
    let out = "";
    let next = nxttk(f)?;
    const oper = expct(next is opr, next, f, void: EXPECTD,
        "declaration or assignment")?: opr;

    const dup = alloc(*f);

    switch(oper){
    case opr::CASTTOTP =>
        if(!(defn is void)){
            return bi_msg {
                lft = dest: str,
                rgt = get_idpos(defn: (*nmsp | *func)),
                tip = void,
                ptr = dup,
            }: IDTCDUP;
        };
        next = nxttk(f)?;
        const tp = expct(is_type(next), next, f, void: EXPECTD,
            "valid type notation")?: kwd;

        push_idt(dest, mutbl, tp, f, scp)?;
        out = fmt::asprintf("    %{0} =l alloc4 {1}\n    store{2} {3}, %{0}\n",
            dest: str, get_t_len(tp), get_qbe_t(tp), getdefval(tp));

        // TODO: typedefs
    case opr::ASSIGNMT =>
        next = nxttk(f, true)?;
        if(cmp_tok(next, kwd::FUNCTION)){
            if(!global){
                return unimsg {
                    msg = "define local functions",
                    tip = "it's planned to add local-scope functions, but it's not implemented yet",
                    ptr = dup,
                }: CANT_DO;
            };
            return parse_fun(f, dest, scp)?;
        } else {
            setptr(f, true);
        };
        let refs = []: []idref;
        const (exp, tp, val_id) = parse_exp(f, scp, &refs)?;
        
        if(defn is void){
            expct(tp != kwd::NUMBER_T, oper, dup, void: GENERIC,
                "untyped definition of namespace")?;

            const nm = push_idt(dest, mutbl, tp, f, scp)?;
            nm.asgnd = true;
            out = fmt::asprintf("    %{} =l alloc4 {}\n", dest: str, get_t_len(tp));
        } else {
            match(defn){
            case let nm: *nmsp =>
                if(nm.asgnd && !nm.mutbl){
                    return unimsg {
                        msg = "redefine a value of a immutable variable",
                        tip = void,
                        ptr = dup,
                    }: CANT_DO;
                };
                nm.asgnd = true;
                expct(is_subt(tp, nm.vtype), oper, dup, void: MISMTCH,
                    "destination and expression result types", cast_err(tp, nm.vtype))?;
            case =>
                assert(false);
            };
        };
        out = fmt::asprintf("{}{}{}    store{} {}, %{}\n",
            out, solve_ref(&refs), exp, get_qbe_t(tp), val_id, dest);
    case =>
        return bi_msg {
            lft = "declaration or assignment",
            rgt = tktostr(oper),
            tip = void,
            ptr = dup,
        }: EXPECTD;
    };
    free(dup);
    return out;
};

fn parse_exp(f: *file, scp: *scope, refs: *[]idref, limit: []tok = [eol]) ((str, kwd, str) | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing expression at {}", gen_pos(f))!;
    let out = "";
    let single = true;
    let expr_t = kwd::NOT_KWRD;
    let next = nxttk(f)?;

    let dest = "";

    // TODO: handle idt, opr, "+" | "-" | "~"
    // TODO: handle literals of records and lists
    // TODO: handle statements as valid hands
    const vall = expct(next is num || next is txt || next is idt,
        next, f, void: EXPECTD, "valid operand")?: (num | txt | idt);
    match(vall){
    case let n: num =>
        out = fmt::asprint(n: u64);
        expr_t = parse_cast(f, kwd::NUMBER_T)?;

    case let t: txt =>
        const val = tostr(t);
        const idx = pushstr(val);
        out = idx;
        
        next = nxttk(f, true)?;
        // TODO: acept casting to union types
        expct(is_limit(next, limit), next, f, void: EXPECTD,
            "end of expression")?;
        setptr(f, true);
        return ("", kwd::STRING_T, idx);

    case let i: idt =>
        match(get_idt(i: str, f, scp)?){
        case let nm: *nmsp =>
            pushref(nm, f, scp, refs)?;
            if(nm.orign is kernel){
                skip_field(f)?;
                expr_t = parse_cast(f, nm.vtype)?;
                out = fmt::asprintf("%{}.{}.g", nm.ident, get_qbe_t(nm.vtype));
            } else {
                expr_t = parse_cast(f, nm.vtype)?;
                out = fmt::asprintf("%{}.{}", nm.ident, get_qbe_t(nm.vtype));
            };
            dest = fmt::asprintf("%val.{}", get_qbe_t(expr_t, 1));
            // TODO: assert for composite types
        case let fun: *func =>
            if(fun.orign is kernel){
                skip_field(f)?;
            };
            out = parse_fcall(fun, f, scp, refs)?;
            expr_t = fun.retrn;
        };
    };
    next = nxttk(f)?;
    if(is_limit(next, limit)){
        return ("", expr_t, out);
    };
    // keep reading until end of expression
    for(!is_limit(next, limit); next = nxttk(f)?){
        expct(next is opr || next is eol, next, f,
            void: EXPECTD, "operator or end of expression")?;
        if(next is opr){
            // cast value
            if(next: opr == opr::CASTTOTP){
                next = nxttk(f)?;
                const cast = expct(is_type(next), next, f, void: EXPECTD,
                    "valid casting type")?: kwd;

                expr_t = cast_to(expr_t, cast, next, f)?;
                if(single){
                    dest = fmt::asprintf("%val.{}", get_qbe_t(expr_t, 1));
                };
                continue;
            };
            const tmp = alloc(*f);
            const (exp, tp) = parse_opr(f, next: opr, expr_t, scp, refs)?;

            expr_t = cast_to(expr_t, tp, next, tmp)?;
            free(tmp);

            if(single){
                dest = fmt::asprintf("%val.{}", get_qbe_t(expr_t, 1));
                out = fmt::asprintf("    {} ={} copy {}\n{}",
                    dest, get_qbe_t(expr_t, 1), out, exp);
                single = false;
            } else {
                out = strings::concat(out, exp);
            };
        };
    };
    return (out, expr_t, dest);
};

fn parse_opr(f: *file, oper: opr, expr_t: kwd, scp: *scope, refs: *[]idref) ((str, kwd) | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing operation at {}", gen_pos(f))!;
    static const inst =
        [ "neg", "and", "or"
        , "sar", "shl"
        , "ceq", "cneq"
        , "cls", "cgt"
        , "cle", "cge"
        , "add", "sub", "mul", "div", "rem"
        ];
    let next = nxttk(f)?;
    const rgth = expct(next is num || next is idt, next, f,
        void: EXPECTD, "numeric literal or identifier")?;
    
    const val_id = fmt::asprintf("%val.{}", get_qbe_t(expr_t, 1));
    const asg_tp = get_qbe_t(expr_t, 1);

    if(is_cmp(oper)){
        todo(f, "comparisons")?;
        return ("", expr_t);
    };
    match(rgth){
    case let n: num =>
        if(opeable(kwd::NUMBER_T, expr_t, oper)){
            const exp = fmt::asprintf("    {0} ={1} {2} {0}, {3}\n",
                val_id, asg_tp, inst[oper], n: u64);
            return (exp, expr_t);
        } else {
            return unimsg {
                msg = "member types",
                tip =  cast_err(kwd::NUMBER_T, expr_t),
                ptr = f,
            }: MISMTCH;
        };
    case let i: idt =>
        match(get_idt(i: str, f, scp)?){
        case let nm: *nmsp =>
            pushref(nm, f, scp, refs)?;
            if(opeable(nm.vtype, expr_t, oper)){
                const (hdr, wrp) = fix_sizes(expr_t, nm);
                const exp = fmt::asprintf("{}    {} ={} {} {}, {}\n",
                    hdr, val_id, asg_tp, inst[oper], val_id, wrp);
                return (exp, nm.vtype);
            } else {
                return unimsg {
                    msg = "member types",
                    tip =  cast_err(nm.vtype, expr_t),
                    ptr = f,
                }: MISMTCH;
            };
        case let fun: *func =>
            if(opeable(fun.retrn, expr_t, oper)){
                const call = parse_fcall(fun, f, scp, refs)?;
                const wrp = fmt::asprintf("%{}.{}", fun.fname, get_qbe_t(fun.retrn));
                const exp = fmt::asprintf("    {} ={} {} {}, {}\n",
                    val_id, asg_tp, inst[oper], val_id, wrp);
                const out = fmt::asprintf("{}{}{}", solve_ref(refs), call, exp);
                return (out, fun.retrn);
            } else {
                return unimsg {
                    msg = "member types",
                    tip =  cast_err(fun.retrn, expr_t),
                    ptr = f,
                }: MISMTCH;
            };
        };
    case =>
        return ("righthand should be number or identifier", f): UNREACH;
    };
};

fn parse_fun(f: *file, dest: idt, scp: *scope, skip: bool = false) (str | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing function \"{}\" at {}", dest: str, gen_pos(f))!;

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

        let (body, ret_tp) = parse(f, &fn_scp, mtchs(bgn, f)?)?;
        expct(is_subt(ret_tp, ret), ret_tp, dup, void: MISMTCH,
            "function return type and body type", cast_err(ret_tp, ret))?;
        free(dup);

        if(ret_tp == kwd::UNITTYPE){
            body = fmt::asprintf("{}    %.ret =l copy {}\n    ret %.ret\n", body, 0xcafe0000);
        };
        const (prml, prmd) = gen_params(params, parm_n);
        out = fmt::asprintf("function {} ${}({}){{\n@start\n{}{}}}\n", get_qbe_t(ret, 1), dest, prml, prmd, body);
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
            param_lst = fmt::asprintf("{} %{}.{}", get_qbe_t(param_t[arg], 1),
                param_n[arg], get_qbe_t(param_t[arg]));
        } else {
            param_lst = fmt::asprintf("{}, {} %{}.{}", param_lst, get_qbe_t(param_t[arg], 1),
                param_n[arg], get_qbe_t(param_t[arg]));
        };
        param_def = fmt::asprintf("{0}    %{1} =l alloc4 {2}\n    store{3} %{1}.{3}, %{1}\n",
            param_def, param_n[arg], get_t_len(param_t[arg]), get_qbe_t(param_t[arg]));
    };
    return (param_lst, param_def);
};

fn is_limit(tkn: tok, lmt: []tok) bool = {
    for(let l .. lmt){
        if(cmp_tok(tkn, l)) return true;
    };
    return false;
};

// TODO: linear types
fn match_linear() bool = {
    return false;
};

// TODO: if/else & enhance operations' type checking
fn opeable(lft: kwd, rgt: kwd, oper: opr) bool = {
    switch(oper){
    case opr::BOOL_LSS, opr::BOOL_GRT, opr::BOOL_LEQ, opr::BOOL_GEQ =>
        return (is_num(lft) && is_num(rgt)) ||
            (is_num(lft, true) && is_num(rgt, true)) ||
            (lft == kwd::STRING_T && rgt == kwd::STRING_T) ||
            (lft == kwd::ARRAY__T && rgt == kwd::ARRAY__T);
    case =>
        return is_subt(lft, rgt) && is_subt(rgt, lft);
    };
};

fn fix_sizes(dest: kwd, nm: *nmsp) (str, str) = {
    let hdr = "";
    let val = fmt::asprintf("%{}.{}", nm.ident, get_qbe_t(nm.vtype));
    if(is_subt(dest, kwd::NUMBER_T) && dest != kwd::NUMBER_T){
        const chck =
            (is_num(dest) && dest > kwd::U32_TYPE) ||
            (is_num(dest, true) && dest > kwd::I32_TYPE);
        const smol = dest > nm.vtype;
        
        if(chck && smol){
            hdr = fmt::asprintf("%{}.l =l ext{1} {}", nm.ident, get_qbe_t(nm.vtype, 2), val);
            val = fmt::asprintf("%{0}.l", nm.ident);
        };
    };
    if(nm.orign is kernel){
        val = strings::concat(val, ".g");
    };
    return (hdr, val);
};

fn is_subt(tp: kwd, set: kwd) bool = {
    switch(set){
    case kwd::RAW_TYPE, kwd::ANY_TYPE =>
        return tp == set;
    case kwd::U8__TYPE, kwd::U16_TYPE, kwd::U32_TYPE,
        kwd::U64_TYPE =>
        return is_num(tp) && tp <= set || tp == kwd::NUMBER_T;
    case kwd::I8__TYPE, kwd::I16_TYPE, kwd::I32_TYPE,
        kwd::I64_TYPE =>
        if(is_num(tp)) return tp < set - stou;
        if(is_num(tp, true)) return tp <= set;
        return  tp == kwd::NUMBER_T;
    case kwd::ARRAY__T, kwd::STRING_T =>
        return tp == set;
    case kwd::NUMBER_T =>
        return is_num(tp);
    case kwd::NOT_KWRD =>
        return true;
    case =>
        assert(false);
        return false;
    };
};

fn parse_cast(f: *file, src: kwd) (kwd | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing cast of {}", src: int)!;
    let out_t = src;
    let next = nxttk(f, true)?;
    if(cmp_tok(next, opr::CASTTOTP)){
        next = nxttk(f)?;
        const cast = expct(is_type(next), next, f, void: EXPECTD,
            "valid casting type")?: kwd;
        out_t = cast_to(src, cast, next, f)?;
    } else {
        setptr(f, true);
    };
    return out_t;
};

fn cast_to(s: kwd, d: kwd, t: tok, f: *file) (kwd | CMP_ERR) = {
    if(s == kwd::NOT_KWRD){
        return d;
    } else {
        expct(castable(s, d), t, f, void: MISMTCH,
            "member types", cast_err(s, d))?;
        if(d != kwd::NOT_KWRD) return d;
        return s;
    };
};

fn castable(s: kwd, d: kwd) bool = {
    if(s == kwd::NOT_KWRD || s == kwd::RAW_TYPE) return true;
    if((is_num(s) || is_num(d, true)) &&
        (is_num(d) || is_num(s, true))) return true;
    return s == d;
};

fn cast_err(s: kwd, d: kwd) str = {
    assert(s != kwd::NOT_KWRD);
    // result will never be used
    if(d == kwd::NOT_KWRD) assert(false);
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

fn is_cmp(oper: opr) bool = {
    return oper == opr::BOOL_EQL || oper == opr::BOOL_DIF || oper == opr::BOOL_LSS ||
        oper == opr::BOOL_GRT || oper == opr::BOOL_LEQ || oper == opr::BOOL_GEQ;
};
