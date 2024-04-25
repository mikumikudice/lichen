use fmt;
use strings;
use strconv;
use encoding::utf8;

fn todo(f: *file) (void | CMP_ERR) = {
    let t = nxttk(f)?;
    for(!(t is eol)){
        t = nxttk(f)?;
    };
};

@test fn subtypes() void = {
    // invalid down-casting
    assert(subtp(kwd::U8__TYPE, kwd::I8__TYPE) == false);
    assert(subtp(kwd::U64_TYPE, kwd::U8__TYPE) == false);

    // valid down-casting
    assert(subtp(kwd::U8__TYPE, kwd::U8__TYPE) == true);
    assert(subtp(kwd::U8__TYPE, kwd::U64_TYPE) == true);
    assert(subtp(kwd::U32_TYPE, kwd::U64_TYPE) == true);
    assert(subtp(kwd::U32_TYPE, kwd::NOT_KWRD) == true);
    assert(subtp(kwd::NOT_KWRD, kwd::STRING_T) == true);

    // invalid string down-casting
    assert(subtp(num_t, kwd::STRING_T) == false);
    assert(subtp(kwd::STRING_T, num_t) == false);
    assert(subtp(kwd::STRING_T, kwd::U64_TYPE) == false);
    assert(subtp(kwd::U64_TYPE, kwd::STRING_T) == false);
};

fn nsttos(vtp: nmsp_t) str = {
    match(vtp){
    case let k: kwd =>
        switch(k){
        case kwd::NIL_TYPE =>
            return "TODO: nil literal";
        case kwd::RATIO__T =>
            return "TODO: ratio literals";
        case =>
            return kwdv[k];
        };
    case => return "TODO";
    };
};

fn getdefval(vtp: nmsp_t) str = {
    match(vtp){
    case let k: kwd =>
        switch(k){
        case kwd::NIL_TYPE =>
            return "TODO: nil literal";
        case kwd::RATIO__T =>
            return "TODO: ratio literals";
        case kwd::U8__TYPE, kwd::U16_TYPE, kwd::U32_TYPE, kwd::U64_TYPE,
            kwd::I8__TYPE, kwd::I16_TYPE, kwd::I32_TYPE, kwd::I64_TYPE =>
                return "0";
        case kwd::STRING_T =>
                return "\"\"";
        case =>
            assert(false);
            return "";
        };
    };
};

let glob_ns: []nmsp = [];
fn push_idt(name: str, vtp: nmsp_t, scp: (*[]nmsp | void),f: *file) (str | CMP_ERR) = {
    const host = match(scp){
        case let s: *[]nmsp => yield s;
        case => yield &glob_ns;
    };
    match(get_idt(name, host)){
    case let ns: *nmsp =>
        if(subtp(ns.nstype, vtp)){
            return nsttos(ns.nstype);
        } else {
            match(vtp){
            case let k: kwd =>
                assert(k != kwd::NOT_KWRD);
                switch(k){
                case kwd::U8__TYPE, kwd::U16_TYPE,
                    kwd::U32_TYPE, kwd::U64_TYPE =>
                    if(subtp(kwd::U64_TYPE, ns.nstype)){
                        return unimsg {
                            msg = "expression typesaaaaaaaaa",
                            tip = "you need to explicitly cast bigger types to smaller types",
                            ptr = f,
                        }: MISMTCH;
                    } else if(subtp(kwd::I64_TYPE, ns.nstype)){
                        return unimsg {
                            msg = "expression types",
                            tip = "you need to explicitly cast signed types to unsigned types",
                            ptr = f,
                        }: MISMTCH;
                    } else {
                        return unimsg {
                            msg = "expression types",
                            tip = "these are not subtypes of each other",
                            ptr = f,
                        }: MISMTCH;
                    };
                case => return f: UNREACH;
                };
            };
        };
    case void =>
        append(host, nmsp {
            idntfr = name,
            nstype = vtp,
            atline = f.lin,
            atcoln = f.cln,
        });
        return nsttos(vtp);
    };
};

