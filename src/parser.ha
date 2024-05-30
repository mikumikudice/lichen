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
    
    assert(castable(kwd::I8__TYPE, kwd::U64_TYPE) == true);
    assert(castable(kwd::STRING_T, kwd::I32_TYPE) == false);

    assert(need_ext(kwd::U32_TYPE, kwd::U64_TYPE) == true);
    assert(need_ext(kwd::I16_TYPE, kwd::U64_TYPE) == true);
    assert(need_ext(kwd::U8__TYPE, kwd::I64_TYPE) == true);
    assert(need_ext(kwd::I16_TYPE, kwd::U64_TYPE) == true);
    assert(need_ext(kwd::U8__TYPE, kwd::U32_TYPE) == false);
    assert(need_ext(kwd::U32_TYPE, kwd::U32_TYPE) == false);
    assert(need_ext(kwd::I64_TYPE, kwd::U8__TYPE) == false);
    assert(need_ext(kwd::I64_TYPE, kwd::U64_TYPE) == false);
    assert(need_ext(kwd::U64_TYPE, kwd::I64_TYPE) == false);

    assert(sign_mismtch(kwd::U64_TYPE, kwd::I64_TYPE) == true);
    assert(sign_mismtch(kwd::I8__TYPE, kwd::U64_TYPE) == true);
};

