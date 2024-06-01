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
    assert(castable(kwd::NUMBER_T, kwd::STRING_T) == false);

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
    case kwd::STRING_T =>
        return "$empty.str";
    case kwd::ARRAY__T =>
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
    case kwd::RATIO__T, kwd::STRING_T, kwd::NUMBER_T,
        kwd::RAW_TYPE, kwd::UNITTYPE, kwd::ARRAY__T =>
        return "l";
    case =>
        fmt::errorfln("unknown type {}", vtp: int)!;
        assert(false);
        return "";
    };
};

// returns size in bytes of a type
fn get_t_len(vtp: kwd) int = {
    switch(vtp){
    case kwd::U8__TYPE, kwd::I8__TYPE =>
        return 1;
    case kwd::I16_TYPE, kwd::U16_TYPE =>
        return 2;
    case kwd::U32_TYPE, kwd::I32_TYPE =>
        return 4;
    case kwd::U64_TYPE, kwd::I64_TYPE, kwd::RATIO__T, kwd::STRING_T,
        kwd::RAW_TYPE, kwd::UNITTYPE, kwd::ARRAY__T, kwd::NUMBER_T  =>
        return 8;
    case =>
        assert(false);
        return 0;
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
    if(len(l) == 0) return "$empty.str";
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

fn cmp_origin(ths: (str | kernel), tht: (str | kernel)) bool = {
    if(ths is str && tht is str) return ths: str == tht: str;
    if(ths is kernel && tht is kernel) return ths: kernel == tht: kernel;
    return false;
};

fn pushref(nm : *nmsp, f: *file, ctxt: *context, add: *[]idref) (kwd | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("pushing new reference to \"{}\" at {}", nm.ident, gen_pos(f))!;

    const max = len(add);
    // value is already loaded
    if(nm.param) return nm.vtype;

    for(let i = 0z; i < max; i += 1){
        if(add[i].idt == nm.ident && cmp_origin(add[i].origin, nm.origin)){
            return add[i].vtp;
        };
    };
    append(add, idref {
        idt = nm.ident,
        vtp = nm.vtype,
        global = nm.global,
        origin = nm.origin,
    });
    return nm.vtype;
};

fn solve_ref(refs: *[]idref) str = {
    let hdr = "";
    const max = len(refs);
    for(let i = 0z; i < max; i += 1){
        if(refs[i].origin is kernel){
            hdr = fmt::asprintf("{0}    %{1}.{2}.g ={2} load{2} ${1}\n",
                hdr, refs[i].idt, get_qbe_t(refs[i].vtp, 1));
        } else if(refs[i].global){
            if(refs[i].vtp != kwd::STRING_T && refs[i].vtp != kwd::ARRAY__T){
                hdr = fmt::asprintf("{0}    %{1}.{2} ={2} load{2} ${1}\n",
                    hdr, refs[i].idt, get_qbe_t(refs[i].vtp, 1));
            } else {
                hdr = fmt::asprintf("{0}    %{1}.l =l copy ${1}\n",
                    hdr, refs[i].idt);
            };
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
        match(var.origin){
        case let fname: str =>
            return fmt::asprintf("{}:{}:{}", fname, var.lin + 1, var.cln + 1);
        case let kid: kernel =>
            return fmt::asprintf("the {} kernel", krnls[kid]);
        };
    case let fun: *func =>
        match(fun.origin){
        case let fname: str =>
            return fmt::asprintf("{}:{}:{}", fname, fun.lin + 1, fun.cln + 1);
        case let kid: kernel =>
            return fmt::asprintf("the {} kernel", krnls[kid]);
        };
    };
};

fn push_idt(nm: idt, mut: bool, pub: bool, tp: kwd, f: *file, ctxt: *context) (*nmsp | IDTCDUP) = {
    if(stacktrace)
        fmt::printfln("pushing identifier \"{}\" at {}", nm, gen_pos(f))!;

    match(get_idt(nm, f, ctxt.scp, ctxt)){
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
            global = false,
            origin = f.name,
            value = eol,
            public = pub,
            lin = f.lin,
            cln = f.cln,
        });
        append(ctxt.scp.defs, new);
        return new;
    };
};

fn get_idt(nm: idt, f: *file, scp: *scope, ctxt: *context) (*nmsp | *func | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("getting identifier \"{}\" at {}", nm, gen_pos(f))!;

    let next = nxttk(f, true)?;
    if(cmp_tok(next, opr::MODFIELD)){
        return parse_field(nm, f, ctxt)?;
    };
    setptr(f, true);

    for(let n ..& scp.defs){
        if(n.ident == nm: str) return n;
    };
    for(let f ..& scp.funs){
        if(f.fname == nm: str) return f;
    };

    if(!(scp.over is void)){
        return get_idt(nm, f, scp.over: *scope, ctxt)?;
    };
    return unimsg {
        msg = nm: str,
        tip = void,
        ptr = f,
    }: UNDEFNS;
};

fn push_glob(id: idt, pub: bool, f: *file, ctxt: *context) (str | CMP_ERR) = {
    if(!(ctxt.scp.over is void)){
        return unimsg {
            msg = "define mutable variables at global scope",
            tip = "try moving it to inside a function",
            ptr = f,
        }: CANT_DO;
    };
    const dup = alloc(*f);
    let res = eol: tok;
    let out = fmt::asprintf("data ${} = ", id: str);

    let expr_t = kwd::NOT_KWRD; 
    // TODO: handle idt, opr, "+" | "-" | "~"
    // TODO: handle literals of records and lists
    // TODO: handle statements as valid hands
    let next = nxttk(f)?;
    match(next){
    case let n: num =>
        res = n;
        expr_t = parse_cast(f, kwd::NUMBER_T)?;
        expct(expr_t != kwd::NUMBER_T, next, f, void: GENERIC,
            "untyped definition of namespace")?;
        next = nxttk(f, true)?;
        if(next is eol){
            setptr(f, true);
            const glob = alloc(nmsp {
                ident = id: str,
                vtype = expr_t,
                mutbl = false,
                asgnd = false,
                param = false,
                global = true,
                origin = f.name,
                value = res,
                public = pub,
                lin = dup.lin,
                cln = dup.cln,
            });
            free(dup);
            append(ctxt.scp.defs, glob);
            return fmt::asprintf("{}{{ {} {} }}\n", out, get_qbe_t(expr_t), res: i64);
        };
    case let t: txt =>
        const val = tostr(t);
        const idx = pushstr(val);
        expr_t = parse_cast(f, kwd::STRING_T)?;
        next = nxttk(f, true)?;
        setptr(f, true);
        // TODO: acept casting to union types
        expct(next is eol, next, f, void: EXPECTD, "end of expression")?;
        return fmt::asprintf("{}{{ l {} }}\n", out, idx);
    case let i: idt =>
        match(get_idt(i, f, ctxt.scp, ctxt)?){
        case let nm: *nmsp =>
            assert(nm.global);            
            res = nm.value;
            expr_t = parse_cast(f, nm.vtype)?;

            next = nxttk(f, true)?;
            if(next is eol){
                setptr(f, true);
                match(res){
                case let n: num  =>
                    return fmt::asprintf("{}{{ {} {} }}\n", out, get_qbe_t(expr_t), res: i64);
                case let t: txt =>
                    const val = tostr(t);
                    const idx = pushstr(val);
                    next = nxttk(f, true)?;
                    setptr(f, true);
                    // TODO: acept casting to union types
                    expct(next is eol, next, f, void: EXPECTD, "end of expression")?;
                    const glob = alloc(nmsp {
                        ident = id: str,
                        vtype = expr_t,
                        mutbl = false,
                        asgnd = false,
                        param = false,
                        global = true,
                        origin = f.name,
                        public = pub,
                        value = res,
                        lin = dup.lin,
                        cln = dup.cln,
                    });
                    free(dup);
                    append(ctxt.scp.defs, glob);
                    return fmt::asprintf("{}{{ l {} }}\n", out, idx);
                case =>
                    assert(false);
                };
            };
            // TODO: assert for composite types
        case let fun: *func =>
            return unimsg {
                msg = "make function calls at global scope",
                tip = "it's planned to add comptime function calls, but it's not implemented yet",
                ptr = f,
            }: CANT_DO;
        };
    };
    let res = res: num;
    // keep reading until end of expression
    for(!(next is eol); next = nxttk(f, true)?){
        if(next is eol) break;
        expct(next is opr, next, f,
            void: EXPECTD, "operator or end of expressionsss")?;
        if(next is opr){
            const oper = next: opr;
            // cast value
            if(oper == opr::CASTTOTP){
                next = nxttk(f)?;
                const cast = expct(is_type(next), next, f, void: EXPECTD,
                    "valid casting type")?: kwd;

                const old_t = expr_t;
                expr_t = cast_to(expr_t, cast, next, f)?;
                continue;
            };
            const tmp = alloc(*f);
            next = nxttk(f)?;
            const rgth = expct(next is num || next is idt, next, f,
                void: EXPECTD, "numeric literal or identifier")?;
            const (val, rght_t) =
                match(rgth){
                case let n: num =>
                    const cast = parse_cast(f, kwd::NUMBER_T)?;
                    yield (n, cast);
                case let i: idt =>
                    yield
                    match(get_idt(i, f, ctxt.scp, ctxt)?){
                    case let nm: *nmsp =>
                        assert(nm.global);           
                        assert(nm.value is num); 
                        const cast = parse_cast(f, nm.vtype)?;
                        yield (nm.value: num, cast);
                    case =>
                        return unimsg {
                            msg = "make function calls at global scope",
                            tip = "it's planned to add comptime function calls, but it's not implemented yet",
                            ptr = f,
                        }: CANT_DO;
                    };
                };
            expct(operable(expr_t, rght_t, oper), oper, tmp, void: MISMTCH,
                "member types", cast_err(expr_t, rght_t))?;
            free(tmp);
            switch(oper){
            case opr::LOGICAND =>
                if(is_num(expr_t)){
                    res = (res: i64 & val: i64): num;
                } else {
                    res = (res: u64 & val: u64): num;
                };
                expr_t = cast_to(expr_t, rght_t, next, f)?;
            case opr::LOGIC_OR =>
                if(is_num(expr_t)){
                    res = (res: i64 | val: i64): num;
                } else {
                    res = (res: u64 | val: u64): num;
                };
                expr_t = cast_to(expr_t, rght_t, next, f)?;
            case opr::BITSHFTR =>
                if(is_num(expr_t)){
                    res = (res: i64 << val: i64): num;
                } else {
                    res = (res: u64 << val: u64): num;
                };
                expr_t = cast_to(expr_t, rght_t, next, f)?;
            case opr::BITSHFTL =>
                if(is_num(expr_t)){
                    res = (res: i64 >> val: i64): num;
                } else {
                    res = (res: u64 >> val: u64): num;
                };
                expr_t = cast_to(expr_t, rght_t, next, f)?;
            case opr::BOOL_EQL =>
                if(is_num(expr_t)){
                    if(res: i64 == val: i64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                } else {
                    if(res: u64 == val: u64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                };
                expr_t = cast_to(expr_t, kwd::NUMBER_T, next, f)?;
            case opr::BOOL_DIF =>
                if(is_num(expr_t)){
                    if(res: i64 != val: i64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                } else {
                    if(res: u64 != val: u64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                };
                expr_t = cast_to(expr_t, kwd::NUMBER_T, next, f)?;
            case opr::BOOL_LSS =>
                if(is_num(expr_t)){
                    if(res: i64 < val: i64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                } else {
                    if(res: u64 < val: u64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                };
                expr_t = cast_to(expr_t, kwd::NUMBER_T, next, f)?;
            case opr::BOOL_GRT =>
                if(is_num(expr_t)){
                    if(res: i64 > val: i64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                } else {
                    if(res: u64 > val: u64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                };
                expr_t = cast_to(expr_t, kwd::NUMBER_T, next, f)?;
            case opr::BOOL_LEQ =>
                if(is_num(expr_t)){
                    if(res: i64 <= val: i64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                } else {
                    if(res: u64 <= val: u64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                };
                expr_t = cast_to(expr_t, kwd::NUMBER_T, next, f)?;
            case opr::BOOL_GEQ =>
                if(is_num(expr_t)){
                    if(res: i64 >= val: i64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                } else {
                    if(res: u64 >= val: u64){
                        res = 1: u64: num;
                    } else {
                        res = 0: u64: num;
                    };
                };
                expr_t = cast_to(expr_t, kwd::NUMBER_T, next, f)?;
            case opr::ARTH_PLS =>
                if(is_num(expr_t)){
                    res = (res: i64 + val: i64): num;
                } else {
                    res = (res: u64 + val: u64): num;
                };
                expr_t = cast_to(expr_t, rght_t, next, f)?;
            case opr::ARTH_MIN =>
                if(is_num(expr_t)){
                    res = (res: i64 - val: i64): num;
                } else {
                    res = (res: u64 - val: u64): num;
                };
                expr_t = cast_to(expr_t, rght_t, next, f)?;
            case opr::ARTH_MUL =>
                if(is_num(expr_t)){
                    res = (res: i64 * val: i64): num;
                } else {
                    res = (res: u64 * val: u64): num;
                };
                expr_t = cast_to(expr_t, rght_t, next, f)?;
            case opr::ARTH_DIV =>
                if(is_num(expr_t)){
                    res = (res: i64 / val: i64): num;
                } else {
                    res = (res: u64 / val: u64): num;
                };
                expr_t = cast_to(expr_t, rght_t, next, f)?;
            case opr::ARTH_MOD =>
                if(is_num(expr_t)){
                    res = (res: i64 % val: i64): num;
                } else {
                    res = (res: u64 % val: u64): num;
                };
                expr_t = cast_to(expr_t, rght_t, next, f)?;
            case =>
                return bi_msg {
                    lft = "valid operator",
                    rgt = tktostr(oper, true),
                    tip = void,
                    ptr = f,
                }: EXPECTD;
            };
        };
    };
    setptr(f, true);
    const glob = alloc(nmsp {
        ident = id: str,
        vtype = expr_t,
        mutbl = false,
        asgnd = false,
        param = false,
        global = true,
        origin = f.name,
        value = res,
        public = pub,
        lin = dup.lin,
        cln = dup.cln,
    });
    free(dup);
    append(ctxt.scp.defs, glob);

    if(is_num(expr_t)){
        return fmt::asprintf("{}{{ {} {} }}\n", out, get_qbe_t(expr_t), res: u64);
    } else {
        assert(is_num(expr_t, true));
        return fmt::asprintf("{}{{ {} {} }}\n", out, get_qbe_t(expr_t), res: i64);
    };
};

fn push_fun(name: idt, pub: bool, f: *file, parm_l: []kwd, parm_n : []idt, retrn: kwd, efx: []str, ctxt: *context) (*func | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("pushing function \"{}\" at {}", name, gen_pos(f))!;
    assert(ctxt.scp.over is void);
    match(get_idt(name, f, ctxt.scp, ctxt)){
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
            origin = f.name,
            public = pub,
            effect = efx,
            lin = f.lin,
            cln = f.cln,
        });
        append(ctxt.scp.funs, fun);
        return fun;
    };
};

// parses a source. if `from` is a string, opens the file and parses its contents, if the file
// itself, parses a new scope withih `within`. returns a header containing global definitions,
// the parsed source itself in the QBE IR and the final type of return, in the case of parsing
// a function body. in case of any parsing error, returns a compilation error
fn parse(from: (str | *file), ctxt: *context, stop: size = 0, fun_tp: kwd = kwd::UNITTYPE) ((str, kwd) | CMP_ERR) = {
    let out = "";
    let ret_tp = kwd::NOT_KWRD;
    let f =
        match(from){
        case let fname: str =>
            if(stacktrace)
                fmt::printfln("parsing file \"{}\"", fname)!;

            const _f =  load(fname)?;
            out = parse_global(_f, ctxt)?;
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
            case kwd::PUBFIELD =>
                if(stacktrace)
                    fmt::printfln("parsing pubdef at {}", gen_pos(f))!;
                if(!(ctxt.scp.over is void)){
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
                    const asg = parse_asg(f, i, true, next: opr, ctxt)?;
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
                    over = ctxt.scp,
                    defs = [],
                    funs = [],
                };
                ctxt.scp = &if_scp;
                const endp = f.lin + 1;
                const limit = [ sym::OPN_CRLY ]: []tok;
                for(cmp_tok(next, kwd::IF___BLK)){
                    let refs = []: []idref;
                    let dup = alloc(*f);
                    const idx = dup.lin + 1;
                    
                    const (exp, tp, chk) = parse_exp(f, ctxt, &refs, limit)?;
                    nxttk(f)!;
                    // fix checking for strings and arrays
                    const eval =
                        if(tp == kwd::STRING_T || tp == kwd::ARRAY__T){
                            exp = fmt::asprintf("{}    %val.l =l loadl {}\n    %val.l =l sub %val.l, 8\n", exp, chk);
                            yield "%val.l";
                        } else {
                            yield chk;
                        };
                    const (body, if_tp) = parse(f, ctxt, mtchs(sym::OPN_CRLY, f)?)?;
                    if(if_tp != kwd::UNITTYPE){
                        expct(is_subt(if_tp, ret_tp), if_tp, dup, void: MISMTCH,
                        "return types", "union types are not implemented yet")?;
                    };
                    free(dup);
                    out = fmt::asprintf("{0}{1}{2}    jnz {3}, @t.{4}, @f.{4}\n@t.{4}\n{5}    jmp @end.{6}\n@f.{4}\n",
                        out, solve_ref(&refs), exp, eval, idx, body, endp);
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
                        const (body, el_tp) = parse(f, ctxt, mtchs(sym::OPN_CRLY, f)?)?;
                        if(el_tp != kwd::UNITTYPE){
                            expct(is_subt(el_tp, ret_tp), el_tp, dup, void: MISMTCH,
                            "return types", "union types are not implemented yet")?;
                        };
                        out = strings::concat(out, body);
                        free(dup);
                    };
                    out = fmt::asprintf("{}@end.{}\n", out, endp);
                };
                ctxt.scp = if_scp.over: *scope;
            case kwd::DMUTABLE =>
                if(stacktrace)
                    fmt::printfln("parsing mutdef at {}", gen_pos(f))!;
                next = nxttk(f)?;
                const i = expct(next is idt,
                    next, f, void: EXPECTD, "variable definition")?: idt;

                const asg = parse_asg(f, i, false, next: opr, ctxt, void, true)?;
                out = fmt::asprintf("{}{}", out, asg);
            case kwd::USE__MOD =>
                if(stacktrace)
                    fmt::printfln("parsing mod req at {}", gen_pos(f))!;
                if(!(ctxt.scp.over is void)){
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
                case let krnl: size =>
                    const filename = fmt::asprintf("{}{}.asm", ctxt.libpath, mod: str);
                    // TODO: un-hardcode these definitions
                    switch(krnl){
                    case kernel::IO =>
                        const mod_io = alloc(module {
                            name = mod: str,
                            origin = filename,
                            funs = io_funs,
                            defs = io_vars,
                            addp = (f.lin + 1, f.cln + 1),
                        });
                        append(ctxt.uses, mod_io);
                    case kernel::MEM =>
                        const mod_mem = alloc(module {
                            name = mod: str,
                            origin = filename,
                            funs = mem_funs,
                            defs = mem_defs,
                            addp = (f.lin + 1, f.cln + 1),
                        });
                        append(ctxt.uses, mod_mem);
                    case =>
                        const err = fmt::asprintf("module {} not matched", mod: str);
                        return (err, f): UNREACH;
                    };
                case =>
                    match(get_mod(mod, ctxt)){
                    case let dup_mod: *module =>
                        return bi_msg {
                            lft = mod: str,
                            rgt = fmt::asprintf("{}:{}:{}",
                                f.name, dup_mod.addp.0, dup_mod.addp.1),
                            tip = void,
                            ptr = f,
                        }: MODCDUP;
                    case =>
                        let lmod = scope {
                            over = void,
                            defs = [],
                            funs = [],
                        };
                        let mods = []: []*module;
                        let modctxt = context {
                            scp = &lmod,
                            uses = &mods,
                            libpath = ctxt.libpath,
                            nomain = true,
                            hostfn = "",
                            effect = [],
                        };
                        const filename = fmt::asprintf("{}{}.ms", modctxt.libpath, mod: str);
                        match(build(filename, mod: str, &modctxt)){
                        case let e: CMP_ERR =>
                            if(e is LDDFAIL){
                                return unimsg {
                                    msg = fmt::asprintf("source file for module \"{}\" not found", col(mod: str, cmd::BLU)),
                                    tip = "try to specify the libpath with the flag -l",
                                    ptr = f,
                                }: GENERIC;
                            } else return e;
                        case =>
                            const newmod = alloc(module {
                                name = mod: str,
                                origin = filename,
                                funs = lmod.funs,
                                defs = lmod.defs,
                                addp = (f.lin + 1, f.cln + 1),
                            });
                            append(ctxt.uses, newmod);
                        };
                    };
                };
            case kwd::RETURNTO =>
                if(stacktrace)
                    fmt::printfln("parsing return at {}", gen_pos(f))!;
                let add = []: []idref;
                const dup = alloc(*f);
                const (exp, expr_t, val_id) = parse_exp(f, ctxt, &add, [eol], (0, fun_tp))?;
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
                match(get_idt(i, f, ctxt.scp, ctxt)){
                case =>
                    const asg = parse_asg(f, i, false, next: opr, ctxt)?;
                    out = fmt::asprintf("{}{}", out, asg);
                case let nm: *nmsp =>
                    // these fields have already been parsed
                    if(nm.global && !nm.asgnd){
                        nm.asgnd = true;
                        jmpto(eol, f)?;
                        continue;
                    };
                    const asg = parse_asg(f, i, false, next: opr, ctxt, nm)?;
                    out = fmt::asprintf("{}{}", out, asg);
                case let fun: *func =>
                    if(fun.origin is kernel){
                        skip_field(f)?;
                        check_efx(f, fun, ctxt)?;
                        const (newexp, call) = parse_fcall(fun, f, ctxt, &refs)?;
                        out = fmt::asprintf("{}{}{}    {}\n", out, solve_ref(&refs), newexp, call);
                        continue;
                    };
                    next = nxttk(f, true)?;
                    if(is_asg_opr(next)){
                        setptr(f, true);
                        const asg = parse_asg(f, i, false, next: opr, ctxt, fun)?;
                        out = fmt::asprintf("{}{}", out, asg);
                    } else {
                        setptr(f, true);
                        check_efx(f, fun, ctxt)?;
                        const (newexp, call) = parse_fcall(fun, f, ctxt, &refs)?;
                        out = fmt::asprintf("{}{}{}    {}\n", out, solve_ref(&refs), newexp, call);
                    };
                };
            } else {
                setptr(f, true);
                let refs = []: []idref;
                const id = get_idt(i, f, ctxt.scp, ctxt)?;
                expct(id is *func, i, f, void: NOTCALL, i)?;
                const fun = id: *func;
                if(fun.origin is kernel){
                    skip_field(f)?;
                };
                check_efx(f, fun, ctxt)?;
                const (newexp, call) = parse_fcall(fun, f, ctxt, &refs)?;
                out = fmt::asprintf("{}{}{}    {}\n", out, solve_ref(&refs), newexp, call);
                finsh(f, void: EXPECTD, "end of function call")?;
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
    if(ctxt.scp.over is void){
        return (strings::concat(datasec, out), kwd::NOT_KWRD);
    };
    if(ret_tp == kwd::NOT_KWRD) ret_tp = kwd::UNITTYPE;
    return (out, ret_tp);
};

fn parse_global(_f: *file, ctxt: *context) (str | CMP_ERR) = {
    if(stacktrace)
        fmt::println("parsing global definitions")!;
    const f = alloc(*_f);
    const max = len(f.src);
    
    let defs = "";
    let new_pub = false;
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
            next = nxttk(f, true)?;
            if(cmp_tok(next, kwd::FUNCTION)){
                parse_fun(f, i, new_pub, ctxt, true)?;
            // TODO: expect for unary operators
            } else if(next is num || next is txt || next is idt){
                setptr(f, true);
                const gdef = push_glob(i, new_pub, f, ctxt)?;
                new_pub = false;
                defs = strings::concat(defs, gdef);
            } else {
                jmpto(eol, f)?;
                continue;
            };
        case let k: kwd =>
            // TODO: parse typedefs
            switch(k){
            case kwd::PUBFIELD =>
                new_pub = true;
                continue;
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
    return defs;
};

fn get_mod(mod: idt, ctxt: *context) (*module | void) = {
    for(let m ..& ctxt.uses){
        if(m.name == mod: str){
            return m;
        };
    };
};

fn parse_field(mod: idt, f: *file, ctxt: *context) (*nmsp | *func | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing mod field access")!;

    match(get_mod(mod, ctxt)){
    case let m: *module =>
        let next = nxttk(f)?;
        const field = expct(next is idt,
            next, f, void: EXPECTD, "field name")?: idt;
        let max = len(m.funs);
        for(let i = 0z; i < max; i += 1){
            const fun = m.funs[i];
            if(field == fun.fname){
                if(fun.public) return fun;
                return bi_msg {
                    lft = field,
                    rgt = mod: str,
                    tip = void, // TODO: add a tip when the module is not from stdlib
                    ptr = f,
                }: NOTPUBL;
            };
        };
        let max = len(m.defs);
        for(let i = 0z; i < max; i += 1){
            const nm = m.defs[i];
            if(field: str == nm.ident){
                if(nm.public) return nm;
                return bi_msg {
                    lft = field,
                    rgt = mod: str,
                    tip = void, // TODO: add a tip when the module is not from stdlib
                    ptr = f,
                }: NOTPUBL;
            };
        };
        return unimsg {
            msg = fmt::asprintf("this field is not defined in the \"{}\" module", mod: str),
            tip = void,
            ptr = f,
        }: GENERIC;
    case void =>
        return unimsg {
            msg = fmt::asprintf("the module {} is not defined at this point", mod: str),
            tip = void,
            ptr = f,
        }: GENERIC;
    };
};

fn parse_fcall(fun: *func, f: *file, ctxt: *context, refs: *[]idref) ((str, str) | CMP_ERR) = {
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
            fmt::asprintf("the function \"{}\" takes {}", fun.fname, plural("{} argument", argmax)))?;
    };
    const max = len(f.src);
    for(f.ptr < max){
        next = nxttk(f, true)?;
        if(cmp_tok(next, opr::COMPLETE)){
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
            next = nxttk(f)?;
            expct(cmp_tok(next, sym::CLOSEPAR), next, f, void: GENERIC, "too many arguments on function call",
                fmt::asprintf("the function \"{}\" takes {}", fun.fname, plural("{} argument", argmax)))?;
            break;
        };
        setptr(f, true);
        if(cmp_tok(next, sym::CLOSEPAR) || next is eol){
            if(argc != argmax){
                return unimsg {
                    msg = "too few arguments on function call",
                    tip = fmt::asprintf("the function \"{}\" takes {}.\ntry using the `...` operator to fill on default values",
                        fun.fname, plural("{} argument", argmax)),
                    ptr = f,
                } : GENERIC;
            };
            break;
        };
        if(cmp_tok(next, sym::SYMCOMMA)) nxttk(f)!;
        const (exp, tp, arg) = parse_exp(f, ctxt, refs, limit, (argc + 1, fun.param[argc]))?;
        expct(is_subt(tp, fun.param[argc]), next, f, void: MISMTCH,
            fmt::asprintf("function parameter {} and argument types", argc + 1),
            cast_err(tp, fun.param[argc]))?;

        if(argc == 0){
            out = fmt::asprintf("{}{} {}", out, get_qbe_t(tp, 1), arg);
        } else {
            out = fmt::asprintf("{}, {} {}", out, get_qbe_t(tp, 1), arg);
        };
        hdr = fmt::asprintf("{}{}", hdr, exp);
        argc += 1;
        if(argc == argmax){
            next = nxttk(f)?;
            expct(cmp_tok(next, sym::CLOSEPAR), next, f, void: GENERIC, "too many arguments on function call",
                fmt::asprintf("the function \"{}\" takes {}", fun.fname, plural("{} argument", argmax)))?;
            break;
        };
    };
    return (hdr, strings::concat(out, ")"));
};

fn parse_asg(f: *file, dest: idt, pub: bool, oper: opr, ctxt: *context, defn: (*nmsp | *func | void) = void, mutbl: bool = false) (str | CMP_ERR) = {
    if(stacktrace){
        if(defn is void){
            fmt::printfln("parsing assignment to \"{}\" at {}", dest, gen_pos(f))!;
        } else {
            fmt::printfln("parsing definition and assignment to \"{}\" at {}", dest, gen_pos(f))!;
        };
    };
    const global = ctxt.scp.over is void;
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

        push_idt(dest, mutbl, pub, tp, f, ctxt)?;
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
            return parse_fun(f, dest, pub, ctxt)?;
        } else {
            setptr(f, true);
        };
        let refs = []: []idref;
        const (exp, tp, val_id) = parse_exp(f, ctxt, &refs)?;
        
        let store_t = kwd::NOT_KWRD;
        if(defn is void){
            expct(tp != kwd::NUMBER_T, oper, dup, void: GENERIC,
                "untyped definition of namespace")?;

            store_t = tp;
            const nm = push_idt(dest, mutbl, pub, tp, f, ctxt)?;
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

fn parse_exp(f: *file, ctxt: *context, refs: *[]idref, limit: []tok = [ eol ], ini_t: ((size, kwd) | void) = void) ((str, kwd, str) | CMP_ERR) = {
    if(stacktrace)
        fmt::printfln("parsing expression at {}", gen_pos(f))!;
    let exp = "";
    let single = true;
    let (argc, expr_t) =
        match(ini_t){
        case let any: (size, kwd) =>
            yield any;
        case void =>
            yield (0z, kwd::NOT_KWRD);
        };
    let dest = "";

    // TODO: handle idt, opr, "+" | "-" | "~"
    // TODO: handle literals of records and lists
    // TODO: handle statements as valid hands
    let next = nxttk(f)?;
    const vall = expct(next is num || next is txt || next is idt,
        next, f, void: EXPECTD, "valid operand")?: (num | txt | idt);
    match(vall){
    case let n: num =>
        dest = fmt::asprint(n: i64);
        if(expr_t == kwd::NOT_KWRD){
            expr_t = kwd::NUMBER_T;
        } else {
            expr_t = cast_to(kwd::NUMBER_T, expr_t, vall, f)?;
        };
        expr_t = parse_cast(f, expr_t)?;
        next = nxttk(f, true)?;
        if(is_limit(next, limit)){
            setptr(f, true);
            return ("", expr_t, dest);
        };
    case let t: txt =>
        const val = tostr(t);
        const idx = pushstr(val);
        if(expr_t == kwd::NOT_KWRD){
            expr_t = kwd::STRING_T;
        } else {
            expr_t = cast_to(kwd::STRING_T, expr_t, vall, f)?;
        };
        expr_t = parse_cast(f, expr_t)?;
        expct(is_subt(kwd::STRING_T, expr_t), vall, f, void: MISMTCH,
            "argument and parameter types", cast_err(kwd::STRING_T, expr_t))?;

        next = nxttk(f, true)?;
        setptr(f, true);
        // TODO: acept casting to union types
        expct(is_limit(next, limit), next, f, void: EXPECTD,
            "end of expression")?;
        return ("", kwd::STRING_T, idx);

    case let i: idt =>
        match(get_idt(i, f, ctxt.scp, ctxt)?){
        case let nm: *nmsp =>
            pushref(nm, f, ctxt, refs)?;
            if(nm.origin is kernel){
                skip_field(f)?;
                const cast = parse_cast(f, nm.vtype)?;
                if(expr_t != kwd::NOT_KWRD){
                    if(argc == 0){
                        expct(is_subt(cast, expr_t), vall, f, void: MISMTCH,
                            "member types", cast_err(cast, expr_t))?;
                    } else {
                        expct(is_subt(cast, expr_t), next, f, void: MISMTCH,
                            fmt::asprintf("function parameter {} and argument types", argc),
                            cast_err(cast, expr_t))?;
                    };
                };
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
            if(fun.origin is kernel){
                skip_field(f)?;
            };
            check_efx(f, fun, ctxt)?;
            const (newexp, call) = parse_fcall(fun, f, ctxt, refs)?;
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
    assert(expr_t != kwd::NOT_KWRD);
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
                    exp = fmt::asprintf("{}    {} ={} ext{} {}\n", exp, dest,
                        get_qbe_t(cast, 1), get_qbe_t(expr_t, 2), old);
                } else if(need_ext(expr_t, cast, true)){
                    const old = dest;
                    dest = fmt::asprintf("%val.{}", get_qbe_t(cast, 1));
                    exp = fmt::asprintf("{}    {} ={} copy {}\n", exp, dest, get_qbe_t(cast, 1), old);
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
                    exp = fmt::asprintf("{0}    {1} ={2} call $abs{3}({3} {1})\n",
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
                const (newexp, tp, val_id) = parse_exp(f, ctxt, refs, limit)?;

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
                const (newexp, tp) = parse_opr(f, oper, expr_t, ctxt, refs)?;
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

fn parse_opr(f: *file, oper: opr, expr_t: kwd, ctxt: *context, refs: *[]idref) ((str, kwd) | CMP_ERR) = {
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
                val_id, asg_tp, inst[oper], n: i64);  
            return (exp, expr_t);
        } else {
            return unimsg {
                msg = "member types",
                tip =  cast_err(kwd::NUMBER_T, expr_t, true),
                ptr = dup,
            }: MISMTCH;
        };
    case let i: idt =>
        match(get_idt(i, f, ctxt.scp, ctxt)?){
        case let nm: *nmsp =>
            pushref(nm, f, ctxt, refs)?;
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
                check_efx(f, fun, ctxt)?;
                const (newhdr, call) = parse_fcall(fun, f, ctxt, refs)?;
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

fn parse_fun(f: *file, dest: idt, pub: bool, ctxt: *context, skip: bool = false) (str | CMP_ERR) = {
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
                global = false,
                origin = f.name,
                value = eol,
                public = false,
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
    
    // parse effects
    let tags = []: []str;
    next = nxttk(f, true)?;
    if(cmp_tok(next, opr::EFFCTTAG)){
        next = nxttk(f)?;
        let tag = expct(next is idt, next, f, void: EXPECTD, "effect tag")?: idt;
        append(tags, tag: str);

        next = nxttk(f, true)?;
        expct(cmp_tok(next, opr::LOGICAND) || cmp_tok(next, sym::OPN_CRLY),
            next, f, void: EXPECTD, "`&` operator or function body")?: idt;

        for(cmp_tok(next, opr::LOGICAND)){
            next = nxttk(f, true)?;
            tag = expct(next is idt,
                next, f, void: EXPECTD, "effect tag")?: idt;
            append(tags, next: str);

            next = nxttk(f, true)?;
            expct(cmp_tok(next, opr::LOGICAND) || cmp_tok(next, sym::OPN_CRLY),
                next, f, void: EXPECTD, "`&` operator or function body")?;
        };
    };
    setptr(f, true);
    if(skip){
        push_fun(dest, pub, dup, params, parm_n, ret, tags, ctxt)?;
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
            let fn_scp = scope {
                over = ctxt.scp,
                defs = [],
                funs = [],
            };
            ctxt.scp = &fn_scp;
            ctxt.hostfn = dest;
            ctxt.effect = tags;
            next = nxttk(f)?;
            const bgn = expct(cmp_tok(next, sym::OPN_CRLY), next, f, void: EXPECTD,
                "function body declaration")?: sym;

            const (body, ret_tp) = parse(f, ctxt, mtchs(bgn, f)?)?;
            ctxt.scp = fn_scp.over: *scope;
            ctxt.hostfn = "";
            ctxt.effect = [];
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
            over = ctxt.scp,
            defs = defs,
            funs = [],
        };
        next = nxttk(f)?;
        const bgn = expct(cmp_tok(next, sym::OPN_CRLY), next, f, void: EXPECTD,
            "function body declaration")?: sym;

        ctxt.scp = &fn_scp;
        ctxt.hostfn = dest;
        ctxt.effect = tags;
        let (body, ret_tp) = parse(f, ctxt, mtchs(bgn, f)?, ret)?;
        ctxt.scp = fn_scp.over: *scope;
        ctxt.hostfn = "";
        ctxt.effect = [];
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

fn plural(pat: str, cnt: u64) str = {
    if(cnt == 1){
        return fmt::asprintf(pat, cnt);
    } else {
        return strings::concat(fmt::asprintf(pat, cnt), "s");
    };
};

fn check_efx(f: *file, fun: *func, ctxt: *context) (void | CMP_ERR) = {
    const effect =
        match(fun.origin){
        case kernel =>
            yield krnls[fun.origin: kernel];
        case let mod: str =>
            const (name, _) = rem_path(mod);
            yield strings::replace(name, ".ms", "");
        };
    if(fun.origin is str && fun.origin: str == f.name){
        for(let f_efx .. fun.effect){
            for(let tag .. ctxt.effect){
                if(f_efx == tag) return;
            };
        };
        return bi_msg {
            lft = fun.fname,
            rgt = ctxt.hostfn,
            tip = get_efx(fun),
            ptr = f,
        }: EFX_ERR;
    } else {
        for(let tag .. ctxt.effect){
            if(tag == effect) return;
        };
        return bi_msg {
            lft = fun.fname,
            rgt = ctxt.hostfn,
            tip = get_efx(fun, effect),
            ptr = f,
        }: EFX_ERR;
    };
};

fn get_efx(fun: *func, mod: str = "") str = {
    let out = fmt::asprintf("the function {} produces these effects:", fun.fname);
    let first = true;
    if(mod != ""){
        return fmt::asprintf("{} {}", out, mod);
    };
    assert(len(fun.effect) > 0);
    for(let efx .. fun.effect){
        if(first){
            out = fmt::asprintf("{} {}", out, efx);
            first = false;
        } else {
            out = fmt::asprintf("{}, {}", out, efx);
        };
    };
    return out;
};

// TODO: linear types
fn match_linear() bool = {
    return false;
};

// TODO: if/else & enhance operations' type checking
fn operable(lft: kwd, rgt: kwd, oper: opr) bool = {
    if(lft == kwd::RAW_TYPE || rgt == kwd::RAW_TYPE) return false;
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

fn need_ext(src: kwd, dst: kwd, numarg: bool = false) bool = {
    if(numarg)
    if(src == kwd::NUMBER_T && get_t_len(dst) < 8) return true;

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
        if(nm.origin is kernel){
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
        if(fun.origin is kernel){
            val = strings::concat(val, ".g");
        };
    };
    return (hdr, val);
};

fn is_subt(tp: kwd, set: kwd) bool = {
    switch(set){
    case kwd::RAW_TYPE =>
        return true;
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
    expct(castable(s, d), t, f, void: MISMTCH,
        "member types", cast_err(s, d))?;
    if(s == kwd::NOT_KWRD){
        return d;
    } else if(d == kwd::NUMBER_T){
        return s;
    } else {
        if(d != kwd::NOT_KWRD) return d;
        return s;
    };
};

fn castable(s: kwd, d: kwd) bool = {
    if(s == kwd::NOT_KWRD || s == kwd::RAW_TYPE) return true;
    if(d == kwd::RAW_TYPE) return true;
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