fn get_idt(name: str, scp: (*[]nmsp | void) = void) (*nmsp | void) = {
    const host =
        match(scp){
        case let s: *[]nmsp => yield s;
        case => yield &glob_ns;
        };
    for(let i &.. host){
        if(strings::compare(i.idntfr, name) == 0) return i;
    };
};

// TODO: unions and record definitions for further type checking

let defd_fn: []*func = [];
fn get_func(name: str, f: *file) (*func | void) = {
    const max = len(defd_fn);
    for(let i = 0: size; i < max; i += 1){
        if(strings::compare(defd_fn[i].fnname, name) == 0){
            return defd_fn[i];
        };
    };
};

fn pushfunc(name: str, lin: size, cln: size, f: *file) (void | CMP_ERR) = {
    match(get_func(name, f)){
        case void =>
            const dup = get_idt(name, void);
            if(dup is *nmsp){
                const ns = dup: *nmsp;
                f.lin = lin;
                f.cln = cln;
                return unimsg {
                    msg = name,
                    tip = fmt::asprintf("the first definition is at {}:{}:{}",
                        f.name, ns.atline + 1, ns.atcoln + 1),
                    ptr = f,
                }: IDTCDUP;
            } else {
                append(defd_fn, parse_fn(name, lin, cln, f)?);
            };
        case let fun: *func =>
            f.lin = lin;
            f.cln = cln;
            return unimsg {
                msg = name,
                tip = fmt::asprintf("the first definition is at {}:{}:{}",
                    f.name, fun.atline + 1, fun.atcoln + 1),
                ptr = f,
            }: IDTCDUP;
    };
};

