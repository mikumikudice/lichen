use bufio;
use fmt;
use fs;
use io;
use memio;
use os;
use strings;

// qbe_t modes
type mode = enum u8 { REAL, ASSIGN, LOAD, RETURN };

// returns the qbe equivalent of a given type. changing the mode to
// ASSIGN rounds types smaller than a word to a word, and to LOAD
// adds a sign prefix to the type
fn qbe_t(tpe: lichen_t, md: mode = mode::REAL) str = {
    if(tpe.base is primitive){
        assert(tpe.base as primitive != primitive::ANY);
        if(tpe.fail && md == mode::RETURN) return ":opt";
        switch(tpe.base as primitive){
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
        case primitive::F32 =>
            return "s";
        case primitive::F64 =>
            return "d";
        case primitive::U64, primitive::I64, primitive::STR,
            primitive::CSTR, primitive::BOOL, primitive::NUMBER =>
            return "l";
        case primitive::RATIO =>
            return "d";
        case primitive::UNIT, primitive::VOID =>
            return "l";
        case =>
            color_error("%Runreachable:%r unknown type %y{}",
                prim_value[tpe.base as primitive]);
        };
    } else {
        return "l";
    };
};

// gets the given type's in memory type
fn type_size(tpe: lichen_t) size = {
    const arg = strtype(tpe);
    defer free(arg);
    assert(!untyped(tpe), arg);

    if(tpe.base is primitive){
        switch(tpe.base as primitive){
        case primitive::UNIT, primitive::VOID => return 0;
        case primitive::U8, primitive::I8 => return 1;
        case primitive::U16, primitive::I16 => return 2;
        case primitive::U32, primitive::I32,
            primitive::F32 => return 4;
        case primitive::U64, primitive::I64,
            primitive::F64, primitive::STR,
            primitive::CSTR, primitive::BOOL => return 8;
        case =>
            assert(false, "unreachable");
            return 0;
        };
    } else if(tpe.base is *record){
        const rec = tpe.base as *record;
        let length = 0z;
        todo("records");
    } else if(tpe.base is *array){
        const arr = tpe.base as *array;
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

// checks if there's a type mismatch for assignment between two given types
fn size_mismatch(src: lichen_t, dest: lichen_t) bool = {
    if(is_subtype(src, primitive::NUMBER) &&
        is_subtype(dest, primitive::NUMBER)){
        if(untyped(src) || untyped(dest)) return false;
        return type_size(src) < type_size(dest);
    };
    return type_size(src) != type_size(dest);
};

// casts an integer to a floating type
fn itof(int_t: lichen_t, float_t: lichen_t) str = {
    // unsigned
    if(is_subtype(primitive::U8, int_t)){
        if(type_size(int_t) == 4) return "uwtof";
        return "ultof";
    // signed
    } else {
        if(type_size(int_t) == 4) return "swtof";
        return "sltof";
    };
};

// casts a floating type to an integer
fn ftoi(float_t: lichen_t, int_t: lichen_t) str = {
    // unsigned
    if(is_subtype(primitive::U8, int_t)){
        fmt::println(strtype(float_t), strtype(int_t))!;
        if(type_size(int_t) == 4) return "stoui";
        return "dtoui";
    // signed
    } else {
        if(type_size(int_t) == 4) return "stosi";
        return "dtosi";
    };
};

fn emit_obj(
    ir: *memio::stream,
    also_link: []str,
    target_file: str,
    lib_path: str,
    shared_lib: bool,
    static_lib: bool,
    silent: bool
) void = {
    const link_args = []: []str;
    defer free(link_args);
    defer for(let obj ..& link_args) free(obj);

    const obj_name =
        if(strings::index(target_file, "/") is size){
            yield strings::rcut(target_file, "/").1;
        } else {
            yield target_file;
        };
    // generate temporary file names
    const qbe_out = fmt::asprintf("{}{}.ssa", temp, obj_name)!;
    defer free(qbe_out);
    const asm_src = fmt::asprintf("{}{}.s", temp, obj_name)!;
    defer free(asm_src);
    const obj_out = fmt::asprintf("{}{}.o", temp, obj_name)!;
    append(link_args, strings::dup(obj_out)!)!;
    // a final executable
    if(!static_lib && !shared_lib){
        for(let l .. ["-o", target_file]){
            append(link_args, strings::dup(l)!)!;
        };
        if(len(also_link) > 0){
            for(let l .. ["--dynamic-linker", "/usr/lib64/ld-linux-x86-64.so.2"]){
                append(link_args, strings::dup(l)!)!;
            };
        };
    // a static library archive
    } else if(static_lib){
        for(let l .. ["-r", "-o"]){
            append(link_args, strings::dup(l)!)!;
        };
        append(link_args, fmt::asprintf("{}.o", obj_name)!)!;
    // a shared library
    } else {
        for(let l .. ["-shared", "-fPIC", "--export-dynamic", "-o"]){
            append(link_args, strings::dup(l)!)!;
        };
        append(link_args, fmt::asprintf("{}.so", obj_name)!)!;
    };
    for(let obj .. also_link){
        append(link_args, strings::dup(obj)!)!;
    };

    // create temporary directory
    run_cmd(silent, "mkdir", "-p", temp);
    // emit final IR file
    const object =
        match(os::create(qbe_out, fs::mode::USER_RWX)){
        case let f: io::file => yield f;
        case let e: fs::error =>
            color_error("%Robject emition error:%b {}%r: {}",
                qbe_out, fs::strerror(e));
        };
    io::write(object, strings::toutf8(memio::string(ir)!))!;
    io::close(object)!;
    // emit assembly
    run_cmd(silent, "qbe", "-o", asm_src, qbe_out);

    // append runtime to assembly emittion
    const rt_src = strings::concat(lib_path, "rt.s")!;
    defer free(rt_src);

    const rt_file = os::open(rt_src, fs::flag::RDONLY)!;
    const rt_asm = &memio::dynamic();
    defer io::close(rt_asm)!;

    // read all runtime content, line by line
    for(true) match(bufio::read_line(rt_file)!){
    case io::EOF =>
        break;
    case let l: []u8 =>
        fmt::fprintln(rt_asm, strings::fromutf8(l)!)!;
        free(l);
    };
    io::close(rt_file)!;

    const pre_asm = &memio::dynamic();
    defer io::close(pre_asm)!;
    if(!static_lib && !shared_lib){
        const pre_src = strings::concat(lib_path, "pre.s")!;
        defer free(pre_src);

        const pre_file = os::open(pre_src, fs::flag::RDONLY)!;

        // read all runtime content, line by line
        for(true) match(bufio::read_line(pre_file)!){
        case io::EOF =>
            break;
        case let l: []u8 =>
            fmt::fprintln(pre_asm, strings::fromutf8(l)!)!;
            free(l);
        };
        io::close(rt_file)!;
    };
    // append it to the end of the file
    const asm_file = os::open(asm_src, fs::flag::RDWR | fs::flag::APPEND)!;
    io::write(asm_file, strings::toutf8(memio::string(pre_asm)!))!;
    io::write(asm_file, strings::toutf8(memio::string(rt_asm)!))!;
    io::close(asm_file)!;

    // assemble final source
    run_cmd(silent, "as" , "-o", obj_out, asm_src);
    // link it accordingly
    run_cmd(silent, "ld", link_args...);
    // final steps with static archive
    if(static_lib){
        const out = fmt::asprintf("{}.a", obj_name)!;
        defer free(out);
        const obj = fmt::asprintf("{}.o", obj_name)!;
        defer free(obj);
        run_cmd(silent, "ar", "rcs", out, obj);
        run_cmd(silent, "rm", obj);
    };
};

fn gen_qbe_ir(ctxt: *context) memio::stream = {
    const ir = memio::dynamic();
    fmt::fprintfln(&ir, "# code emitted by lcc v{}", version)!;
    fmt::fprint(&ir, "type :opt = { l, l }")!;
    gen_module(ctxt, &ir);
    for(let m .. ctxt.global.defs){
        if(m is *module_meta){
            const module = m as *module_meta;
            if(!module.emitted){
                gen_module(module.ctxt, &ir);
                module.emitted = true;
            };
        };
    };
    // emit string literals
    for(let lit = 0z; lit < len(ctxt.literals); lit += 1){
        // emit string literal
        fmt::fprintfln(&ir, "data $lit.{} = align 8 {{ b \"{}\" }}",
            lit, ctxt.literals[lit])!;
        // emit constant string value
        fmt::fprintfln(&ir,
            "data $str.{0} = align 16 {{ l {1}, l $lit.{0} }}",
            lit, true_size(ctxt.literals[lit]))!;
    };
    return ir;
};

fn gen_module(ctxt: *context, buff: *memio::stream) void = {
    for(let defn .. ctxt.global.defs){
        match(defn){
        case let meta: *decl_meta =>
            if(meta.var.nm.ffi is str) continue;
            fmt::fprint(buff, "\n")!;
            const name =
                if(!ctxt.main){
                    const mod = strings::rcut(
                        strings::rcut(ctxt.file, "/").0, ".").0;
                    yield fmt::asprintf("${}.{}", mod,
                        meta.var.nm.name)!;
                } else {
                    yield fmt::asprintf("${}", meta.var.nm.name)!;
                };
            defer free(name);
            if(meta.var.nm.pub) fmt::fprintln(buff, "export ")!;
            // gen value
            const val_meta = meta.val as *const_meta;
            const val =
                match(val_meta.val){
                case let num: size =>
                    yield
                    if(val_meta.pre is operator){
                        yield switch(val_meta.pre as operator){
                        case operator::NOT =>
                            yield fmt::asprintf("{} {}",
                                qbe_t(meta.var.nm.tpe), ~num)!;
                        case operator::PLS =>
                            yield fmt::asprintf("{} {}",
                                qbe_t(meta.var.nm.tpe), num)!;
                        case operator::MIN =>
                            yield fmt::asprintf("{} {}",
                                qbe_t(meta.var.nm.tpe), -(num: i64))!;
                        case =>
                            assert(false);
                            yield "";
                        };
                    } else {
                        yield fmt::asprintf("{} {}",
                            qbe_t(meta.var.nm.tpe), num)!;
                    };
                case let txt: str =>
                    yield if(val_meta.pre is operator){
                        yield fmt::asprintf("l {}", true_size(txt))!;
                    } else {
                        yield fmt::asprintf("l $str.{}",
                            push_lit(ctxt, txt))!;
                    };
                };
            defer free(val);
            // emit constant
            fmt::fprintfln(buff, "data {} = align 16 {{ {} }}", name, val)!;
        case let meta: *fun_meta =>
            // skip functions that should not be emitted
            if(meta.fun.ffi is str || meta.body == null) continue;
            fmt::fprint(buff, "\n")!;
            const name =
                if(meta.fun.ffi is str){
                    yield fmt::asprintf("${}",
                        meta.fun.ffi as str)!;
                } else if(ctxt.file != meta.origin || !ctxt.main){
                    const mod = strings::rcut(
                        strings::rcut(meta.origin, "/").1, ".").0;
                    yield fmt::asprintf("${}.{}", mod,
                        meta.fun.name)!;
                } else {
                    yield fmt::asprintf("${}", meta.fun.name)!;
                };
            // emit linking flags
            if(meta.fun.pub){
                fmt::fprintf(buff,
                    "dbgfile \"{}\"\nsection \".text.{}\" \"ax\"\nexport ",
                    ctxt.file, strings::sub(name, 1))!;
            } else {
                fmt::fprintfln(buff,
                    "dbgfile \"{}\"\nsection \".text.{}\" \"ax\"",
                    ctxt.file, strings::sub(name, 1))!;
            };
        // emit core declaration
        fmt::fprintf(buff, "function ")!;
        if(comp_type(meta.fun.tpe, primitive::VOID) ||
            comp_type(meta.fun.tpe, primitive::UNIT)){
            fmt::fprint(buff, name)!;
        } else {
            fmt::fprintf(buff, "{} {}",
                qbe_t(meta.fun.tpe, mode::RETURN), name)!;
        };
        const params: []*var_meta = [];
        defer free(params);
        defer for(let p .. params){
            free(p.nm.name);
            free_nodes(p);
        };
        for(let p .. meta.params){
            const dup = alloc(*p.var)!;
            dup.nm.name = strings::concat("%", dup.nm.name)!;
            append(params, dup)!;
        };
        // gen parameter list
        gen_list(buff, params);
        // gen function body scope
        gen_scope(ctxt, buff, meta.body as *scope_meta, "@start", true);
        case let meta: *module_meta => void;
        };
    };
};

fn gen_list(buff: *memio::stream, names: []*var_meta) void = {
    fmt::fprint(buff, "(")!;
    for(let n .. names){
        fmt::fprintf(buff, "{} {}, ",
            qbe_t(n.nm.tpe, mode::ASSIGN), n.nm.name)!;
    };
    fmt::fprint(buff, ")")!;
};

fn gen_scope(
    ctxt: *context,
    buff: *memio::stream,
    scope: *scope_meta,
    ini_tag: str,
    has_fail: bool = false,
) void = {
    if(has_fail) fmt::fprintfln(buff, "{{\n{}", ini_tag)!;
    for(let stt = 0z; stt < len(scope.stt); stt += 1){
        gen_stt(ctxt, buff, scope.stt[stt]);
        if(stt < len(scope.stt) - 1) fmt::fprint(buff, "\n")!;
    };
    if(comp_type(scope.tpe, primitive::VOID) && has_fail){
        fmt::fprintfln(buff, "\tcall $rt.exit(w 0)\n\thlt")!;
    } else if(!scope.rets && has_fail){
        if(comp_type(scope.tpe, quick_t(primitive::UNIT))){
            fmt::fprintln(buff, "\tret")!;
        } else if(comp_type(scope.tpe, quick_t(primitive::UNIT, true))){
            fmt::fprintln(buff, "\t%opt =l alloc8 16")!;
            fmt::fprintln(buff, "\tstorel 1, %opt")!;
            fmt::fprintln(buff, "\tret %opt")!;
        };
    };
    if(has_fail){
        fmt::fprintln(buff, "@fail\n\tcall $rt.exit(w 1)\n\thlt\n}")!;
    };
};

fn gen_stt(ctxt: *context, buff: *memio::stream, stt: path_meta) void = {
    match(stt){
    case let decl: *decl_meta =>
        gen_decl(ctxt, buff, decl);
    case let asg: *assign_meta =>
        move_ptr(ctxt, ctxt.tokens[asg.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        const wrap = fmt::asprintf("%asg.val")!;
        defer free(wrap);
        const val = gen_exp(ctxt, buff, wrap, asg.var.nm.tpe,
            asg.val);
        if(val != ""){
            fmt::fprintfln(buff, "\t{} ={} copy {}",
                fix_nm(ctxt, buff, asg.var.nm),
                qbe_t(asg.var.nm.tpe, mode::ASSIGN),
                val)!;
        } else {
            fmt::fprintfln(buff, "\t{} ={} copy {}",
                fix_nm(ctxt, buff, asg.var.nm),
                qbe_t(asg.var.nm.tpe, mode::ASSIGN),
                wrap)!;
        };
    case let branch: *branch_meta =>
        move_ptr(ctxt, ctxt.tokens[branch.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        const cond = fmt::asprintf("%cond.{}", branch.pos)!;
        for(let i = 0z; i < len(branch.bodies); i += 1){
            if(i < len(branch.conds)){
                if(branch.bodies[i].0 is *decl_meta){
                    gen_decl(ctxt, buff, branch.bodies[i].0 as *decl_meta);
                };
                gen_exp(ctxt, buff, cond, quick_t(primitive::BOOL),
                    branch.conds[i]);
                fmt::fprintfln(buff,
                    "\tjnz {0}, @true.{1}.{2}, @false.{1}.{2}", cond,
                    branch.pos, i)!;
                fmt::fprintfln(buff, "@true.{}.{}", branch.pos, i)!;
                gen_scope(ctxt, buff, branch.bodies[i].1, "");
                if(!branch.bodies[i].1.rets){
                    fmt::fprintfln(buff, "\tjmp @end.{}", branch.pos)!;
                };
                fmt::fprintfln(buff, "@false.{}.{}", branch.pos, i)!;
            } else {
                gen_scope(ctxt, buff, branch.bodies[i].1, "");
                if(!branch.bodies[i].1.rets){
                    fmt::fprintfln(buff, "\tjmp @end.{}", branch.pos)!;
                };
            };
        };
        if(!(branch.rets && len(branch.bodies) > len(branch.conds))){
            fmt::fprintfln(buff, "@end.{}", branch.pos)!;
        };
    case let ret: *return_meta =>
        move_ptr(ctxt, ctxt.tokens[ret.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        // skip expression for empty returns
        if(ret.val.val is void){
            if(comp_type(ret.val.tpe, quick_t(primitive::VOID))){
                fmt::fprintln(buff, "\tcall $rt.exit(w 0)\nhlt")!;
            } else if(comp_type(ret.val.tpe, quick_t(primitive::VOID, true))){
                fmt::fprintln(buff, "\tcall $rt.exit(w 1)\nhlt")!;
            } else {
                assert(is_subtype(ret.val.tpe, quick_t(primitive::UNIT, true)));
                if(!ret.val.tpe.fail){
                    fmt::fprintln(buff, "\tret")!;
                } else {
                    fmt::fprintln(buff, "\t%opt =l alloc8 16")!;
                    fmt::fprintln(buff, "\tstorel 1, %opt")!;
                    fmt::fprintln(buff, "\tret %opt")!;
                };
            };
            return;
        };
        const temp = fmt::asprintf("%ret.{}", ret.pos)!;
        defer free(temp);
        const memb = gen_exp(ctxt, buff, temp, ret.val.tpe, ret.val);
        if(memb != ""){
            defer free(memb);
            if(ret.tpe.fail && ret.tpe.base is primitive &&
                ret.val.val is hand_t && assert_no_error_val(ret.val.val as hand_t)){
                // allocate partial type
                fmt::fprintfln(buff, "\t{}.wrap =l alloc8 16", temp)!;
                // set as valid
                fmt::fprintfln(buff, "\tstorel 1, {}.wrap", temp)!;
                // offset to point to data
                fmt::fprintfln(buff, "\t{0}.wrap =l add {0}.wrap, 8", temp)!;
                // store data
                fmt::fprintfln(buff, "\tstore{} {}, {}.wrap",
                    qbe_t(quick_t(ret.val.tpe.base as primitive)),
                    memb, temp)!;
                // undo offset
                fmt::fprintfln(buff, "\t{0}.wrap =l sub {0}.wrap, 8", temp)!;
                fmt::fprintfln(buff, "\tret {}.wrap", temp)!;
            } else {
                fmt::fprintfln(buff, "\tret {}", memb)!;
            };
        } else if(ret.tpe.fail && ret.tpe.base is primitive){
            // allocate partial type
            fmt::fprintfln(buff, "\t{}.wrap =l alloc8 16", temp)!;
            // set as valid
            fmt::fprintfln(buff, "\tstorel 1, {}.wrap", temp)!;
            // offset to point to data
            fmt::fprintfln(buff, "\t{0}.wrap =l add {0}.wrap, 8", temp)!;
            // store data
            fmt::fprintfln(buff, "\tstore{0} {1}, {1}.wrap",
                qbe_t(quick_t(ret.val.tpe.base as primitive)), temp)!;
            // undo offset
            fmt::fprintfln(buff, "\t{0}.wrap =l sub {0}.wrap, 8", temp)!;
            fmt::fprintfln(buff, "\tret {}.wrap", temp)!;
        } else {
            fmt::fprintfln(buff, "\tret {}", temp)!;
        };
    case let exp: *expr_meta =>
        move_ptr(ctxt, ctxt.tokens[exp.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;

        const temp = fmt::asprintf("%exp.{}", exp.pos)!;
        defer free(temp);
        const memb = gen_exp(ctxt, buff, temp, exp.tpe, exp);
    };
};

fn assert_no_error_val(val: hand_t) bool = {
    if(val is *member_meta){
        const memb = val as *member_meta;
        return !(memb.val is keyword &&
            (comp_tk(memb.val as keyword, keyword::FAIL) ||
            comp_tk(memb.val as keyword, keyword::NOMEM)));
    };
    return true;
};

fn gen_decl(ctxt: *context, buff: *memio::stream, decl: *decl_meta) void = {
    move_ptr(ctxt, ctxt.tokens[decl.var.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;

    const name = fix_nm(ctxt, buff, decl.var.nm);
    defer free(name);
    match(decl.val){
    case let const_val: *const_meta =>
        const val = emit_constant(ctxt, buff, const_val, decl.var.nm.tpe);
        defer free(val);
        fmt::fprintfln(buff, "\t{} ={} copy {}", name,
            qbe_t(decl.var.nm.tpe, mode::ASSIGN), val)!;
    case let hand: hand_t =>
        const memb = gen_exp(ctxt, buff, name, decl.var.nm.tpe, hand);
        if(memb != ""){
            defer free(memb);
            fmt::fprintfln(buff, "\t{} ={} copy {}", name,
                qbe_t(decl.var.nm.tpe, mode::ASSIGN), memb)!;
        };
    };
};

fn gen_exp(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    exp_t: lichen_t,
    exp: hand_t
) str = {
    match(exp){
    case let hand: *hand_meta =>
        gen_arithmetic(ctxt, buff, dest, exp_t, hand);
    case let memb: *member_meta =>
        const wrap = assign_memb(ctxt, buff, dest, exp_t, memb);
        if(memb.pre is operator){
            switch(memb.pre as operator){
            case operator::PLS =>
                if(wrap != ""){
                    return wrap;
                };
            case operator::MIN =>
                if(wrap != ""){
                    fmt::fprintln(buff, "\t{} ={} neg {}",
                        dest, qbe_t(exp_t, mode::ASSIGN), wrap)!;
                } else {
                    fmt::fprintln(buff, "\t{0} ={1} neg {0}",
                        dest, qbe_t(exp_t, mode::ASSIGN))!;
                };
            case operator::NOT =>
                if(wrap != ""){
                    fmt::fprintln(buff,
                        "\t{} ={} xor {}, 18446744073709551615",
                        dest, qbe_t(exp_t, mode::ASSIGN), wrap)!;
                } else {
                    fmt::fprintln(buff,
                        "\t{0} ={1} xor {0}, 18446744073709551615",
                        dest, qbe_t(exp_t, mode::ASSIGN))!;
                };
            case operator::LENGTH =>
                if(wrap != ""){
                    fmt::fprintfln(buff, "%len =l loadl {}", wrap)!;
                    return strings::dup("%len")!;
                } else {
                    fmt::fprintfln(buff, "\t{0}.len =l loadl {0}", dest)!;
                    return fmt::asprintf("{}.len", dest)!;
                };
            case =>
                fmt::fatal("emit_constant: unreachable");
            };
        } else {
            return wrap;
        };
    case let exp: *expr_meta =>
        if(exp.val is void) return "";
        const pre_cast = extract_hand_type(exp.val as hand_t);
        if(!is_subtype(pre_cast, exp_t)){
            const temp = fmt::asprintf("%tmp.{}", exp.pos)!;
            defer free(temp);
            const memb = gen_exp(ctxt, buff, temp, pre_cast,
                exp.val as hand_t);
            if(memb != ""){
                gen_cast(buff, memb, pre_cast, dest, exp_t);
            } else {
                gen_cast(buff, temp, pre_cast, dest, exp_t);
            };
        } else if(exp.val is hand_t){
            return gen_exp(ctxt, buff, dest, exp_t, exp.val as hand_t);
        };
    case let ternary: *ternary_meta =>
        const cond = fmt::asprintf("%cond.{}", ternary.pos)!;
        defer free(cond);
        gen_exp(ctxt, buff, cond, quick_t(primitive::BOOL), ternary.condition);

        fmt::fprintfln(buff,
            "\tjnz {0}, @true.val.{1}, @false.val.{1}\n@true.val.{1}",
            cond, ternary.pos)!;
        const pos_val = fmt::asprintf("%positive.{}", ternary.pos)!;
        defer free(pos_val);
        gen_exp(ctxt, buff, pos_val, ternary.tpe, ternary.positive);
        gen_cast(buff, pos_val, ternary.tpe, dest, exp_t);
        fmt::fprintfln(buff, "\tjmp @end.{0}\n@false.val.{0}", ternary.pos)!;

        const neg_val = fmt::asprintf("%negative.{}", ternary.pos)!;
        defer free(neg_val);
        gen_exp(ctxt, buff, neg_val, ternary.tpe, ternary.negative);
        gen_cast(buff, neg_val, ternary.tpe, dest, exp_t);
        fmt::fprintfln(buff, "\tjmp @end.{0}\n@end.{0}", ternary.pos)!;
    };
    return "";
};

fn gen_arithmetic(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    exp_t: lichen_t,
    hand: *hand_meta
) void = {
    if(hand.opr > operator::LAND){
        const asg_t = qbe_t(exp_t, mode::ASSIGN);
        const lft_h = fmt::asprintf("%l.{}", hand.pos)!;
        const lft_t = extract_hand_type(hand.lft);
        const short_l = gen_exp(ctxt, buff, lft_h, lft_t, hand.lft);
        if(short_l != ""){
            free(lft_h);
            lft_h = short_l;
        };
        defer free(lft_h);
        
        const rgt_h = fmt::asprintf("%r.{}", hand.pos)!;
        const rgt_t = extract_hand_type(hand.rgt);
        const short_r = gen_exp(ctxt, buff, rgt_h, rgt_t, hand.rgt);
        if(short_r != ""){
            free(rgt_h);
            rgt_h = short_r;
        };
        defer free(rgt_h);
        let needs_free = false;
        const inst =
            switch(hand.opr){
            case operator::EQL =>
                needs_free = true;
                yield fmt::asprintf("ceq{}", qbe_t(lft_t))!;
            case operator::NEQ =>
                needs_free = true;
                yield fmt::asprintf("cne{}", qbe_t(lft_t))!;
            case operator::LEQ =>
                needs_free = true;
                yield if(is_subtype(lft_t, primitive::U64)){
                    yield fmt::asprintf("cule{}", qbe_t(lft_t))!;
                } else if(is_subtype(lft_t, primitive::I64)){
                    yield fmt::asprintf("csle{}", qbe_t(lft_t))!;
                } else {
                    yield fmt::asprintf("cle{}", qbe_t(lft_t))!;
                };
            case operator::GEQ =>
                needs_free = true;
                yield if(is_subtype(lft_t, primitive::U64)){
                    yield fmt::asprintf("cuge{}", qbe_t(lft_t))!;
                } else if(is_subtype(lft_t, primitive::I64)){
                    yield fmt::asprintf("csge{}", qbe_t(lft_t))!;
                } else {
                    yield fmt::asprintf("cge{}", qbe_t(lft_t))!;
                };
            case operator::LST =>
                needs_free = true;
                yield if(is_subtype(lft_t, primitive::U64)){
                    yield fmt::asprintf("cult{}", qbe_t(lft_t))!;
                } else if(is_subtype(lft_t, primitive::I64)){
                    yield fmt::asprintf("cslt{}", qbe_t(lft_t))!;
                } else {
                    yield fmt::asprintf("clt{}", qbe_t(lft_t))!;
                };
            case operator::GTT =>
                needs_free = true;
                yield if(is_subtype(lft_t, primitive::U64)){
                    yield fmt::asprintf("cugt{}", qbe_t(lft_t))!;
                } else if(is_subtype(lft_t, primitive::I64)){
                    yield fmt::asprintf("csgt{}", qbe_t(lft_t))!;
                } else {
                    yield fmt::asprintf("cgt{}", qbe_t(lft_t))!;
                };
            case operator::BAND => yield "and";
            case operator::BOR => yield "or";
            case operator::PLS => yield "add";
            case operator::MIN => yield "sub";
            case operator::MUL => yield "mul";
            case operator::DIV =>
                // address for signed types or ratios
                yield if(is_subtype(exp_t, primitive::U64)){
                    yield "udiv";
                } else {
                    yield "div";
                };
            case operator::MOD =>
                // address for signed types or ratios
                yield if(is_subtype(exp_t, primitive::U64)){
                    yield "urem";
                } else {
                    yield "rem";
                };
            case operator::SHL => yield "shl";
            case operator::SHR =>
                // address for signed types or ratios
                yield if(is_subtype(exp_t, primitive::U64)){
                    yield "shr";
                } else {
                    yield "sar";
                };
            case =>
                fmt::fatalf("gen_arithmetic: unreachable operator {}",
                    oper_value[hand.opr]);
            };
        defer if(needs_free) free(inst);
        // compatible types
        if(comp_type(lft_t, rgt_t) && is_subtype(lft_t, exp_t) &&
            !size_mismatch(lft_t, exp_t)){
            gen_cast(buff, lft_h, lft_t, dest, exp_t);
            fmt::fprintf(buff, "\t{0} ={1} {2} {0}, {3}\n",
                dest, asg_t, inst, rgt_h)!;
        // boolean comparison
        } else if(comp_type(exp_t, primitive::BOOL)){
            fmt::fprintf(buff, "\t{} ={} {} {}, {}\n",
                dest, asg_t, inst, lft_h, rgt_h)!;
        // at least one member require casting
        } else {
            gen_cast(buff, lft_h, lft_t, dest, exp_t);
            const rgt_wrap = fmt::asprintf("%r.{}.wrap", hand.pos)!;
            defer free(rgt_wrap);
            if(short_r == ""){
                gen_cast(buff, rgt_h, rgt_t, rgt_wrap, exp_t);
                fmt::fprintf(buff, "\t{0} ={1} {2} {0}, {3}\n",
                    dest, asg_t, inst, rgt_wrap)!;
            } else {
                fmt::fprintf(buff, "\t{0} ={1} {2} {0}, {3}\n",
                    dest, asg_t, inst, rgt_h)!;
            };
        };
    } else if(hand.opr == operator::LAND){
        const asg_t = qbe_t(exp_t, mode::ASSIGN);
        const lft_h = fmt::asprintf("%l.{}", hand.pos)!;
        const lft_t = extract_hand_type(hand.lft);
        const short_l = gen_exp(ctxt, buff, lft_h, lft_t, hand.lft);
        if(short_l != ""){
            free(lft_h);
            lft_h = short_l;
        };
        defer free(lft_h);
        fmt::fprintfln(buff, "\tjnz {0}, @mid.{1}, @false.{1}\n@mid.{1}", lft_h, hand.pos)!;

        const rgt_h = fmt::asprintf("%r.{}", hand.pos)!;
        const rgt_t = extract_hand_type(hand.rgt);
        const short_r = gen_exp(ctxt, buff, rgt_h, rgt_t, hand.rgt);
        if(short_r != ""){
            free(rgt_h);
            rgt_h = short_r;
        };
        defer free(rgt_h);
        fmt::fprintfln(buff, "\tjnz {0}, @true.{1}, @false.{1}", rgt_h, hand.pos)!;
        fmt::fprintfln(buff,
            "@true.{1}\n\t{0} =l copy 1\n\tjmp @end.{1}\n@false.{1}\n\t{0} =l copy 0\n\tjmp @end.{1}\n@end.{1}",
            dest, hand.pos)!;
    } else {
        const asg_t = qbe_t(exp_t, mode::ASSIGN);
        const lft_h = fmt::asprintf("%l.{}", hand.pos)!;
        const lft_t = extract_hand_type(hand.lft);
        const short_l = gen_exp(ctxt, buff, lft_h, lft_t, hand.lft);
        if(short_l != ""){
            free(lft_h);
            lft_h = short_l;
        };
        defer free(lft_h);
        fmt::fprintfln(buff, "\tjnz {0}, @true.{1}, @mid.{1}\n@mid.{1}", lft_h, hand.pos)!;
        const rgt_h = fmt::asprintf("%r.{}", hand.pos)!;
        const rgt_t = extract_hand_type(hand.rgt);
        const short_r = gen_exp(ctxt, buff, rgt_h, rgt_t, hand.rgt);
        if(short_r != ""){
            free(rgt_h);
            rgt_h = short_r;
        };
        defer free(rgt_h);
        fmt::fprintfln(buff, "\tjnz {0}, @true.{1}, @false.{1}", rgt_h, hand.pos)!;
        fmt::fprintfln(buff,
            "@true.{1}\n\t{0} =l copy 1\n\tjmp @end.{1}\n@false.{1}\n\t{0} =l copy 0\n\tjmp @end.{1}\n@end.{1}",
            dest, hand.pos)!;
    };
};

fn assign_memb(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    exp_t: lichen_t,
    memb: *member_meta,
) str = {
    const temp = fmt::asprintf("%tmp.{}", qbe_t(memb.tpe))!;
    defer free(temp);
    const (val, tpe, skip) = 
        match(memb.val){
        case let const_val: *const_meta =>
            if(comp_type(memb.tpe, primitive::CSTR) && const_val.val is str){
                fmt::fprintfln(buff, "\t{} =l add $str.{}, 8", dest,
                    push_lit(ctxt, const_val.val as str))!;
                fmt::fprintfln(buff, "\t{0} =l loadl {0}", dest)!;
                return "";
            } else {
                return emit_constant(ctxt, buff, const_val, memb.tpe);
            };
        case let var: *var_meta =>
            yield (fix_nm(ctxt, buff, var.nm), var.nm.tpe, false);
        case let call: *funcall_meta =>
            const nm =
                if(call.fun.fun.tpe.fail != exp_t.fail){
                    yield temp;
                } else {
                    yield dest;
                };
            yield(gen_funcall(ctxt, buff, call, nm), call.fun.fun.tpe,
                is_subtype(call.fun.fun.tpe, memb.tpe));
        case let kwd: keyword =>
            yield switch(kwd){
            case keyword::TRUE =>
                return strings::dup("1")!;
            case keyword::FALSE =>
                return strings::dup("0")!;
            case keyword::NOMEM =>
                if(exp_t.base is primitive){
                    fmt::fprintln(buff, "\t%opt =l alloc8 16")!;
                    fmt::fprintln(buff, "\tstorel 0, %opt")!;
                    return strings::dup("%opt")!;
                } else {
                    return strings::dup("0")!;
                };
            case keyword::FAIL =>
                if(exp_t.base is primitive){
                    fmt::fprintln(buff, "\t%opt =l alloc8 16")!;
                    fmt::fprintln(buff, "\tstorel -1, %opt")!;
                    return strings::dup("%opt")!;
                } else {
                    return strings::dup("-1")!;
                };
            case =>
                fmt::fatal("assign_memb: unreachable");
            };
        };
    if(memb.prop is propagation){
        const prop = memb.prop as propagation;
        if(tpe.base is primitive){
            fmt::fprintfln(buff, "\t%fail.code =l loadl {}", val)!;
            fmt::fprintln(buff, "\t%assert.fail =l csltl %fail.code, 1")!;
        } else {
            if(tpe.base is primitive){
                fmt::fprintfln(buff, "\t%assert.fail =l csltl {}, 1", val)!;
            };
        };
        // no assertion expression
        if(prop.1 is void){
            if(prop.0 == operator::BUBBLE){
                fmt::fprintfln(buff, "\tjnz %assert.fail, @bubble.{0}, @ok.{0}",
                    memb.pos)!;
                fmt::fprintfln(buff, "@bubble.{0}\n\tret {1}\n@ok.{0}",
                    memb.pos, val)!;
            } else {
                fmt::fprintfln(buff, "\tjnz %assert.fail, @fail, @ok.{0}\n@ok.{0}",
                    memb.pos)!;
            };
        } else {
            if(prop.0 == operator::BUBBLE){
                const exp = prop.1 as *expr_meta;
                fmt::fprintfln(buff,
                    "\tjnz %assert.fail, @bubble.{0}, @ok.{0}\n@bubble.{0}",
                    memb.pos)!;
                const wrap = fmt::asprint("%default.{}", memb.pos)!;
                defer free(wrap);
                const val = gen_exp(ctxt, buff, wrap, memb.tpe, exp);
                fmt::fprintfln(buff,
                    "\t{1} ={2} copy {3}\n\tjmp @skip.{0}\n@ok.{0}",
                    memb.pos, dest, qbe_t(exp_t, mode::ASSIGN), val)!;
            } else {
                const stt = prop.1 as path_meta;
                fmt::fprintfln(buff, "\tjnz %assert.fail, @fail.{0}, @ok.{0}",
                    memb.pos)!;
                const zero = zeroed_value(ctxt, buff, exp_t);
                defer free(zero);
                fmt::fprintfln(buff, "@fail.{}\n\t{} ={} copy {}",
                    memb.pos, dest, qbe_t(exp_t, mode::ASSIGN), zero)!;
                gen_stt(ctxt, buff, stt);
                fmt::fprintfln(buff, "\tjmp @skip.{0}\n@ok.{0}", memb.pos)!;
            };
        };
    };
    if(!skip){
        defer free(val);
        if(!is_subtype(memb.tpe, exp_t)){
            gen_cast(buff, val, tpe, temp, memb.tpe);
            gen_cast(buff, temp, memb.tpe, dest, exp_t);
        } else {
            gen_cast(buff, val, tpe, dest, exp_t);
        };
    };
    if(memb.prop is propagation){
        const prop = memb.prop as propagation;
        if(prop.1 is path_meta){
            fmt::fprintfln(buff, "@skip.{}", memb.pos)!;
        };
    };
    return "";
};

fn gen_funcall(
    ctxt: *context,
    buff: *memio::stream,
    call: *funcall_meta,
    dest: str,
) str = {
    const name =
        if(call.fun.fun.ffi is str){
            yield fmt::asprintf("${}",
                call.fun.fun.ffi as str)!;
        } else if(ctxt.file != call.fun.origin || !ctxt.main){
            const mod = strings::rcut(
                strings::rcut(call.fun.origin, "/").1, ".").0;
            yield fmt::asprintf("${}.{}", mod,
                call.fun.fun.name)!;
        } else {
            yield fmt::asprintf("${}", call.fun.fun.name)!;
        };
    defer free(name);
    const defs: []*var_meta = [];
    defer for(const d .. defs) free_nodes(d);
    for(let exp .. call.args){
        const wrap = fmt::asprintf("%exp.{}", exp.pos)!;
        const memb = gen_exp(ctxt, buff, wrap, exp.tpe, exp);
        const name =
            if(memb != ""){
                free(wrap);
                yield memb;
            } else {
                yield wrap;
            };
        const temp = var_meta {
            nm = namespace {
                name = name,
                tpe = exp.tpe,
                ffi = void,
                ...
            },
            pos = exp.pos,
        };
        append(defs, alloc(temp)!)!;
    };
    if(dest != "" && !comp_type(call.fun.fun.tpe, quick_t(primitive::UNIT))){
        fmt::fprintf(buff, "\t{} ={} call {}", dest,
            qbe_t(call.fun.fun.tpe, mode::RETURN), name)!;
    } else {
        fmt::fprintf(buff, "\tcall {}", name)!;
    };
    gen_list(buff, defs);
    fmt::fprint(buff, "\n")!;
    return strings::dup(dest)!;
};

// generates all needed type casting for an assignment
fn gen_cast(
    buff: *memio::stream,
    src: str,
    src_t: lichen_t,
    dest: str,
    dest_t: lichen_t,
) void = {
    const dest_qbe_t = qbe_t(dest_t, mode::ASSIGN);
    if(untyped(src_t)){
        const d_tpe_p =
            if(!untyped(dest_t)){
                yield dest_t;
            } else if(is_subtype(dest_t, primitive::U64)){
                yield quick_t(primitive::U64);
            } else if(is_subtype(dest_t, primitive::I64)){
                yield quick_t(primitive::I64);
            } else if(is_subtype(dest_t, primitive::F64)){
                yield quick_t(primitive::F64);
            } else {
                todo("gen_cast: other default types for untyped");
            };
        if(is_subtype(src_t, primitive::NUMBER) && is_ratio(dest_t)){
            fmt::fprintfln(buff, "\t{} ={} {} {}", dest,
                qbe_t(dest_t, mode::ASSIGN),
                itof(quick_t(primitive::I64), d_tpe_p), src)!;
            return;
        } else if(is_ratio(src_t) &&
            is_subtype(dest_t, primitive::NUMBER)){
            fmt::fprintfln(buff, "\t{} ={} {} {}", dest,
                qbe_t(dest_t, mode::ASSIGN),
                ftoi(quick_t(primitive::F64), d_tpe_p), src)!;
            return;
        } else {
            fmt::fprintfln(buff, "\t{} ={} copy {}", dest, dest_qbe_t, src)!;
            return;
        };
    };
    if(src_t.base is primitive && !src_t.fail && dest_t.base is primitive &&
        !dest_t.fail){
        if(comp_type(src_t, primitive::STR) || comp_type(dest_t, primitive::STR)){
            if(!comp_type(src_t, dest_t) && comp_type(dest_t, primitive::CSTR)){
                fmt::fprintfln(buff, "\t{} =l add {}, 8", dest, src)!;
                fmt::fprintfln(buff, "\t{0} =l loadl {0}", dest)!;
                return;
            } else {
                fmt::fprintfln(buff, "\t{} =l copy {}", dest, src)!;
                return;
            };
        } else if(!comp_type(src_t, dest_t) && size_mismatch(src_t, dest_t)){
            // cast between integers
            if((is_subtype(src_t, primitive::NUMBER) ||
                is_subtype(src_t, primitive::BOOL)) &&
                (is_subtype(dest_t, primitive::NUMBER) ||
                is_subtype(dest_t, primitive::BOOL))){
                fmt::fprintfln(buff, "\t{} ={} ext{} {}",
                    dest, dest_qbe_t, qbe_t(src_t, mode::LOAD), src)!;
            // cast of integer to float
            } else if((is_subtype(src_t, primitive::NUMBER) ||
                is_subtype(src_t, primitive::BOOL)) && is_ratio(dest_t)){
                fmt::fprintfln(buff, "\t{} ={} {} {}",
                    dest, dest_qbe_t, itof(src_t, dest_t), src)!;
            // cast of float to integer
            } else if(is_ratio(src_t) &&
                (is_subtype(dest_t, primitive::NUMBER) ||
                is_subtype(dest_t, primitive::BOOL))){
                fmt::fprintfln(buff, "\t{} ={} {} {}",
                    dest, dest_qbe_t, ftoi(src_t, dest_t), src)!;
            // cast between floats
            } else {
                if(type_size(src_t) < type_size(dest_t)){
                    fmt::fprintfln(buff, "\t{} ={} exts {}",
                        dest, dest_qbe_t, src)!;
                } else {
                    fmt::fprintfln(buff, "\t{} ={} truncd {}",
                        dest, dest_qbe_t, src)!;
                };
            };
        } else if(!is_subtype(src_t, dest_t) &&
            (is_ratio(src_t) || is_ratio(dest_t))){
            if(is_subtype(src_t, primitive::NUMBER) &&
                is_subtype(dest_t, primitive::NUMBER)){
                if(is_ratio(src_t)){
                    fmt::fprintfln(buff, "\t{} ={} {} {}",
                        dest, dest_qbe_t, ftoi(src_t, dest_t), src)!;
                } else {
                    fmt::fprintfln(buff, "\t{} ={} {} {}",
                        dest, dest_qbe_t, itof(src_t, dest_t), src)!;
                };
            } else {
                fmt::println(strtype(src_t), strtype(dest_t))!;
                fmt::fprintfln(buff, "\t{} ={} cast {}", dest, dest_qbe_t,
                    src)!;
            };
        } else {
            fmt::fprintfln(buff, "\t{} ={} copy {}",
                dest, dest_qbe_t, src)!;
        };
    } else if(src_t.base is primitive && dest_t.base is primitive){
        // unwrap
        if(src_t.fail && !dest_t.fail){
            // offset loading point to actual cata
            fmt::fprintfln(buff, "\t{0} =l add {0}, 8", src)!;
            // deal with data type casting
            if(!comp_type(quick_t(src_t.base as primitive),
                quick_t(dest_t.base as primitive)) &&
                size_mismatch(src_t, dest_t)){
                const temp = fmt::asprintf("{}.wrap", dest)!;
                defer free(temp);
                fmt::fprintfln(buff, "\t{} ={} load{} {}", temp,
                    qbe_t(dest_t, mode::ASSIGN), qbe_t(dest_t, mode::LOAD), src)!;
                // cast loaded value to desired type
                gen_cast(buff, temp, quick_t(src_t.base as primitive), dest,
                    dest_t);
            } else {
                fmt::fprintfln(buff, "\t{} ={} load{} {}", dest,
                    qbe_t(dest_t, mode::ASSIGN), qbe_t(dest_t, mode::LOAD), src)!;
            };
            // undo offset
            fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", src)!;
        // concrete to partial
        } else if(!src_t.fail && dest_t.fail){
            fmt::fprintfln(buff, "\t{0} =l add {0}, 8", src)!;
            fmt::fprintfln(buff, "\tstore{} {}, {}", qbe_t(src_t),
                dest, src)!;
            fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", src)!;
        // both error types
        } else {
            fmt::fprintfln(buff, "\t{} =l copy {}", dest, src)!;
        };
    } else {
        todo("composite types");
    };
};

fn fix_nm(ctxt: *context, buff: *memio::stream, nm: namespace) str = {
    if(nm.ffi is str){
        fmt::fprintfln(buff, "\t%{0} ={1} load{2} ${0}", nm.ffi,
            qbe_t(nm.tpe, mode::ASSIGN), qbe_t(nm.tpe, mode::LOAD))!;
        return fmt::asprintf("%{}", nm.ffi as str)!;
    };
    const name = strings::replace(nm.name, "'", ".q")!;
    defer free(name);
    if(!ctxt.main && nm.glob){
        const mod = strings::rcut(
            strings::rcut(ctxt.file, "/").0, ".").0;
        const wrap = fmt::asprintf("%{}.{}", mod, name)!;
        fmt::fprintfln(buff, "\t{} ={} load{} ${}.{}", wrap,
            qbe_t(nm.tpe, mode::ASSIGN), qbe_t(nm.tpe, mode::LOAD),
            mod, name)!;
        return wrap;
    } else if(nm.glob){
        fmt::fprintfln(buff, "\t%{0} ={1} load{2} ${0}", name,
            qbe_t(nm.tpe, mode::ASSIGN), qbe_t(nm.tpe, mode::LOAD))!;
        return fmt::asprintf("%{}", name)!;
    } else {
        return fmt::asprintf("%{}", name)!;
    };
};

fn emit_constant(
    ctxt: *context, 
    buff: *memio::stream, 
    c: *const_meta,
    hint: lichen_t,
) str = {
    match(c.val){
    case let num: size =>
        if(c.pre is operator){
            const op = c.pre as operator;
            switch(op){
            case operator::PLS =>
                return fmt::asprint(num)!;
            case operator::MIN =>
                return fmt::asprint(-(num: i64))!;
            case operator::NOT =>
                return fmt::asprint(~num)!;
            case =>
                fmt::fatal("emit_constant: unreachable");
            };
        } else {
            return fmt::asprint(num)!;
        };
    case let flt: f64 =>
        const prefix =
            if(comp_type(hint, primitive::F32)){
                yield "s_";
            } else {
                yield "d_";
            };
        if(c.pre is operator){
            const op = c.pre as operator;
            switch(op){
            case operator::PLS =>
                return fmt::asprintf("{}{}", prefix, flt)!;
            case operator::MIN =>
                return fmt::asprintf("-{}{}", prefix, flt)!;
            case =>
                fmt::fatal("emit_constant: unreachable");
            };
        } else {
            return fmt::asprintf("{}{}", prefix, flt)!;
        };
    case let txt: str =>
        if(c.pre is operator){
            assert(c.pre as operator == operator::LENGTH);
            const idx = push_lit(ctxt, txt);
            fmt::fprintfln(buff, "\t%str.{0}.len =l loadl $str.{0}", idx)!;
            return fmt::asprintf("%str.{}.len", idx)!;
        } else {
            return fmt::asprintf("$str.{}", push_lit(ctxt, txt))!;
        };
    case let kwd: keyword =>
        switch(kwd){
        case keyword::TRUE =>
            return strings::dup("1")!;
        case keyword::FALSE, keyword::NOMEM =>
            return strings::dup("0")!;
        case keyword::FAIL =>
            return strings::dup("-1")!;
        case =>
            fmt::fatal("emit_constant: unreachable");
        };
    };
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

fn zeroed_value(ctxt: *context, buff: *memio::stream, tpe: lichen_t) str = {
    if(tpe.base is primitive){
        if(is_aggregated(tpe)){
            return strings::dup("$rt.zero")!;
        } else {
            return strings::dup("0")!;
        };
    } else if(tpe.base is *array){
        return strings::dup("$rt.zero")!;
    } else if(tpe.base is *enum_t){
        const e = tpe.base as *enum_t;
        return fix_nm(ctxt, buff, e.variant[0]);
    } else {
        todo("default values for records");
    };
};
