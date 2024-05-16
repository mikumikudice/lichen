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
    case kwd::U64_TYPE, kwd::I64_TYPE,
        kwd::RATIO__T, kwd::LIST_LIT =>
        return "l";
    case =>
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
    datasec = fmt::asprintf("{}data $.{} = {{ w {}, b {} }}\n",
        datasec, max, len(l), l);
    return fmt::asprintf("$.{}", max);
};

fn pushref(id: str, f: *file, scp: *scope, add: *[]ref) (void | CMP_ERR) = {
    const max = len(add);
    const nm =
        match(get_idt(id, scp)){
        case let i: *nmsp =>
            yield i;
        case void =>
            return unimsg {
                msg = id,
                tip = void,
                ptr = f,
            }: UNDEFNS;
        };
    for(let i = 0z; i < max; i += 1){
        if(add[i].idt == id){
            return;
        };
    };
    append(add, ref {
        idt = id,
        vtp = nm.vtype,
    });
};

fn push_idt(nm: str, mut: bool, f: *file, scp: *scope) (*nmsp | IDTCDUP) = {
    match(get_idt(nm, scp)){
    case void =>
        const new = alloc(nmsp {
            ident = nm,
            vtype = kwd::NOT_KWRD,
            mutbl = mut,
            asgnd = false,
            orign = f.name,
            lin = f.lin,
            cln = f.cln,
        });
        append(scp.defs, new);
        return new;
    case let dup: *nmsp =>
        return bi_msg {
            lft = nm,
            rgt = fmt::asprintf("{}:{}:{}", dup.orign, dup.lin + 1, dup.cln + 1),
            tip = void,
            ptr = f,
        }: IDTCDUP;
    };
};

fn get_idt(nm: str, scp: *scope) (*nmsp | void) = {
    for(let n ..& scp.defs){
        if(n.ident == nm) return n;
    };
    if(!(scp.over is void)){
        return get_idt(nm, scp.over: *scope);
    };
};

// parses a source. if `from` is a string, opens the file and parses its contents, if the file
// itself, parses a new scope withih `within`. returns a header containing global definitions,
// the parsed source itself in the QBE IR and the final type of return, in the case of parsing
// a function body. in case of any parsing error, returns a compilation error
fn parse(from: (str | *file), scp: *scope, stop: size = 0) (str | CMP_ERR) = {
    let out = "";
    let f =
        match(from){
        case let fname: str =>
            yield load(fname)?;
        case let _f: *file =>
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
                    out = strings::concat(out, exp);
                };
            case =>
                todo(f, "uncovered rule")?;
            };
        case let i: idt =>
            match(get_idt(i: str, scp)){
            case void =>
                const nm = push_idt(i: str, false, f, scp)!;
                next = nxttk(f, true)?;
                const oper = expct(next is opr, next, f, void: EXPECTD,
                    "type declaration or assignment")?: opr;
                
                switch(oper){
                case opr::CASTTOTP =>
                    next = nxttk(f)?;
                    const tp = expct(is_type(next), next, f, void: EXPECTD,
                        "valid type notation")?: kwd;
                    nm.vtype = tp;
                    out = fmt::asprintf("{0}    %{1} =l alloc4 {2}\n    store{3} {4}, %{1}\n",
                        out, i: str, tptoz(tp), tptob(tp), getdefval(tp));
                case opr::ASSIGNMT =>
                    setptr(f, true);
                    const (exp, tp) = parse_asg(f, i: str, scp)?;
                    nm.vtype = tp;
                    nm.asgnd = true;
                    out = fmt::asprintf("{}    %{} =l alloc4 {}\n{}",
                        out, i: str, tptoz(tp), exp);
                case => void;
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

                    out = fmt::asprintf("{}{}    store{} %.val, %{}\n",
                        out, exp, tptob(tp), nm.ident);
                } else {
                    return unimsg {
                        msg = "redefine a value of a immutable variable",
                        tip = void,
                        ptr = f,
                    }: CANT_DO;
                };
            };
        case let s: sym =>
            switch(s){
            case sym::CLS_CRLY =>
                if(stop > 0 && f.ptr >= stop) break;
            case =>
                todo(f, "uncovered rule")?;
            };
        case =>
            todo(f, "uncovered rule")?;
        };
    };
    return out;
};