fn parse(from: (str | *file), within: (*func | void) = void) ((str, nmsp_t) | CMP_ERR) = {
    const src = match(from){
        case str => yield load(from: str)?;
        case *file => yield from: *file;
    };
    const max = len(src.src);
    // define all constant fields at global scope
    const global = within is void;
    const dupf = alloc(*src);
    for(dupf.ptr < max){
        const dummy = nxttk(dupf)?;
        if(dummy is idt){
            const lin = dupf.lin;
            const cln = dupf.cln;
            const name = dummy: idt: str;
            const oper = nxttk(dupf)?;
            if(!(oper is opr && oper: opr == opr::ASSIGNMT)) continue;

            const keyw = nxttk(dupf)?;
            if(!(keyw is kwd && keyw: kwd == kwd::FUNCTION)) continue;

            pushfunc(name, lin, cln, dupf)?;
        };
    };
    free(dupf);

    let (out, scope) =
        if(global){
            yield ("; moss 0.0.1 => mio 0.0.1\n", &glob_ns);
        } else {
            yield ("", alloc([]: []nmsp));
        };
    const ret_tp = kwd::NOT_KWRD: nmsp_t;
    const ident =
        if(global){
            yield "";
        } else {
            yield "    ";
        };
    for(src.ptr < max){
        const tkn = match(nxttk(src)?){
            case eof => break;
            case let t: tok =>
                //fmt::println(tktostr(t, true))!;
                yield t; 
        };
        match(tkn){
        case let name: idt =>
            out = fmt::asprintf("{}{}", out,
                parse_asg(src, name, scope, global)?);
        case kwd =>
            switch(tkn: kwd){
            case kwd::PUBFIELD =>
                if(!global){
                    return unimsg {
                        msg = "export variables local to a functions",
                        tip = "try exporting these fields at global scope",
                        ptr = src,
                    }: CANT_DO;
                };
                const lin = src.lin;
                const cln = src.cln;

                const name = nxttk(src)?;
                expct(name is idt, name, src, void: EXPECTD, "valid lefthand")?;

                const oper = nxttk(src)?;
                expct(oper is opr && oper: opr == opr::ASSIGNMT,
                    oper, src, void: EXPECTD, "assignment operator")?;

                out = fmt::asprintf("{}pub {}", out,
                    parse_asg(src, name: idt: str, scope, global)?);

            case kwd::RETURNTO =>
                // TODO: handle expressions on ret statemenmts
                const val = nxttk(src)?;
                expct(val is num || val is txt || val is idt || val is eol, val, src,
                    void: EXPECTD, "valid return value")?;
                
                if(val is eol){
                    // TODO: do return type checking for named returns
                    out = fmt::asprintf("{}    ret\n", out);
                    continue;
                };
                const ismain =
                    match(within){
                    case void => yield false;
                    case let fun: *func =>
                        yield strings::compare(fun.fnname, "main") == 0;
                    };
                match(val: tok){
                case let n: num =>
                    ret_tp = num_t;
                    if(ismain){
                        out = fmt::asprintf("{}    exit({})\n", out, n: u64);
                    } else {
                        out = fmt::asprintf("{}    %0 = {}\n    ret\n", out, n: u64);
                    };
                case let t: txt =>
                    if(ismain){
                        return unimsg {
                            msg = "main function must return only numerical values or nil",
                            tip = void,
                            ptr = src,
                        }: GENERIC;
                    };
                    ret_tp = kwd::STRING_T;
                    out = fmt::asprintf("{}    %0 = {}\n    ret\n", out, tostr(t: []u8));
                case let i: idt =>
                    match(get_idt(i: str, scope)){
                    case void =>
                        return unimsg {
                            msg = i: str,
                            tip = void,
                            ptr = src,
                        }: UNDEFNS;
                    case let ns: *nmsp =>
                        ret_tp = ns.nstype;
                        if(!subtp(ret_tp, num_t) && !typeeq(ret_tp, kwd::NIL_TYPE)){
                            return unimsg {
                                msg = "main function must return only numerical values or nil",
                                tip = void,
                                ptr = src,
                            }: GENERIC;
                        };
                        if(ismain){
                            out = fmt::asprintf("{}    exit({})\n", out, i: str);
                        } else {
                            out = fmt::asprintf("{}    %0 = {}\n    ret\n", out, i: str);
                        };
                    };
                };
            case => todo(src)?; // void;
            };
        case sym =>
            switch(tkn: sym){
            case sym::CLS_CRLY => break;
            case => todo(src)?; // void;
            };
        case txt =>
            return bi_msg {
                lft = "valid expression or statement",
                rgt = tktostr(tkn, false),
                tip = void,
                ptr = src,
            }: EXPECTD;
        case num =>
            return bi_msg {
                lft = "valid expression or statement",
                rgt = tktostr(tkn, false),
                tip = void,
                ptr = src,
            }: EXPECTD;
        case opr =>
            return bi_msg {
                lft = "valid expression or statement",
                rgt = tktostr(tkn, false),
                tip = void,
                ptr = src,
            }: EXPECTD;
        case eol => void;
        };
    };
    if(!global) free(scope);
    return (out, ret_tp);
};

fn parse_fn(fname: str, lin: size, cln: size, f: *file) (*func | CMP_ERR) = {
    noeol(f, "function parameter definition")?;
    const opn_par = nxttk(f)?: tok;
    expct(opn_par is sym && opn_par: sym == sym::OPEN_PAR,
        opn_par, f, void: EXPECTD, "function parameter definition")?;
    
    for(true){
        noeol(f, "a valid function parameter definition")?;
        const next = nxttk(f)?: tok;
        match(next){
            case sym =>
                if(next: sym == sym::CLOSEPAR) break;
            case => void; // TODO: handle parameters
        };
    };
    noeol(f, "function return type definition")?;
    const comma = nxttk(f)?: tok;
    expct(comma is sym && comma: sym == sym::CASTTOTP,
        comma, f, void: EXPECTD, "function return type definition")?;
    
    noeol(f, "function return type definition")?;
    const ret_tp = nxttk(f)?: tok;
    expct(ret_tp is kwd, ret_tp, f, void: EXPECTD,
        "function return type definition")?;

    // TODO: handle user-defined types
    // TODO: handle named and multiple returns
    if(ret_tp: kwd >= kwd:: U8__TYPE && ret_tp: kwd <= kwd::NIL_TYPE){
        return alloc(func {
            fnname = fname,
            params = []: []nmsp_t,
            retrns = alloc([ ret_tp: kwd ]),
            atline = lin,
            atcoln = cln,
        });
    } else {
        // TODO: handle invalid return types  
        return unimsg {
            msg = "proper handling for function return types not implemented",
            tip = void,
            ptr =  f,
        }: GENTODO;
    };
};