// returns the default value for each primitive type
fn getdefval(vtp: kwd) str = {
    switch(vtp){
    case kwd::RATIO__T =>
        return "0"; // TODO
    case kwd::STRING_T, kwd::ARRAY__T =>
        return "$empty.arr";
    case kwd::UNITTYPE =>
        return "$t.unt";
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
    if(mode == 2)
    if(vtp == kwd::U8__TYPE || vtp == kwd::U16_TYPE){
        return "uw";
    } else if(vtp == kwd::I8__TYPE || vtp == kwd::I16_TYPE){
        return "sw";
    };
    switch(vtp){
    case kwd::U8__TYPE =>
        if(mode == 2) return "ub";
        return "b";
    case kwd::I8__TYPE =>
        if(mode == 2) return "sb";
        return "b";
    case kwd::U16_TYPE =>
        if(mode == 2) return "uh";
        return "h";
    case kwd::I16_TYPE =>
        if(mode == 2) return "sh";
        return "h";
    case kwd::U32_TYPE =>
        if(mode == 2) return "uw";
        return "w";
    case kwd::I32_TYPE =>
        if(mode == 2) return "sw";
        return "w";
    case kwd::U64_TYPE =>
        if(mode == 2) return "ul";
        return "l";
    case kwd::I64_TYPE =>
        if(mode == 2) return "sl";
        return "l";
    case kwd::RATIO__T, kwd::STRING_T, kwd::ANY_TYPE,
        kwd::RAW_TYPE, kwd::UNITTYPE, kwd::ARRAY__T =>
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
    //if(len(l) == 0) return "$empty.arr";
    const max = len(str_lit);
    for(let i = 0z; i < max; i += 1){
        if(l == str_lit[i]){
            return fmt::asprintf("$.{}", i);
        };
    };
    append(str_lit, l);
    datasec = fmt::asprintf("{}data $.{} = {{ l {}, b \"{}\" }}\n",
        datasec, max, truelen(l) + 8, l);
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
            hdr = fmt::asprintf("{0}    %{1}.{2}.g ={2} load{2} ${1}\n",
                hdr, refs[i].idt, get_qbe_t(refs[i].vtp, 1));
        } else {
            hdr = fmt::asprintf("{0}    %{1}.{2} ={2} load{2} %{1}\n",
                hdr, refs[i].idt, get_qbe_t(refs[i].vtp, 1));
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

    match(get_idt(nm, f, scp)){
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

fn get_idt(nm: idt, f: *file, scp: *scope) (*nmsp | *func | CMP_ERR) = {
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
        return get_idt(nm, f, scp.over: *scope)?;
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
    match(get_idt(name, f, scp)){
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
fn parse(from: (str | *file), scp: *scope, stop: size = 0, fun_tp: kwd = kwd::UNITTYPE) ((str, kwd) | CMP_ERR) = {
    let out = "";
    let ret_tp = kwd::NOT_KWRD;
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
            case kwd::IF___BLK =>
                if(stacktrace)
                    fmt::printfln("parsing if block at {}", gen_pos(f))!;
                let if_scp = scope {
                    over = scp,
                    defs = [],
                    funs = [],
                };
                const endp = f.lin + 1;
                for(cmp_tok(next, kwd::IF___BLK)){
                    let refs = []: []idref;
                    let dup = alloc(*f);
                    const idx = dup.lin + 1;
                    const limit = [ sym::OPN_CRLY ]: []tok;
                    const (exp, _, chk) = parse_exp(f, &if_scp, &refs, limit)?;
                    nxttk(f)!;
                    const (body, if_tp) = parse(f, &if_scp, mtchs(sym::OPN_CRLY, f)?)?;
                    if(if_tp != kwd::UNITTYPE){
                        expct(is_subt(if_tp, ret_tp), if_tp, dup, void: MISMTCH,
                        "return types", "union types are not implemented yet")?;
                    };
                    free(dup);
                    out = fmt::asprintf("{0}{1}{2}    jnz {3}, @t.{4}, @f.{4}\n@t.{4}\n{5}    jmp @end.{6}\n@f.{4}\n",
                        out, solve_ref(&refs), exp, chk, idx, body, endp);
                    next = nxttk(f, true)?;
                    if(cmp_tok(next, kwd::ELSE_BLK)){
                        if(stacktrace)
                            fmt::printfln("parsing if block at {}", gen_pos(f))!;

                        if_scp.defs = []; // TODO: reset only to if-block defined variable
                        next = nxttk(f)?;
                        if(cmp_tok(next, kwd::IF___BLK)){
                            continue;
                        };
                        dup = alloc(*f);
                        expct(cmp_tok(next, sym::OPN_CRLY), next, f, void: EXPECTD,
                            "else body declaration")?;
                        const (body, el_tp) = parse(f, &if_scp, mtchs(sym::OPN_CRLY, f)?)?;
                        if(el_tp != kwd::UNITTYPE){
                            expct(is_subt(el_tp, ret_tp), el_tp, dup, void: MISMTCH,
                            "return types", "union types are not implemented yet")?;
                        };
                        out = strings::concat(out, body);
                        free(dup);
                    };
                    out = fmt::asprintf("{}@end.{}\n", out, endp);
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
                                    retrn = kwd::U32_TYPE,
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
                                [ func { // alloc = fn(size: u32) : raw
                                    fname = "alloc",
                                    param = [ kwd::U32_TYPE ],
                                    retrn = kwd::RAW_TYPE,
                                    ret_n = "",
                                    orign = kernel::MEM,
                                    ...
                                }
                                , func { // free = fn(obj : raw) : unit
                                    fname = "free",
                                    param = [ kwd::RAW_TYPE ],
                                    retrn = kwd::UNITTYPE,
                                    ret_n = "",
                                    orign = kernel::MEM,
                                    ...
                                }
                                , func { // copy = fn(dest : raw, src : raw, size : u64) : raw
                                    fname = "copy",
                                    param = [ kwd::RAW_TYPE, kwd::RAW_TYPE, kwd::U64_TYPE ],
                                    retrn = kwd::RAW_TYPE,
                                    ret_n = "",
                                    orign = kernel::MEM,
                                    ...
                                }
                                , func { // strlset = fnfn(dest : str, size : u64) : unit
                                    fname = "strlset",
                                    param = [ kwd::STRING_T, kwd::U64_TYPE ],
                                    retrn = kwd::UNITTYPE,
                                    ret_n = "",
                                    orign = kernel::MEM,
                                    ...
                                }
                                , func { // strcpy = fn(dest : str, src : sre, size : u64) : unit
                                    fname = "strcpy",
                                    param = [ kwd::STRING_T, kwd::STRING_T, kwd::U64_TYPE ],
                                    retrn = kwd::UNITTYPE,
                                    ret_n = "",
                                    orign = kernel::MEM,
                                    ...
                                }
                                , func { // memset = fn(dest : raw, src : u8, size : u64) : unit
                                    fname = "memset",
                                    param = [ kwd::RAW_TYPE, kwd::U8__TYPE, kwd::U64_TYPE ],
                                    retrn = kwd::UNITTYPE,
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
                expct(is_subt(expr_t, ret_tp), expr_t, dup, void: MISMTCH,
                    "return types", "union types are not implemented yet")?;
                ret_tp = expr_t;
                expr_t = cast_to(ret_tp, fun_tp, kwd::RETURNTO, dup)?;
                free(dup);
                // TODO: assert for size mismatches
                const wrp = fmt::asprintf("{}{}    %.ret ={} copy {}\n",
                    solve_ref(&add), exp, get_qbe_t(expr_t, 1), val_id);
                out = fmt::asprintf("{}{}    ret %.ret\n", out, wrp);
            case =>
                todo(f, fmt::asprintf("uncovered keyword: {}", kwdv[k]))?;
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
                        const (newexp, call) = parse_fcall(fun, f, scp, &refs)?;
                        out = fmt::asprintf("{}{}{}    {}\n", out, solve_ref(&refs), newexp, call);
                        continue;
                    };
                    next = nxttk(f, true)?;
                    if(is_asg_opr(next)){
                        setptr(f, true);
                        const asg = parse_asg(f, i, next: opr, scp, fun)?;
                        out = fmt::asprintf("{}{}", out, asg);
                    } else {
                        setptr(f, true);
                        const (newexp, call) = parse_fcall(fun, f, scp, &refs)?;
                        out = fmt::asprintf("{}{}{}    {}\n", out, solve_ref(&refs), newexp, call);
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
                const (newexp, call) = parse_fcall(fun, f, scp, &refs)?;
                out = fmt::asprintf("{}{}{}    {}\n", out, solve_ref(&refs), newexp, call);
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
    if(ret_tp == kwd::NOT_KWRD) ret_tp = kwd::UNITTYPE;
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

fn parse_fcall(fun: *func, f: *file, scp: *scope, refs: *[]idref) ((str, str) | CMP_ERR) = {
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
        setptr(f, true);
        if(cmp_tok(next, sym::CLOSEPAR) || next is eol) break;
        if(cmp_tok(next, sym::SYMCOMMA)) nxttk(f)!;

        const (exp, tp, arg) = parse_exp(f, scp, refs, limit, fun.param[argc])?;
        if(argc == 0){
            out = fmt::asprintf("{}{} {}", out, get_qbe_t(tp, 1), arg);
        } else {
            out = fmt::asprintf("{}, {} {}", out, get_qbe_t(tp, 1), arg);
        };
        hdr = fmt::asprintf("{}{}", hdr, exp);
        argc += 1;
        if(argc == argmax){
            next = nxttk(f)?;
            expct(cmp_tok(next, sym::CLOSEPAR), next, f, void: GENERIC, "too many parameters on function call",
                fmt::asprintf("the function \"{}\" takes {} arguments", fun.fname, argmax))?;
            break;
        };
    };
    for(argc < argmax; argc += 1){
        // TODO: default values for function parameters
        if(argc == 0){
            out = fmt::asprintf("{}{} {}", out,
                get_qbe_t(fun.param[argc], 1), getdefval(fun.param[argc]));
        } else {
            out = fmt::asprintf("{}, {} {}", out,
                get_qbe_t(fun.param[argc], 1), getdefval(fun.param[argc]));
        };
    };
    return (hdr, strings::concat(out, ")"));
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
        
        let store_t = kwd::NOT_KWRD;
        if(defn is void){
            expct(tp != kwd::NUMBER_T, oper, dup, void: GENERIC,
                "untyped definition of namespace")?;

            store_t = tp;
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
                store_t = nm.vtype;
                expct(is_subt(tp, nm.vtype), oper, dup, void: MISMTCH,
                    "destination and expression result types", cast_err(tp, nm.vtype))?;
            case =>
                assert(false);
            };
        };
        const src_id = val_id;
        if(need_ext(tp, store_t)){
            src_id = fmt::asprintf("%{}.l", dest);
            exp = fmt::asprintf("{}    {} =l ext{} {}\n",
                exp, src_id, get_qbe_t(tp, 2), val_id);
        };
        out = fmt::asprintf("{}{}{}    store{} {}, %{}\n",
            out, solve_ref(&refs), exp, get_qbe_t(store_t), src_id, dest);
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

fn parse_exp(f: *file, scp: *scope, refs: *[]idref, limit: []tok = [ eol ], ini_t: kwd = kwd::NOT_KWRD) ((str, kwd, str) | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing expression at {}", gen_pos(f))!;
    let exp = "";
    let single = true;
    let expr_t = ini_t;
    let dest = "";

    // TODO: handle idt, opr, "+" | "-" | "~"
    // TODO: handle literals of records and lists
    // TODO: handle statements as valid hands
    let next = nxttk(f)?;
    const vall = expct(next is num || next is txt || next is idt,
        next, f, void: EXPECTD, "valid operand")?: (num | txt | idt);
    match(vall){
    case let n: num =>
        dest = fmt::asprint(n: u64);
        if(expr_t == kwd::NOT_KWRD){
            expr_t = parse_cast(f, kwd::NUMBER_T)?;
        } else {
            expr_t = parse_cast(f, expr_t)?;
        };
        next = nxttk(f, true)?;
        if(is_limit(next, limit)){
            setptr(f, true);
            return ("", expr_t, dest);
        };
    case let t: txt =>
        const val = tostr(t);
        const idx = pushstr(val);
        exp = idx;
        if(expr_t == kwd::NOT_KWRD){
            expr_t = parse_cast(f, kwd::STRING_T)?;
        } else {
            expr_t = parse_cast(f, expr_t)?;
        };
        expct(is_subt(kwd::STRING_T, expr_t), vall, f, void: MISMTCH,
            "argument and parameter types", cast_err(kwd::STRING_T, expr_t))?;

        next = nxttk(f, true)?;
        setptr(f, true);
        // TODO: acept casting to union types
        expct(is_limit(next, limit), next, f, void: EXPECTD,
            "end of expression")?;
        return ("", kwd::STRING_T, idx);

    case let i: idt =>
        match(get_idt(i: str, f, scp)?){
        case let nm: *nmsp =>
            pushref(nm, f, scp, refs)?;
            if(nm.orign is kernel){
                skip_field(f)?;
                const cast = parse_cast(f, nm.vtype)?;
                expct(is_subt(cast, expr_t), vall, f, void: MISMTCH,
                    "argument and parameter types", cast_err(cast, expr_t))?;
                expr_t = cast;
                dest = fmt::asprintf("%{}.{}.g", nm.ident, get_qbe_t(expr_t, 1));

                let src_id = fmt::asprintf("%{}.{}.g", nm.ident, get_qbe_t(nm.vtype, 1));
                if(need_ext(nm.vtype, expr_t)){
                    const val_id = src_id;
                    src_id = fmt::asprintf("%{}.l.g", nm.ident);

                    const cast = fmt::asprintf("    {} =l ext{} {}\n",
                        src_id, get_qbe_t(nm.vtype, 2), val_id);

                    if(src_id != dest){
                        exp = fmt::asprintf("{}    store{} {}, {}\n",
                            cast, get_qbe_t(expr_t), src_id, dest);
                    } else {
                        exp = strings::concat(exp, cast);
                    };
                };
                if(sign_mismtch(nm.vtype, expr_t)){
                    exp = fmt::asprintf("{0}    {1} ={2} $abs{3}({3} {1})\n",
                        exp, dest, get_qbe_t(expr_t, 1), get_qbe_t(expr_t));
                };
            } else {
                expr_t = parse_cast(f, nm.vtype)?;
                dest = fmt::asprintf("%{}.{}", nm.ident, get_qbe_t(expr_t, 1));

                let src_id = fmt::asprintf("%{}.{}", nm.ident, get_qbe_t(nm.vtype, 1));
                if(need_ext(nm.vtype, expr_t)){
                    const val_id = src_id;
                    src_id = fmt::asprintf("%{}.l", nm.ident);

                    const cast = fmt::asprintf("    {} =l ext{} {}\n",
                        src_id, get_qbe_t(nm.vtype, 2), val_id);

                    if(src_id != dest){
                        exp = fmt::asprintf("{}    store{} {}, {}\n",
                            cast, get_qbe_t(expr_t), src_id, dest);
                    } else {
                        exp = strings::concat(exp, cast);
                    };
                    if(sign_mismtch(nm.vtype, expr_t)){
                        exp = fmt::asprintf("{0}    {1} ={2} $abs{3}({3} {1})\n",
                            exp, dest, get_qbe_t(expr_t, 1), get_qbe_t(expr_t));
                    };
                };
            };
            next = nxttk(f, true)?;
            if(is_limit(next, limit)){
                setptr(f, true);
                return (exp, expr_t, dest);
            };
            // TODO: assert for composite types
        case let fun: *func =>
            if(fun.orign is kernel){
                skip_field(f)?;
            };
            const (newexp, call) = parse_fcall(fun, f, scp, refs)?;
            const qbet = get_qbe_t(fun.retrn, 1);
            dest = fmt::asprintf("%{}.{}", fun.fname, qbet);
            exp = fmt::asprintf("{}    {} ={} {}\n", newexp, dest, qbet, call);
            expr_t = fun.retrn;

            next = nxttk(f, true)?;
            if(is_limit(next, limit)){
                setptr(f, true);
                return (exp, expr_t, dest);
            };
        };
    };
    assert(expr_t != kwd::NUMBER_T);
    // keep reading until end of expression
    for(!is_limit(next, limit); next = nxttk(f, true)?){
        if(is_limit(next, limit)) break;
        expct(next is opr, next, f,
            void: EXPECTD, "operator or end of expressionsss")?;
        if(next is opr){
            const oper = next: opr;
            // cast value
            if(oper == opr::CASTTOTP){
                next = nxttk(f)?;
                const cast = expct(is_type(next), next, f, void: EXPECTD,
                    "valid casting type")?: kwd;

                if(need_ext(expr_t, cast) && !single){
                    const old = dest;
                    dest = fmt::asprintf("%val.{}", get_qbe_t(cast, 1));
                    exp = fmt::asprintf("{}{}    {} ={} ext{} {}\n", exp, dest,
                        exp, get_qbe_t(expr_t, 1), get_qbe_t(expr_t, 2), old);
                };
                const old_t = expr_t;
                expr_t = cast_to(expr_t, cast, next, f)?;
                if(single){
                    const first = dest;
                    dest = fmt::asprintf("%val.{}", get_qbe_t(expr_t, 1));
                    exp = fmt::asprintf("{}    {} ={} copy {}\n",
                        exp, dest, get_qbe_t(expr_t, 1), first);
                    single = false;
                };
                if(sign_mismtch(old_t, cast)){
                    exp = fmt::asprintf("{0}    {1} ={2} $abs{3}({3} {1})\n",
                        exp, dest, get_qbe_t(cast, 1), get_qbe_t(cast));
                };
                continue;
            };
            const tmp = alloc(*f);
            if(is_cmp(oper)){
                let wrp_opr = false;
                const opr_i =
                    if(expr_t == kwd::STRING_T){
                        wrp_opr = true;
                        yield "$strcmp";
                    } else {
                        yield strings::concat(inst[oper], get_qbe_t(expr_t, 2));
                    };
                const (newexp, tp, val_id) = parse_exp(f, scp, refs, limit)?;
                expct(operable(expr_t, tp, oper), oper, tmp, void: MISMTCH,
                    "member types", cast_err(expr_t, tp, true))?;
                expr_t = cast_to(expr_t, tp, next, tmp)?;
                if(single){
                    let first = dest;
                    if(need_ext(tp, expr_t)){
                        const etp = get_qbe_t(expr_t, 1);
                        const new = fmt::asprintf("%val.{}", etp);
                        first = fmt::asprintf("{} ={} ext{} {}",
                            new, etp, get_qbe_t(tp, 2), first);
                    };
                    dest = fmt::asprintf("%val.{}", get_qbe_t(expr_t, 1));
                    exp = fmt::asprintf("{}    {} ={} copy {}\n{}",
                        exp, dest, get_qbe_t(expr_t, 1), first, newexp);
                    single = false;
                };
                exp =
                    if(!wrp_opr){
                        yield fmt::asprintf("{}{}    {} ={} {} {}, {}\n", exp, newexp, dest,
                            get_qbe_t(expr_t, 1), opr_i, dest, val_id);
                    } else {
                        const lfth = fmt::asprintf("{} {}", get_qbe_t(expr_t, 1), dest);
                        const rgth = fmt::asprintf("{} {}", get_qbe_t(tp, 1), val_id);
                        yield fmt::asprintf("{}{}    {} ={} call {}({}, {})\n", exp, newexp, dest,
                            get_qbe_t(expr_t, 1), opr_i, lfth, rgth);
                    };
                expr_t = kwd::NUMBER_T;
            } else {
                const (newexp, tp) = parse_opr(f, oper, expr_t, scp, refs)?;
                expr_t = cast_to(expr_t, tp, next, tmp)?;
                if(single){
                    const first = dest;
                    dest = fmt::asprintf("%val.{}", get_qbe_t(expr_t, 1));
                    exp = fmt::asprintf("{}    {} ={} copy {}\n{}",
                        exp, dest, get_qbe_t(expr_t, 1), first, newexp);
                    single = false;
                } else {
                    exp = strings::concat(exp, newexp);
                };
            };
            free(tmp);
        };
    };
    setptr(f, true);
    return (exp, expr_t, dest);
};

fn parse_opr(f: *file, oper: opr, expr_t: kwd, scp: *scope, refs: *[]idref) ((str, kwd) | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing operation at {}", gen_pos(f))!;
    const dup = alloc(*f);
    let next = nxttk(f)?;
    const rgth = expct(next is num || next is idt, next, f,
        void: EXPECTD, "numeric literal or identifier")?;

    const val_id = fmt::asprintf("%val.{}", get_qbe_t(expr_t, 1));
    const asg_tp = get_qbe_t(expr_t, 1);

    match(rgth){
    case let n: num =>
        if(operable(kwd::NUMBER_T, expr_t, oper)){
            free(dup);
            const exp = fmt::asprintf("    {0} ={1} {2} {0}, {3}\n",
                val_id, asg_tp, inst[oper], n: u64);  
            return (exp, expr_t);
        } else {
            return unimsg {
                msg = "member types",
                tip =  cast_err(kwd::NUMBER_T, expr_t, true),
                ptr = dup,
            }: MISMTCH;
        };
    case let i: idt =>
        match(get_idt(i: str, f, scp)?){
        case let nm: *nmsp =>
            pushref(nm, f, scp, refs)?;
            const cast = parse_cast(f, nm.vtype)?;
            if(operable(expr_t, cast, oper)){
                free(dup);
                const (hdr, wrp) = fix_sizes(expr_t, nm);
                if(!is_cmp(oper)){
                    expr_t = cast;
                } else {
                    expr_t = kwd::NUMBER_T;
                };
                const exp = fmt::asprintf("{}    {} ={} {} {}, {}\n",
                    hdr, val_id, asg_tp, inst[oper], val_id, wrp);
                return (exp, expr_t);
            } else {
                return unimsg {
                    msg = "member types",
                    tip =  cast_err(cast, expr_t, true),
                    ptr = dup,
                }: MISMTCH;
            };
        case let fun: *func =>
            const cast = parse_cast(f, fun.retrn)?;
            if(operable(expr_t, cast, oper)){
                const (hdr, wrp) = fix_sizes(expr_t, fun);
                if(!is_cmp(oper)){
                    expr_t = cast;
                } else {
                    expr_t = kwd::NUMBER_T;
                };
                const (newhdr, call) = parse_fcall(fun, f, scp, refs)?;
                const exp = fmt::asprintf("{}    {} ={} {} {}, {}\n",
                    newhdr, val_id, asg_tp, inst[oper], val_id, wrp);
                const out = fmt::asprintf("{}{}{}{}", solve_ref(refs), hdr, call, exp);

                return (out, expr_t);
            } else {
                return unimsg {
                    msg = "member types",
                    tip =  cast_err(cast, expr_t, true),
                    ptr = dup,
                }: MISMTCH;
            };
        };
    case =>
        free(dup);
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

            out = fmt::asprintf("function $main(){{\n@start\n{}    call $exit(l 0)\n    hlt\n}}\n", body);
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

        let (body, ret_tp) = parse(f, &fn_scp, mtchs(bgn, f)?, ret)?;
        expct(is_subt(ret_tp, ret), ret_tp, dup, void: MISMTCH,
            "function return type and body type", cast_err(ret_tp, ret))?;
        free(dup);

        if(ret_tp == kwd::UNITTYPE){
            body = fmt::asprintf("{}    %.ret =l copy {}\n    ret %.ret\n", body, getdefval(kwd::UNITTYPE));
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
            param_lst = fmt::asprintf("{0} %{1}.{0}",
                get_qbe_t(param_t[arg], 1), param_n[arg]);
        } else {
            param_lst = fmt::asprintf("{0}, {1} %{2}.{1}",
                param_lst, get_qbe_t(param_t[arg], 1), param_n[arg]);
        };
        param_def = fmt::asprintf("{0}    %{1} =l alloc4 {2}\n    store{3} %{1}.{4}, %{1}\n",
            param_def, param_n[arg], get_t_len(param_t[arg]), get_qbe_t(param_t[arg]), get_qbe_t(param_t[arg], 1));
    };
    return (param_lst, param_def);
};

fn is_limit(tkn: tok, lmt: []tok) bool = {
    for(let l .. lmt){
        if(cmp_tok(tkn, l)){
            if(stacktrace)
                fmt::println("reached expression limit")!;
            return true;
        };
    };
    return false;
};

// TODO: linear types
fn match_linear() bool = {
    return false;
};

// TODO: if/else & enhance operations' type checking
fn operable(lft: kwd, rgt: kwd, oper: opr) bool = {
    if(lft == kwd::RAW_TYPE || rgt == kwd::RAW_TYPE) return false;
    if(lft == kwd::ANY_TYPE || rgt == kwd::ANY_TYPE) return false;
    switch(oper){
    case opr::BOOL_LSS, opr::BOOL_GRT, opr::BOOL_LEQ, opr::BOOL_GEQ =>
        return (is_num(lft) && is_num(rgt)) ||
            (is_num(lft, true) && is_num(rgt, true)) ||
            (lft == kwd::STRING_T && rgt == kwd::STRING_T) ||
            (lft == kwd::ARRAY__T && rgt == kwd::ARRAY__T);
    case opr::BITSHFTL, opr::BITSHFTR =>
        return (is_num(lft) || is_num(lft, true)) && is_num(rgt);
    case =>
        return is_subt(lft, rgt) && is_subt(rgt, lft);
    };
};

fn need_ext(src: kwd, dst: kwd) bool = {
    if(src == kwd::U64_TYPE || src == kwd::I64_TYPE) return false;
    if(dst == kwd::U32_TYPE || dst == kwd::I32_TYPE){
        if(is_num(src) && src <= kwd::U16_TYPE) return false;
        if(is_num(src, true) && src <= kwd::I16_TYPE) return false;
    };
    if(is_num(dst) && is_num(src)){
        return src < dst;
    } else if(is_num(dst, true) && is_num(src, true)){
        return src < dst;
    } else if(is_num(dst)){
        return src - stou < dst;
    } else {
        return src < dst  - stou;
    };
};

fn fix_sizes(dest: kwd, id: (*nmsp | *func)) (str, str) = {
    let hdr = "";
    let val = "";
    match(id){
    case let nm: *nmsp =>
        val = fmt::asprintf("%{}.{}", nm.ident, get_qbe_t(nm.vtype, 1));
        if(is_subt(dest, kwd::NUMBER_T) && dest != kwd::NUMBER_T){
            if(need_ext(nm.vtype, dest)){
                hdr = fmt::asprintf("%{}.l =l ext{1} {}", nm.ident, get_qbe_t(nm.vtype, 2), val);
                val = fmt::asprintf("%{0}.l", nm.ident);
            };
        };
        if(nm.orign is kernel){
            val = strings::concat(val, ".g");
        };
    case let fun: *func =>
            val = fmt::asprintf("%{}.{}", fun.fname, get_qbe_t(fun.retrn, 1));
        if(is_subt(dest, kwd::NUMBER_T) && dest != kwd::NUMBER_T){
            if(need_ext(fun.retrn, dest)){
                hdr = fmt::asprintf("%{}.l =l ext{1} {}", fun.fname, get_qbe_t(fun.retrn, 2), val);
                val = fmt::asprintf("%{0}.l", fun.fname);
            };
        };
        if(fun.orign is kernel){
            val = strings::concat(val, ".g");
        };
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
    case kwd::UNITTYPE =>
        return tp == set;
    case =>
        assert(false, fmt::asprint(set: int));
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
    } else if(d == kwd::NUMBER_T){
        return s;
    } else {
        expct(castable(s, d), t, f, void: MISMTCH,
            "member types", cast_err(s, d))?;
        if(d != kwd::NOT_KWRD) return d;
        return s;
    };
};

fn castable(s: kwd, d: kwd) bool = {
    if(s == kwd::NOT_KWRD || s == kwd::RAW_TYPE) return true;
    if((is_num(s) || is_num(s, true)) &&
        (is_num(d) || is_num(d, true))) return true;
    return s == d;
};

fn sign_mismtch(l: kwd, r: kwd) bool = {
    return (is_num(l) && is_num(r, true)) || (is_num(r) && is_num(l, true));
};

fn cast_err(s: kwd, d: kwd, oper: bool = false) str = {
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
    if(oper){
        return fmt::asprintf("lefthand type is {}, but righthand type is {}", dst, src);
    } else {
        return fmt::asprintf("source type is {}, but dest type is {}", src, dst);
    };
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