fn parse_asg(f: *file, dest: str, scp: *scope, defn: bool = false) ((str, kwd) | CMP_ERR) = {
    let next = nxttk(f)?;
    let defn = false;
    const oper = expct(next is opr, next,
            f, void: EXPECTD, "assigment")?: opr;
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
    let add = []: []ref;
    let otp =
        match(get_idt(dest, scp)){
        case let nm: *nmsp =>
            yield nm.vtype;
        case void =>
            yield kwd::NOT_KWRD;
        };
    next = nxttk(f)?;
    // TODO: handle idt, opr, "+" | "-" | "~"
    // TODO: handle literals of records and lists
    const vall = expct(next is num || next is txt || next is idt || next is kwd,
        next, f, void: EXPECTD, "valid righthand")?;
    match(vall){
    case let n: num =>
        if(!defn){
            out = fmt::asprintf("    store#len# {}, %.val\n", n: u32);
            otp = kwd::NUMBER_T;
        } else {
            out = fmt::asprintf("    store#len# {}, %{}\n", n: u32, dest);
            otp = kwd::NUMBER_T;
        };

    case let t: txt => void;
        const val = tostr(t);
        const idx = pushstr(val);
        out = fmt::asprintf("    %.val =#len# {}\n", idx);

        finsh(f, void: CANT_DO, "perform operations on string literals")?;
        return (out, kwd::LIST_LIT);

    case let i: idt => void;
        match(get_idt(i: str, scp)){
        case let nm: *nmsp =>
            pushref(i: str, f, scp, &add)?;
            out = fmt::asprintf("    %.val =#len# load{} %{}\n", tptob(nm.vtype), i: str);
            otp = nm.vtype;
            // TODO: assert for composite types
        case void =>
            return unimsg {
                msg = i: str,
                tip = void,
                ptr = f,
            }: UNDEFNS;
        };
    case let k: kwd =>
        if(k == kwd::FUNCTION){
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
    for(!(next is eol); next = nxttk(f)?){
        expct(next is opr || next is eol, next, f,
            void: EXPECTD, "operator or end of expression")?;
        if(next is opr){
            // cast value
            if(next: opr == opr::CASTTOTP){
                next = nxttk(f)?;
                const cast = expct(is_type(next), next, f, void: EXPECTD,
                    "valid casting type")?: kwd;

                expct(castable(otp, cast), cast, f, void: EXPECTD,
                    "valid casting", cast_err(otp, cast))?: kwd;
                // TODO: actually cast values
                otp = cast;
                continue;
            };
            const (exp, tp) = parse_opr(f, next: opr, otp, scp, &add)?;
            otp = tp;
            out = strings::concat(out, exp);
        };
    };
    assert(otp != kwd::NUMBER_T);
    let hdr = "";
    const max = len(add);
    for(let i = 0z; i < max; i += 1){
        hdr = fmt::asprintf("{0}    %{1}.v ={2} load{2} %{1}\n",
            hdr, add[i].idt, tptob(add[i].vtp));
    };
    out = strlib::replace(out, "#len#", tptob(otp));
    return (strings::concat(hdr, out), otp);
};

fn parse_opr(f: *file, oper: opr, tp: kwd, scp: *scope, add: *[]ref) ((str, kwd) | CMP_ERR) = {
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
        if(is_subt(kwd::NUMBER_T, tp)){
            const exp = fmt::asprintf("    %.val ={} {} %.val, {}\n",
                tptob(tp), inst[oper], n: u32);
            return (exp, tp);
        } else {
            return unimsg {
                msg = "member types",
                tip =  "try explicitly casting your members",
                ptr = f,
            }: MISMTCH;
        };
    case let i: idt =>
        if(is_subt(kwd::NUMBER_T, tp)){
            pushref(i: str, f, scp, add)?;
            const exp = fmt::asprintf("    %.val ={} {} %.val, %{}.v\n",
                tptob(tp), inst[oper], i: str);
            return (exp, tp);
        } else {
            return unimsg {
                msg = "member types",
                tip =  "try explicitly casting your members",
                ptr = f,
            }: MISMTCH;
        };
    case => return f: UNREACH;
    };
};

fn parse_fun(f: *file, dest: str, scp: *scope) (str | CMP_ERR) = {
    let out = "";
    let next = nxttk(f)?;
    expct(next is sym && next: sym == sym::OPEN_PAR,
        next, f, void: EXPECTD, "function parameter list declaration")?;
    // TODO: eval parameters
    next = nxttk(f)?;
    expct(next is sym && next: sym == sym::CLOSEPAR,
        next, f, void: EXPECTD, "end of function parameter list")?;
    
    next = nxttk(f)?;
    expct(next is opr && next: opr == opr::CASTTOTP,
        next, f, void: EXPECTD, "function return type declaration")?;
    
    next = nxttk(f)?;
    const ret = expct(is_type(next), next, f, void: EXPECTD,
        "valid function return type")?: kwd;
    
    // TODO: effect tags
    // TODO: enforce 0 parameters for main
    if(dest == "main"){
        if(ret == kwd::UNITTYPE){
            // TODO: implement ctxt variable here
            let fn_scp = scope {
                over = scp,
                defs = [],
            };
            next = nxttk(f)?;
            const bgn = expct(next is sym && next: sym == sym::OPN_CRLY,
                next, f, void: EXPECTD, "function body declaration")?: sym;

            const body = parse(f, &fn_scp, mtchs(f, bgn)?)?;
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
            defs = [],
        };
        const body = parse(f, &fn_scp)?;
        out = fmt::asprintf("function {} ${}(){{\n@start\n{}}}\n", tptob(ret), dest, body);
    };
    return out;
};

fn is_type(_tp: (tok | eof)) bool = {
    if(!(_tp is kwd)) return false;
    const tp = _tp: kwd;
    switch(tp){
    case kwd::U8__TYPE, kwd::U16_TYPE, kwd::U32_TYPE, kwd::U64_TYPE, kwd::I8__TYPE,
        kwd::I16_TYPE, kwd::I32_TYPE, kwd::I64_TYPE, kwd::RATIO__T, kwd::UNITTYPE =>
        return true;
    case => return false;
    };
};

fn is_subt(tp: kwd, set: kwd) bool = {
    switch(set){
    case kwd::U8__TYPE, kwd::U16_TYPE, kwd::U32_TYPE,
        kwd::U64_TYPE =>
        return is_num(tp);
    case kwd::I8__TYPE, kwd::I16_TYPE, kwd::I32_TYPE,
        kwd::I64_TYPE, kwd::NUMBER_T =>
        return is_num(tp) || is_num(tp, true);
    case =>
        assert(false);
        return false;
    };
};

fn castable(z: kwd, f: kwd) bool = {
    if((is_num(z) || is_num(z, true)) &&
        (is_num(f) || is_num(f, true))) return true;
    return z == f;
};

fn cast_err(s: kwd, d: kwd) str = {
    const src =
        if(s == kwd::NUMBER_T){
            yield "number literal";
        } else {
            yield kwdv[s];
        };
    const dst =
        if(d == kwd::NUMBER_T){
            yield "number literal";
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