fn gen_args(fun: *func) str = {
    const out = "";
    // TODO
    return out;
};

fn gen_rets(fun: *func) str = {
    const out = "";
    return nsttos((fun.retrns)[0]: nmsp_t);
};

fn parse_asg(f: *file, dest: str, scp: (*[]nmsp | void), global: bool) (str | CMP_ERR) = {
    let out = "";
    const ident =
        if(global){
            yield "";
        } else {
            yield "    ";
        };
    const vall = nxttk(f)?;
    match(vall: tok){
    case let keyw: kwd =>
        switch(keyw){
        case kwd::FUNCTION =>
            if(!global){
                return unimsg {
                    msg = "functions can't be defined within other functions (for now)",
                    tip = "try to define this function at global scope",
                    ptr = f,
                }: CANT_DO;
            };
            jmpto(sym::OPN_CRLY, f)?; // TODO: make sure there are no edge cases
            const fndef = get_func(dest, f): *func;
            const (body, r_tp) = parse(f, fndef)?;
            iseol(f)?;

            // TODO: handle multiple returns
            assert(fndef.retrns[0] is kwd);
            if(!typeeq(fndef.retrns[0]: nmsp_t, r_tp)){
                return unimsg {
                    msg = "function return type and function body evaluatable type",
                    tip = void,
                    ptr = f,
                }: MISMTCH;
            };
            const args = gen_args(fndef);
            const rets = gen_rets(fndef);
            out = fmt::asprintf("{} {} = {}\n{}\n", dest, args, rets, body);

        case kwd::NIL_TYPE => void; // TODO
        case =>
            return bi_msg {
                lft = "attribution value",
                rgt = tktostr(vall, true),
                tip = void,
                ptr = f,
            }: EXPECTD;
        };
    case let oper: opr =>
        switch(oper){
        case opr::ASSIGNMT =>
            const inittp =
                match(get_idt(dest, scp)){
                case void => yield kwd::NOT_KWRD: nmsp_t;
                case let v: *nmsp => yield v.nstype;
                };
            const (vvalue, var_tp, pos) = parse_exp(f, scp, inittp)?;
            const deftp = push_idt(dest, var_tp, scp, pos)?;
            free(pos);

            if(inittp: kwd == kwd::NOT_KWRD){
                out = fmt::asprintf("{}{} {} ={}\n", ident, deftp, dest, vvalue);
            } else {
                out = fmt::asprintf("{}{} ={}\n", ident, dest, vvalue);
            };
        case opr::INCREMNT, opr::DECREMNT,
            opr::MULTIPLY, opr::DIVIDEBY =>
            const inittp =
                match(get_idt(dest, scp)){
                case let v: *nmsp => yield v.nstype;
                case void =>
                    return unimsg {
                        msg = "operate on undefined variables",
                        tip = "define this variable before using this operator",
                        ptr = f,
                    }: CANT_DO;
                };
            const (value, var_tp, pos) = parse_exp(f, scp, inittp)?;
            const deftp = push_idt(dest, var_tp, scp, pos)?;
            free(pos);

            out = fmt::asprintf("{}{} {}{}\n", ident, dest, oprv[oper], value);
        case =>
            return bi_msg {
                lft = "assignment operator",
                rgt = tktostr(oper, true),
                tip = void,
                ptr = f,
            }: EXPECTD;
        };
    case let symb: sym =>
        if(symb == sym::CASTTOTP){
            const inittp =
                match(get_idt(dest, scp)){
                case void => yield kwd::NOT_KWRD: nmsp_t;
                case let v: *nmsp => yield v.nstype;
                };
            const next = nxttk(f)?;
            expct(next is kwd,
                next, f, void: EXPECTD, "valid variable type")?;

            const cast  = next: tok: kwd: nmsp_t;
            const deftp = push_idt(dest, cast, scp, f)?;
            const value = getdefval(cast);

            out = fmt::asprintf("{}{}{} {} = {}\n", out, ident, deftp, dest, value);
        } else {
            return bi_msg {
                lft = "valid variable declaration path",
                rgt = tktostr(symb, true),
                tip = "the syntax for declaration without assigment is `<var> : <type>`",
                ptr = f,
            }: EXPECTD;
        };
    case => assert(false);
    };
    return out;
};

fn parse_exp(f: *file, scp: (*[]nmsp | void), dest_t: nmsp_t) ((str, nmsp_t, *file) | CMP_ERR) = {
    const dup = alloc(*f);
    let exp = "";
    let next = nxttk(f)?;
    let swtch = false;
    let depth = 0;
    let exptp = kwd::NOT_KWRD: nmsp_t;
    for(!(next is eol || next is eof); next = nxttk(f)?){
        match(next: tok){
        case let n: num =>
            if(!swtch){
                // TODO: you need to explicitly cast signed types to unsigned types
                if(subtp(exptp, num_t)){
                    exp = fmt::asprintf("{} {}", exp, n: u64);
                    exptp = num_t;
                    swtch = true;
                } else {
                    return unimsg {
                        msg = "expression types",
                        tip = genmismatch(exptp),
                        ptr = f,
                    }: MISMTCH;
                };
            } else {
                return bi_msg {
                    lft = "expression continuation",
                    rgt = tktostr(next: tok, false),
                    tip = void,
                    ptr = f,
                }: EXPECTD;
            };
        case let t: txt =>
            if(!swtch){
                if(subtp(exptp, kwd::STRING_T)){
                    exp = fmt::asprintf("{} {}", exp, tostr(t: txt));
                    exptp = kwd::STRING_T;
                    swtch = true;
                } else {
                    return unimsg {
                        msg = "expression types",
                        tip = "you can't make arithmetic operations on strings",
                        ptr = f,
                    }: MISMTCH;
                };
            } else {
                return bi_msg {
                    lft = "expression continuation",
                    rgt = tktostr(next: tok, false),
                    tip = void,
                    ptr = f,
                }: EXPECTD;
            };
        case let i: idt =>
            if(!swtch){
                const var = get_idt(i: str, scp);
                match(var){
                case let ns: *nmsp =>
                    match(ns.nstype){
                    case let ths_t: kwd =>
                        // check for casting
                        // TODO: handle parenthesis expressions
                        setptr(f);
                        next = nxttk(f)?;
                        match(next){
                        case tok =>
                            if(next is sym && next: sym == sym::CASTTOTP){
                                next = nxttk(f)?;
                                expct(next is kwd, next, f, void: EXPECTD,
                                    "valid casting type")?;

                                const cast = next: tok: kwd;
                                if(kwd::U8__TYPE <= cast && cast <= kwd::NIL_TYPE){
                                    ths_t = cast;
                                } else {
                                    return bi_msg {
                                        lft = "valid casting type",
                                        rgt = tktostr(cast, false),
                                        tip = void,
                                        ptr = f,
                                    }: EXPECTD;
                                };
                            } else {
                                // invalid paths are going to be handled onwards
                                setptr(f, true);
                            };
                        // invalid paths are going to be handled onwards
                        case => setptr(f, true);
                        };

                        if(subtp(ths_t, exptp)){
                            // TODO: actually cast signed types on output
                            exp = fmt::asprintf("{} {}", exp, i: str);
                            exptp = ths_t;
                            swtch = true;
                            continue;
                        } else {
                            return unimsg {
                                msg = "expression types",
                                tip = genmismatch(exptp),
                                ptr = f,
                            }: MISMTCH;
                        };
                    };
                case =>
                    return unimsg {
                        msg = i: str,
                        tip = void,
                        ptr = f,
                    }: UNDEFNS;
                };
            } else {
                return bi_msg {
                    lft = "expression continuation",
                    rgt = tktostr(next: tok, false),
                    tip = void,
                    ptr = f,
                }: EXPECTD;
            };
        case let o: opr =>
            switch(o){
            case opr::ARTH_PLS =>
                if(subtp(kwd::STRING_T, exptp)){
                    exp = fmt::asprintf("{} +", exp);
                    swtch = false;
                    continue;
                } else {
                        return unimsg {
                        msg = "do concatenations with values other than strings",
                        tip = void,
                        ptr = f,
                    }: CANT_DO;
                };
            case =>
                exp = fmt::asprintf("{} {}", exp, oprv[o]);
                swtch = false;
                continue;
            };
        case let s: sym =>
            switch(s){
            case sym::SEMICLNS => break;
            case sym::CASTTOTP =>
                // TODO: actually cast signed types on output
                next = nxttk(f)?;
                expct(next is kwd, next, f, void: EXPECTD,
                    "valid casting type")?;
                const cast = next: tok: kwd;
                if(kwd::U8__TYPE <= cast && cast <= kwd::NIL_TYPE){
                    if(subtp(cast, exptp) ||
                        (subtp(cast, num_t) && subtp(exptp, num_t))){
                        exptp = cast;
                    } else {
                        return unimsg {
                            msg = "expression types",
                            tip = invcast(exptp, cast),
                            ptr = f,
                        }: MISMTCH;
                    };
                } else {
                    return bi_msg {
                        lft = "valid casting type",
                        rgt = tktostr(cast, false),
                        tip = void,
                        ptr = f,
                    }: EXPECTD;
                };

            case => assert(false, symv[s]);
            };
        case => void;
        };
    };
    if(!swtch){
        return bi_msg {
            lft = "expression continuation",
            rgt = tktostr(next: tok, false),
            tip = void,
            ptr = f,
        }: EXPECTD;
    };
    if(len(exp) == 0){
        return bi_msg {
            lft = "valid righthand",
            rgt = tktostr(next, false),
            tip = void,
            ptr = f
        }: EXPECTD;
    };
    if(subtp(exptp, dest_t)){
        if(dest_t is kwd && dest_t: kwd != kwd::NOT_KWRD)
            return (exp, dest_t, dup);
        return (exp, exptp, dup);
    } else {
        return unimsg {
            msg = "expression types",
            tip = invcast(exptp, dest_t),
            ptr = dup,
        }: MISMTCH;
    };
};

fn nxttk(f: *file, rev: bool = false) (tok | eof | CMP_ERR) = {
    let onstr = false;
    let escpd = false;

    if(rev) setptr(f);

    let tkv: []u8 = [];
    f.cln = f.end;

    const max = len(f.src);
    if(f.ptr >= max) return eol;

    for(f.ptr < max; incptr(f, onstr)){
        const chr = f.src[f.ptr];

        if(onstr){
            // TODO: add support for character literals
            let (s, e) = parse_str(chr, &tkv, onstr, escpd);
            onstr = s; escpd = e;
            if(!onstr){
                incptr(f, false);
                return tkv: txt;
            };
        } else {
            if(iswsp(chr)){
                continue;
            } else if(chr == '"'){
                onstr = true;
                continue;
            } else if(chr == ';'){
                incptr(f, false);
                return eol;
            } else {
                // comments
                // TODO: multiple line comments
                if(chr == '/' && f.src[f.ptr + 1] == '/'){
                    f.lin += 1;
                    f.end = 0;

                    f.ptr += finda(tostr(f.src), "\n", f.ptr)! + 1;
                    f.lst = f.ptr;
                    return eol;
                };
                // just text
                if(istxt(chr)){
                    append(tkv, chr);

                    // it's the last valid character
                    if(f.ptr == max - 1 || !istxt(f.src[f.ptr + 1])){
                        let val = tostr(tkv);
                        for(let k = 0; k < kwd::KWRD_END; k += 1){
                            if(strings::compare(val, kwdv[k]) == 0){
                                incptr(f, false);
                                return k: kwd;
                            };
                        };
                        // TODO: handle different numerical bases
                        match(strconv::stou64(replace(val, "_", ""))){
                        case let n: u64 =>
                            incptr(f, false);
                            return n: num;
                        case =>
                            incptr(f, false);
                            return val: idt;
                        };
                    };
                } else {
                    let idx = f.ptr;
                    for(idx < max; idx += 1){
                        const nxtc = f.src[idx];
                        if(istxt(nxtc) || iswsp(nxtc)){
                            break;
                        };
                    };
                    assert(idx > f.ptr);

                    const slc = tostr(f.src[f.ptr..(idx)]);
                    let last = 0: size;

                    let oprc = opr::NOT_OPER;
                    for(let o = 0; o < opr::OPER_END; o += 1){
                        const olen = len(oprv[o]);
                        if(olen > len(slc)) continue;

                        const sub = strings::sub(slc, 0, len(oprv[o]));
                        if(strings::compare(sub, oprv[o]) == 0){
                            oprc = o: opr;
                            last = olen;
                        };
                    };
                    if(oprc != opr::NOT_OPER){
                        f.ptr += last - 1;
                        f.end += last - 1;
                        incptr(f, false);
                        return oprc;
                    };

                    let symc = sym::NOT_SYMB;
                    for(let s = 0; s < sym::SYMB_END; s += 1){
                        const slen = len(symv[s]);
                        if(slen > len(slc)) continue;

                        const sub = strings::sub(slc, 0, slen);
                        if(strings::compare(sub, symv[s]) == 0){
                            symc = s: sym;
                            last = slen;
                        };
                    };
                    if(symc != sym::NOT_SYMB){
                        f.ptr += last - 1;
                        f.end += last - 1;
                        incptr(f, false);
                        return symc;
                    };

                    return bi_msg {
                        lft = "valid identifier, keyword, operator or symbol",
                        rgt = fmt::asprintf("\"{}\"", slc),
                        tip = void,
                        ptr = f,
                    }: EXPECTD;
                };
            };
        };
    };
    if(f.ptr >= max) return eof;

    assert(false, "unhandled lexer path");
    return eol;
};

fn expct(eql: bool, tk: (tok | eof), f: *file, e: CMP_ERR, msg: str, tip: (str | void) = void) (void | CMP_ERR) = {
    if(!eql){
        match(e){
        case INVALID =>
            return unimsg {
                msg = msg,
                tip = tip,
                ptr = f,
            }: INVALID;
        case EXPECTD =>
            return bi_msg {
                lft = msg,
                rgt = tktostr(tk, false),
                tip = tip,
                ptr = f,
            }: EXPECTD;
        case GENERIC =>
            return unimsg {
                msg = msg,
                tip = tip,
                ptr = f,
            }: GENERIC;
        case =>
            return f: UNREACH;
        };
    };
};

fn jmpto(t: tok, f: *file) (void | CMP_ERR) = {
    for(let next = nxttk(f)?;
        !(next is eol || next is eof)
        && !cmp_tok(next: tok, t); next = nxttk(f)?) { void; };
};

fn iseol(f: *file) (void | CMP_ERR) = {
    const dummy = nxttk(f)?;
    if(dummy is eof) return;
    expct(dummy is eol, dummy: tok, f, void: EXPECTD, tktostr(eol, false))?;
};

fn noeol(f: *file, msg: str, tip: (str | void) = void) (void | CMP_ERR) = {
    setptr(f);
    const dummy = nxttk(f)?;

    if(dummy is eof || dummy is eol){
        return bi_msg {
            lft = msg,
            rgt = "end of file",
            tip = tip,
            ptr = f,
        }: EXPECTD;
    } else {
        setptr(f, true);
    };
};

fn subtp(_this: nmsp_t, _that: nmsp_t) bool = {
    for(let this .. solve(_this))
    for(let that .. solve(_that)){
        if(this == kwd::NOT_KWRD || that == kwd::NOT_KWRD) return true;
        switch(that){
        case kwd::U8__TYPE, kwd::U16_TYPE,
            kwd::U32_TYPE, kwd::U64_TYPE =>
            if((kwd::U8__TYPE <= this && this <= that) ||
                this == kwd::NUMBER_T) return true;

        case kwd::I8__TYPE, kwd::I16_TYPE, 
            kwd::I32_TYPE, kwd::I64_TYPE =>
            if((kwd::I8__TYPE <= this && this <= that) ||
                this == kwd::NUMBER_T) return true;

        case kwd::RATIO__T =>
            if(this == kwd::RATIO__T ||
                subtp(kwd::U16_TYPE, this) ||
                this == kwd::NUMBER_T) return true;

        case kwd::STRING_T, kwd::NIL_TYPE =>
            if(this == that) return true;
        case kwd::NUMBER_T =>
            if(kwd::U8__TYPE <= this &&
                this <= kwd::RATIO__T) return true;
        case =>
            assert(false);
            return false;
        };
    };
    return false;
};

fn typeeq(_this: nmsp_t, _that: nmsp_t) bool = {
    const this_l = solve(_this);
    const that_l = solve(_that);

    if(len(this_l) != len(that_l)) return false;
    for(let this .. this_l)
    for(let that .. that_l){
        switch(that){
        case kwd::NOT_KWRD =>
            assert(false);
            return false;
        case kwd::NUMBER_T =>
            if(!(kwd::U8__TYPE <= this &&
                this <= kwd::RATIO__T)) return false;
        case =>
            if(this != that && !subtp(this, num_t)) return false;
        };
    };
    return true;
};

fn genmismatch(tp: nmsp_t) (str | void) = {
    if(subtp(num_t, tp)){
        return "you need to explicitly cast bigger types to smaller types";
    } else if(subtp(kwd::STRING_T, tp)){
        return "you can't make arithmetic operations on strings";
    };
};

fn invcast(this: nmsp_t, that: nmsp_t) (str | void) = {
    if(typeeq(this, kwd::STRING_T) &&
        typeeq(that, num_t)){
        return "you can't cast a string to a numerical type";
    } else if(typeeq(this, num_t) &&
        typeeq(that, kwd::STRING_T)){
        return "you can't cast a numerical value to a string";
    } else if(typeeq(this, kwd::NIL_TYPE) ||
        typeeq(that, kwd::NIL_TYPE)){
        return "you can't cast a non-union type to nil";
    } else {
        assert(false);
    };
};

// TODO: make solve accept user-defined types (i.e. idt types)
fn solve(this: nmsp_t) []kwd = {
    match(this){
    case num_t => return [ kwd::NUMBER_T ];
    case let k: kwd => return [ k ];
    case =>
        assert(false);
        return [];
    };
};

fn setptr(f: *file, reset: bool = false) void = {
    static let safe_l = 0: size;
    static let safe_p = 0: size;
    static let safe_c = 0: size;
    static let safe_e = 0: size;
    static let safels = 0: size;

    if(!reset){
        safe_l = f.lin;
        safe_p = f.ptr;
        safe_c = f.cln;
        safe_e = f.end;
        safels = f.lst;
    } else {
        f.lin = safe_l;
        f.ptr = safe_p;
        f.cln = safe_c;
        f.end = safe_e;
        f.lst = safels;
    };
};

fn incptr(f: *file, onstr: bool) void = {
    const max = len(f.src);
    f.end += 1;
    f.ptr += 1;

    if(!onstr)
    for(f.ptr < max){
        const chr = f.src[f.ptr];
        if(chr == '\n'){
            f.lst = f.ptr + 1;
            f.lin += 1;
            f.ptr += 1;
            f.end = 0;
        } else if(iswsp(chr)){
            f.end += 1;
            f.ptr += 1;
        } else break;
    };
};
