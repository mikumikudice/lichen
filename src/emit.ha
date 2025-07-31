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
fn qbe_t(ctxt: *context, tpe: lichen_t, md: mode = mode::REAL) str = {
    if(tpe.base is primitive){
        assert(tpe.base as primitive != primitive::ANY);
        if(tpe.fail){
            if(md == mode::RETURN) return ":opt.t";
            return "l";
        };
        switch(tpe.base as primitive){
        case primitive::U8 =>
            if(md == mode::ASSIGN || md == mode::RETURN) return "w";
            if(md == mode::LOAD) return "ub";
            return "b";
        case primitive::I8 =>
            if(md == mode::ASSIGN || md == mode::RETURN) return "w";
            if(md == mode::LOAD) return "sb";
            return "b";
        case primitive::U16 =>
            if(md == mode::ASSIGN || md == mode::RETURN) return "w";
            if(md == mode::LOAD) return "uh";
            return "h";
        case primitive::I16 =>
            if(md == mode::ASSIGN || md == mode::RETURN) return "w";
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
        case primitive::U64, primitive::I64, primitive::CSTR,
            primitive::BOOL, primitive::VOID, primitive::UNIT,
            primitive::NUMBER =>
            return "l";
        case primitive::STR =>
            if(md == mode::RETURN) return ":str.t";
            return "l";
        case primitive::MEM =>
            if(md == mode::RETURN) return ":mem.t";
            return "l";
        case primitive::RATIO =>
            return "d";
        case =>
            color_error("%Runreachable:%r unknown type %y{}",
                prim_value[tpe.base as primitive]);
            os::exit(1);
        };
    } else if(tpe.base is *record){
        if(md == mode::RETURN){
            const rec = tpe.base as *record;
            return rec.export_name;
        };
        return "l";
    } else if(tpe.base is *array){
        if(md == mode::RETURN){
            for(let d .. ctxt.global.defs){
                if(d is *type_meta){
                    const d_tpe = d as *type_meta;
                    if(comp_type(d_tpe.self, tpe))
                        return d_tpe.name.name;
                };
            };
            assert(false);
        };
        return "l";
    } else {
        return "l";
    };
};

// gets the given type's in memory type
fn type_size(tpe: lichen_t, ignore_fail: bool = false) size = {
    const arg = strtype(tpe);
    defer free(arg);
    assert(!untyped(tpe), arg);

    if(tpe.base is primitive){
        if(tpe.fail && !ignore_fail){
            if((tpe.base as primitive) == primitive::MEM) return 32;
            return 16;
        };
        switch(tpe.base as primitive){
        case primitive::UNIT, primitive::VOID => return 8;
        case primitive::U8, primitive::I8 => return 1;
        case primitive::U16, primitive::I16 => return 2;
        case primitive::U32, primitive::I32,
            primitive::F32 => return 4;
        case primitive::U64, primitive::I64,
            primitive::F64, primitive::CSTR, 
            primitive::BOOL => return 8;
        case primitive::STR => return 16;
        case primitive::MEM => return 24;
        case =>
            assert(false, "unreachable");
            return 0;
        };
    } else if(tpe.base is *record){
        const rec = tpe.base as *record;
        let length = 0z;
        for(let field .. rec.fields){
            const real = type_size(field.1.var.nm.tpe);
            const offst =
                if(real % 4 > 0){
                    yield 4 - real % 4;
                } else {
                    yield 0z;
                };
            length += real + offst;
        };
        if(tpe.fail) length += 8;
        return length;
    } else if(tpe.base is *array){
        const arr = tpe.base as *array;
        const base_size = type_size(arr.base);
        const item_offset =
            if(base_size % 4 > 0){
                yield 4 - base_size % 4;
            } else {
                yield 0z;
            };
        const item_size = base_size + item_offset;
        if(arr.length is void){
            if(tpe.fail) return 24;
            return 16;
        } else if(tpe.fail){
            return arr.length as size * item_size + 16;
        } else {
            return arr.length as size * item_size + 8;
        };
    } else {
        assert(false, "unreachable");
        return 0;
    };
};

fn field_offset(rec: *record, field_name: str) size = {
    let acc = 0z;
    let found = false;
    for(let field .. rec.fields){
        if(field.1.var.nm.name == field_name){
            found = true;
            break;
        };
        const real = type_size(field.1.var.nm.tpe);
        const off =
            if(real % 4 != 0){
                yield 4 - real % 4;
            } else {
                yield 0z;
            };
        acc += real + off;
    };
    assert(found);
    return acc;
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
    keep_temps: bool,
    silent: bool,
) void = {
    // unhide temp folder if it should be kept
    if(keep_temps){
        temp_folder = strings::sub(temp_folder, 1);
    };
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
    const qbe_out = fmt::asprintf("{}{}.ssa", temp_folder, obj_name)!;
    defer free(qbe_out);
    const asm_src = fmt::asprintf("{}{}.s", temp_folder, obj_name)!;
    defer free(asm_src);
    const obj_out = fmt::asprintf("{}{}.o", temp_folder, obj_name)!;
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
    run_cmd(silent, "mkdir", "-p", temp_folder);
    // emit final IR file
    const object =
        match(os::create(qbe_out, fs::mode::USER_RWX)){
        case let f: io::file => yield f;
        case let e: fs::error =>
            color_error("%Robject emition error:%b {}%r: {}",
                qbe_out, fs::strerror(e));
            os::exit(1);
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
    fmt::fprintln(&ir, "type :opt.t = { l, l }")!;
    fmt::fprintln(&ir, "type :mem.t = { l, l, l }")!;
    fmt::fprintln(&ir, "type :mem.t.opt = { l, l, l, l }")!;
    fmt::fprintln(&ir, "type :str.t = { l, l }")!;
    fmt::fprintln(&ir, "type :str.t.opt = { l, l, l }")!;
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
                                qbe_t(ctxt, meta.var.nm.tpe), ~num)!;
                        case operator::PLS =>
                            yield fmt::asprintf("{} {}",
                                qbe_t(ctxt, meta.var.nm.tpe), num)!;
                        case operator::MIN =>
                            yield fmt::asprintf("{} {}",
                                qbe_t(ctxt, meta.var.nm.tpe), -(num: i64))!;
                        case =>
                            assert(false);
                            yield "";
                        };
                    } else {
                        yield fmt::asprintf("{} {}",
                            qbe_t(ctxt, meta.var.nm.tpe), num)!;
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
            const base_name = strings::replace(meta.fun.name, "'", ".q")!;
            defer free(base_name);
            const name =
                if(meta.fun.ffi is str){
                    yield fmt::asprintf("${}",
                        meta.fun.ffi as str)!;
                } else if(ctxt.file != meta.origin || !ctxt.main){
                    const mod = strings::rcut(
                        strings::rcut(meta.origin, "/").1, ".").0;
                    yield fmt::asprintf("${}.{}", mod,
                        base_name)!;
                } else {
                    yield fmt::asprintf("${}", base_name)!;
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
            } else if(meta.fun.tpe.fail && meta.fun.tpe.base is *record){
                fmt::fprintf(buff, "{}.opt {}",
                    qbe_t(ctxt, meta.fun.tpe, mode::RETURN), name)!;
            } else {
                fmt::fprintf(buff, "{} {}",
                    qbe_t(ctxt, meta.fun.tpe, mode::RETURN), name)!;
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
            gen_list(ctxt, buff, params);
            // gen function body scope
            gen_scope(ctxt, buff, meta.body as *scope_meta, "@start", true);
        case let tpe: *type_meta =>
            match(tpe.self.base){
            case let rec: *record =>
                fmt::fprintf(buff, "\ntype {} = align 8 {{ ", rec.export_name)!;
                for(let field .. rec.fields){
                    const tpe = field.1.var.nm.tpe;
                    fmt::fprintf(buff, "{}, ", qbe_t(ctxt, tpe))!;
                };
                fmt::fprintln(buff, "}")!;
                fmt::fprintf(buff, "\ntype {}.opt = align 8 {{ l, ", rec.export_name)!;
                for(let field .. rec.fields){
                    const tpe = field.1.var.nm.tpe;
                    fmt::fprintf(buff, "{}, ", qbe_t(ctxt, tpe))!;
                };
                fmt::fprintln(buff, "}")!;
            case let arr: *array =>
                if(tpe.self.fail){
                    fmt::fprintf(buff, "\ntype {} = align 8 {{ l, l, ", tpe.name.name)!;
                } else {
                    fmt::fprintf(buff, "\ntype {} = align 8 {{ l, ", tpe.name.name)!;
                };
                if(arr.length is void){
                    fmt::fprintf(buff, "l, ")!;
                } else {
                    const tpe_name = qbe_t(ctxt, arr.base);
                    for(let t = 0z; t < arr.length as size; t += 1){
                        fmt::fprintf(buff, "{}, ", tpe_name)!;
                    };
                };
                fmt::fprintln(buff, "}")!;
            case => todo("enums emitting");
            };
        case let meta: *module_meta => void;
        };
    };
};

fn gen_list(ctxt: *context, buff: *memio::stream, names: []*var_meta) void = {
    fmt::fprint(buff, "(")!;
    for(let n .. names){
        fmt::fprintf(buff, "{} {}, ",
            qbe_t(ctxt, n.nm.tpe, mode::ASSIGN), n.nm.name)!;
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
    } else if(comp_type(scope.tpe, quick_t(primitive::VOID, true)) && has_fail){
        fmt::fprintfln(buff, "\tcall $rt.exit(w 1)\n\thlt")!;
    } else if(!scope.rets && has_fail){
        if(comp_type(scope.tpe, quick_t(primitive::UNIT))){
            fmt::fprintln(buff, "\tret")!;
        } else if(comp_type(scope.tpe, quick_t(primitive::UNIT, true))){
            fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                scope.pos, type_size(scope.tpe))!;
            fmt::fprintfln(buff, "\tstorel 1, %opt.{}", scope.pos)!;
            fmt::fprintfln(buff, "\tret %opt.{}", scope.pos)!;
        };
    };
    if(has_fail){
        fmt::fprintln(buff, "@fail\n\tcall $rt.exit(w 1)\n\thlt\n}")!;
    };
};

fn gen_stt(ctxt: *context, buff: *memio::stream, stt: path_meta) void = {
    match(stt){
    case let test: *test_meta =>
        move_ptr(ctxt, ctxt.tokens[test.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        const wrap = fmt::asprintf("%test.cond")!;
        defer free(wrap);
        const val = gen_exp(ctxt, buff, wrap,
            quick_t(primitive::BOOL), test.cond);
        if(val != ""){
            defer free(val);
            fmt::fprintfln(buff,
                "\tjnz {0}, @test.ok.{1}, @fail.{1}", val, test.pos)!;
        } else {
            fmt::fprintfln(buff,
                "\tjnz {0}, @test.ok.{1}, @fail.{1}", wrap, test.pos)!;
        };
        fmt::fprintfln(buff, "@fail.{}", test.pos)!;
        if(test.props){
            fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                test.pos, type_size(test.host_tpe as lichen_t))!;
            fmt::fprintfln(buff, "\tstorel 0, %opt.{}", test.pos)!;
            fmt::fprintfln(buff, "\tret %opt.{}", test.pos)!;
            fmt::fprintfln(buff, "@test.ok.{}", test.pos)!;
        } else {
            fmt::fprintfln(buff, "\tcall $rt.write(w 2, l $str.{})", test.str_id)!;
            fmt::fprintln(buff, "\tcall $rt.exit(w 1)\n\thlt")!;
            fmt::fprintfln(buff, "@test.ok.{}", test.pos)!;
        };
    case let loop: *for_meta =>
        move_ptr(ctxt, ctxt.tokens[loop.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        // local variable
        if(loop.local is *decl_meta){
            gen_decl(ctxt, buff, loop.local as *decl_meta);
        };
        // fetch iterator
        const iter =
            match(loop.iter){
            case let iter: *decl_meta =>
                yield fix_nm(ctxt, buff, iter.var.nm);
            case let arr: *array_lit_meta =>
                const anon = fmt::asprintf("%anon.arr.{}", loop.pos)!;
                gen_arr_lit(ctxt, buff, anon, arr.tpe, arr);
                yield anon;
            };
        // loop condition
        defer free(iter);
        fmt::fprintfln(buff, "\t%loop.max.{} =l loadl {}", loop.pos, iter)!;
        const idx =
            if(loop.indx == null){
                yield fmt::asprintf("%loop.idx.{}", loop.pos)!;
            } else {
                yield fix_nm(ctxt, buff, (loop.indx as *decl_meta).var.nm);
            };
        defer free(idx);
        fmt::fprintfln(buff, "\t{} =l copy 0", idx)!;
        // main loop condition checking
        fmt::fprintfln(buff,
            "@loop.rep.{0}\n"
            "\t%loop.rep.{0} =l cultl {1}, %loop.max.{0}",
            loop.pos, idx)!;
        fmt::fprintfln(buff,
            "\tjnz %loop.rep.{0}, @loop.pre.{0}, @loop.end.{0}", loop.pos)!;
        // process array offset
        fmt::fprintfln(buff,
            "@loop.pre.{0}\n"
            "\t%loop.offset.{0} =l mul {2}, {1}\n"
            "\t%loop.offset.{0} =l add %loop.offset.{0}, 8\n",
            loop.pos, type_size(loop.item.var.nm.tpe), idx)!;
        // offset array
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, %loop.offset.{1}",
            iter, loop.pos)!;
        // iteration item assignment
        const item = fix_nm(ctxt, buff, loop.item.var.nm);
        defer free(item);
        fmt::fprintfln(buff, "\t{} ={} load{} {}.ptr", item,
            qbe_t(ctxt, loop.item.var.nm.tpe, mode::ASSIGN),
            qbe_t(ctxt, loop.item.var.nm.tpe, mode::LOAD), iter)!;
        // body scope
        const body = fmt::asprintf("@loop.body.{}", loop.pos)!;
        defer free(body);
        gen_scope(ctxt, buff, loop.body, body);
        fmt::fprintfln(buff, "\t{0} =l add {0}, 1", idx)!;
        fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
            qbe_t(ctxt, loop.item.var.nm.tpe, mode::ASSIGN), item, iter)!;
        fmt::fprintfln(buff, "\tjmp @loop.rep.{0}\n@loop.end.{0}", loop.pos)!;
    case let decl: *decl_meta =>
        gen_decl(ctxt, buff, decl);
    case let asg: *assign_meta =>
        move_ptr(ctxt, ctxt.tokens[asg.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        const wrap = fmt::asprintf("%asg.val")!;
        defer free(wrap);
        const val = gen_exp(ctxt, buff, wrap, asg.var.nm.tpe, asg.val);
        const asg_val =
            if(val != ""){
                yield val;
            } else {
                yield wrap;
            };
        defer if(val != "") free(val);

        if(asg.host is void){
            const name = fix_nm(ctxt, buff, asg.var.nm);
            defer free(name);
            if(asg.var.nm.mut &&
                is_aggregated(asg.var.nm.tpe) &&
                size_known(asg.var.nm.tpe)){
                const mem_size = type_size(asg.var.nm.tpe);
                fmt::fprintfln(buff, "\t%dup.{} =l alloc8 {}", mem_size, asg.pos)!;
                fmt::fprintfln(buff, "\tblit {}, %dup.{}, {}", asg_val, asg.pos, mem_size)!;
                fmt::fprintfln(buff, "\t{} =l copy %dup.{}", name, asg.pos)!;
            } else {
                fmt::fprintfln(buff, "\t{} ={} copy {}", name,
                    qbe_t(ctxt, asg.var.nm.tpe, mode::ASSIGN), asg_val)!;
            };
        } else {
            const host = asg.host as *decl_meta;
            const host_name = fix_nm(ctxt, buff, host.var.nm);

            const offst = field_offset(host.var.nm.tpe.base as *record,
                asg.var.nm.name);
            fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, {1}", host_name, offst)!;
            if(asg.var.nm.mut &&
                is_aggregated(asg.var.nm.tpe) &&
                size_known(asg.var.nm.tpe)){
                const mem_size = type_size(asg.var.nm.tpe);
                fmt::fprintfln(buff, "\tblit {}, {}.ptr, {}", asg_val, host_name, mem_size)!;
            } else {
                fmt::fprintfln(buff, "\tstore{} {}, {}.ptr", 
                    qbe_t(ctxt, asg.var.nm.tpe, mode::ASSIGN), asg_val, host_name)!;
            };
        };
    case let arena: *arena_meta =>
        move_ptr(ctxt, ctxt.tokens[arena.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        const temp = fmt::asprintf("%arena.length.{}", arena.pos)!;
        const val = gen_exp(ctxt, buff, temp, arena.length.tpe, arena.length);
        const length =
            if(val != ""){
                free(temp);
                yield val;
            } else {
                yield temp;
            };
        defer free(length);
        const dummy = fmt::asprintf("%tmp.arena.{}", arena.pos)!;
        defer free(dummy);
        fmt::fprintfln(buff, "\t{} =l alloc8 {}",
            dummy, type_size(arena.self.var.nm.tpe))!;
        // store length
        fmt::fprintfln(buff, "\tstorel {}, {}", length, dummy)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dummy)!;
        // store arena pointer
        fmt::fprintfln(buff, "\tstorel 0, {}.ptr", dummy)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}.ptr, 8", dummy)!;
        // allocate arena memory
        fmt::fprintfln(buff,
            "\t{}.chunk =l call $rt.alloc(l {})", dummy, length)!;
        const src = fmt::asprintf("{}.chunk", dummy)!;
        defer free(src);
        const dest = fmt::asprintf("{}.ptr", dummy)!;
        defer free(dest);
        // validate allocation if needed
        if(arena.prop is propagation){
            const prop = arena.prop as propagation;
            if(prop.1 is void && prop.0 == operator::BANG){
                fmt::fprintfln(buff,
                    "\tjnz {0}.chunk, @arena.ok.{1}, @fail",
                    dummy, arena.pos)!;
            } else {
                fmt::fprintfln(buff,
                    "\tjnz {0}.chunk, @arena.ok.{1}, @fail.{1}",
                    dummy, arena.pos)!;
            };
            if(prop.0 == operator::BUBBLE && prop.1 is *expr_meta){
                const exp = prop.1 as *expr_meta;
                const wrap = fmt::asprintf("%default.{}", arena.pos)!;
                defer free(wrap);
                const val = gen_exp(ctxt, buff, wrap,
                    arena.self.var.nm.tpe, exp);
                const asg_val =
                    if(val != ""){
                        yield val;
                    } else {
                        yield wrap;
                    };
                defer if(val != "") free(val);
                fmt::fprintfln(buff,
                    "@fail.{0}\n\t{1} ={2} copy {3}\n@arena.ok.{0}",
                    arena.pos, dest,
                    qbe_t(ctxt, arena.self.var.nm.tpe, mode::ASSIGN),
                    asg_val)!;
            } else {
                fmt::fprintfln(buff, "@arena.ok.{}", arena.pos)!;
            };
        };
        // assign arena with its memory pointer
        const name = fix_nm(ctxt, buff, arena.self.var.nm);
        fmt::fprintfln(buff, "\tstorel {0}.chunk, {0}.ptr", dummy)!;
        fmt::fprintfln(buff, "\t{} =l copy {}", name, dummy)!;
        // gen arena scope
        const body = fmt::asprintf("@{}.body", name)!;
        defer free(body);
        gen_scope(ctxt, buff, arena.body, body);
        // free arena memory
        fmt::fprintfln(buff,
            "\tcall $rt.free(l {}.chunk, l {})", dummy, length)!;
        if(arena.prop is propagation){
            const prop = arena.prop as propagation;
            if(prop.0 == operator::BANG && prop.1 is path_meta){
                fmt::fprintfln(buff, "\tjmp @skip.{0}\n@fail.{0}", arena.pos)!;
                const stt = prop.1 as path_meta;
                gen_stt(ctxt, buff, stt);
                fmt::fprintfln(buff, "@skip.{0}", arena.pos)!;
            } else if(prop.0 == operator::BUBBLE && prop.1 is void){
                fmt::fprintfln(buff, "\tjmp @skip.{0}\n@fail.{0}", arena.pos)!;
                fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                    arena.pos, type_size(arena.host))!;
                fmt::fprintfln(buff, "\tstorel 0, %opt.{}", arena.pos)!;
                fmt::fprintfln(buff, "\tret %opt.{0}\n@skip.{0}", arena.pos)!;
            };
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
                    fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}", ret.pos,
                        type_size(ret.val.tpe))!;
                    fmt::fprintfln(buff, "\tstorel 1, %opt.{}", ret.pos)!;
                    fmt::fprintfln(buff, "\tret %opt.{}", ret.pos)!;
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
                    qbe_t(ctxt, quick_t(ret.val.tpe.base as primitive)),
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
                qbe_t(ctxt, quick_t(ret.val.tpe.base as primitive)), temp)!;
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
    case unreachable =>
        fmt::fprintfln(buff, "\thlt")!;
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
    const val_exp = decl.val as hand_t;
    // value is a literal of something
    if(val_exp is *expr_meta &&
        extract_root(val_exp as *expr_meta) is *const_meta){
        // extract const
        const const_val = extract_root(val_exp as *expr_meta) as *const_meta;
        // emit
        const val = emit_constant(ctxt, buff, const_val, decl.var.nm.tpe);
        defer free(val);
        // assert if a copy is needed
        if(decl.var.nm.mut && strings::hasprefix(val, "$str.")){
            const mem_size = true_size(const_val.val as str);
            fmt::fprintfln(buff, "\t%.dup =l alloc8 {}", mem_size)!;
            fmt::fprintfln(buff, "\tblit {}, %.dup, {}", val, mem_size)!;
            fmt::fprintfln(buff, "\t{} =l copy %.dup", name)!;
        } else {
            fmt::fprintfln(buff, "\t{} ={} copy {}", name,
                qbe_t(ctxt, decl.var.nm.tpe, mode::ASSIGN), val)!;
        };
    } else if(decl.var.nm.mut &&
        is_aggregated(decl.var.nm.tpe) &&
        size_known(decl.var.nm.tpe)){
        gen_exp(ctxt, buff, "%.val", decl.var.nm.tpe, val_exp);
        const mem_size = type_size(decl.var.nm.tpe);
        fmt::fprintfln(buff, "\t%dup =l alloc8 {}", mem_size)!;
        fmt::fprintfln(buff, "\tblit %.val, %dup, {}", mem_size)!;
        fmt::fprintfln(buff, "\t{} =l copy %dup", name)!;
    } else {
        const val = gen_exp(ctxt, buff, name, decl.var.nm.tpe, val_exp);
        if(val != ""){
            defer free(val);
            fmt::fprintfln(buff, "\t{} ={} copy {}", name,
                qbe_t(ctxt, decl.var.nm.tpe, mode::ASSIGN), val)!;
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
                        dest, qbe_t(ctxt, exp_t, mode::ASSIGN), wrap)!;
                } else {
                    fmt::fprintln(buff, "\t{0} ={1} neg {0}",
                        dest, qbe_t(ctxt, exp_t, mode::ASSIGN))!;
                };
            case operator::NOT =>
                if(wrap != ""){
                    fmt::fprintln(buff,
                        "\t{} ={} xor {}, 18446744073709551615",
                        dest, qbe_t(ctxt, exp_t, mode::ASSIGN), wrap)!;
                } else {
                    fmt::fprintln(buff,
                        "\t{0} ={1} xor {0}, 18446744073709551615",
                        dest, qbe_t(ctxt, exp_t, mode::ASSIGN))!;
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
                gen_cast(ctxt, buff, memb, pre_cast, dest, exp_t);
            } else {
                gen_cast(ctxt, buff, temp, pre_cast, dest, exp_t);
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
        gen_cast(ctxt, buff, pos_val, ternary.tpe, dest, exp_t);
        fmt::fprintfln(buff, "\tjmp @end.{0}\n@false.val.{0}", ternary.pos)!;

        const neg_val = fmt::asprintf("%negative.{}", ternary.pos)!;
        defer free(neg_val);
        gen_exp(ctxt, buff, neg_val, ternary.tpe, ternary.negative);
        gen_cast(ctxt, buff, neg_val, ternary.tpe, dest, exp_t);
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
        const asg_t = qbe_t(ctxt, exp_t, mode::ASSIGN);
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
                yield fmt::asprintf("ceq{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
            case operator::NEQ =>
                needs_free = true;
                yield fmt::asprintf("cne{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
            case operator::LEQ =>
                needs_free = true;
                yield if(is_subtype(lft_t, primitive::U64)){
                    yield fmt::asprintf("cule{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                } else if(is_subtype(lft_t, primitive::I64)){
                    yield fmt::asprintf("csle{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                } else {
                    yield fmt::asprintf("cle{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                };
            case operator::GEQ =>
                needs_free = true;
                yield if(is_subtype(lft_t, primitive::U64)){
                    yield fmt::asprintf("cuge{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                } else if(is_subtype(lft_t, primitive::I64)){
                    yield fmt::asprintf("csge{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                } else {
                    yield fmt::asprintf("cge{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                };
            case operator::LST =>
                needs_free = true;
                yield if(is_subtype(lft_t, primitive::U64)){
                    yield fmt::asprintf("cult{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                } else if(is_subtype(lft_t, primitive::I64)){
                    yield fmt::asprintf("cslt{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                } else {
                    yield fmt::asprintf("clt{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                };
            case operator::GTT =>
                needs_free = true;
                yield if(is_subtype(lft_t, primitive::U64)){
                    yield fmt::asprintf("cugt{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                } else if(is_subtype(lft_t, primitive::I64)){
                    yield fmt::asprintf("csgt{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
                } else {
                    yield fmt::asprintf("cgt{}", qbe_t(ctxt, lft_t, mode::ASSIGN))!;
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
        if(comp_type(lft_t, rgt_t) && comp_type(lft_t, exp_t) &&
            !size_mismatch(lft_t, exp_t)){
            gen_cast(ctxt, buff, lft_h, lft_t, dest, exp_t);
            fmt::fprintfln(buff, "\t{0} ={1} {2} {0}, {3}",
                dest, asg_t, inst, rgt_h)!;
        // boolean comparison
        } else if(comp_type(exp_t, primitive::BOOL)){
            if(comp_type(lft_t, primitive::STR) && hand.opr == operator::EQL){
                fmt::fprintfln(buff, "\t{} =l call $rt.strcmp(l {}, l {})",
                    dest, lft_h, rgt_h)!;
            } else if(comp_type(lft_t, primitive::STR) && hand.opr == operator::NEQ){
                fmt::fprintfln(buff, "\t{} =l call $rt.strcmp(l {}, l {})",
                    dest, lft_h, rgt_h)!;
                fmt::fprintfln(buff, "\t{0} =l ceql {0}, 0", dest)!;
            } else {
                fmt::fprintfln(buff, "\t{} ={} {} {}, {}",
                    dest, asg_t, inst, lft_h, rgt_h)!;
            };
        // at least one member require casting
        } else {
            gen_cast(ctxt, buff, lft_h, lft_t, dest, exp_t);
            const rgt_wrap = fmt::asprintf("%r.{}.wrap", hand.pos)!;
            defer free(rgt_wrap);
            if(short_r == ""){
                gen_cast(ctxt, buff, rgt_h, rgt_t, rgt_wrap, exp_t);
                fmt::fprintfln(buff, "\t{0} ={1} {2} {0}, {3}",
                    dest, asg_t, inst, rgt_wrap)!;
            } else {
                fmt::fprintfln(buff, "\t{0} ={1} {2} {0}, {3}",
                    dest, asg_t, inst, rgt_h)!;
            };
        };
    } else if(hand.opr == operator::LAND){
        const asg_t = qbe_t(ctxt, exp_t, mode::ASSIGN);
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
        const asg_t = qbe_t(ctxt, exp_t, mode::ASSIGN);
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
        case let arr_lit: *array_lit_meta =>
            gen_arr_lit(ctxt, buff, dest, exp_t, arr_lit);
            yield (strings::dup(dest)!, arr_lit.tpe, true);
        case let access: *indexing_meta =>
            yield unwrap_fields_and_indexes(ctxt, buff, access);
        case let rec_lit: *record_lit_meta =>
            fmt::fprintfln(buff, "\t{} =l alloc8 {}", dest, type_size(exp_t))!;
            if(exp_t.fail){
                fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
                fmt::fprintfln(buff, "\t{0} =l add {0}, 8", dest)!;
            };
            for(let val .. rec_lit.values){
                fmt::fprint(buff, "\n")!;
                if(comp_type(val.1.tpe, primitive::UNIT) ||
                    comp_type(val.1.tpe, primitive::VOID)) continue;

                const offst = field_offset(rec_lit.tpe.base as *record, val.0);
                if(offst > 0){
                    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, {1}", dest, offst)!;
                } else {
                    fmt::fprintfln(buff, "\t{0}.ptr =l copy {0}", dest)!;
                };
                const field = fmt::asprintf("%field.{}", val.1.pos)!;
                defer free(field);
                const res = gen_exp(ctxt, buff, field, val.1.tpe, val.1);
                const asg_val =
                    if(res != ""){
                        yield res;
                    } else {
                        yield field;
                    };
                defer if(res != "") free(res);
                const type_l = type_size(val.1.tpe);
                if(type_l <= 8){
                    fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
                        qbe_t(ctxt, val.1.tpe), asg_val, dest)!;
                } else {
                    fmt::fprintfln(buff, "\tblit {}, {}.ptr, {}",
                        asg_val, dest, type_l)!;
                };
            };
            if(exp_t.fail){
                fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", dest)!;
            };
            yield ("", rec_lit.tpe, true);
        case let access: *field_meta =>
            yield unwrap_fields_and_indexes(ctxt, buff, access);
        case let var: *var_meta =>
            yield (fix_nm(ctxt, buff, var.nm), var.nm.tpe, false);
        case let call: *funcall_meta =>
            const temp = fmt::asprintf("%tmp.{}", memb.pos)!;
            defer free(temp);
            const nm =
                if(!comp_type(call.fun.fun.tpe, exp_t)){
                    yield temp;
                } else {
                    yield dest;
                };
            yield(gen_funcall(ctxt, buff, call, nm),
                call.fun.fun.tpe, nm == dest);
        case let all: *alloc_meta =>
            move_ptr(ctxt, ctxt.tokens[all.pos]);
            const (l, c) = get_pos(ctxt);
            fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
            // emit source data
            const temp = fmt::asprintf("%arena.src.{}", all.pos)!;
                const val = assign_memb(ctxt, buff, temp, all.tpe, all.val);
                const data =
                    if(val != ""){
                        free(temp);
                        yield val;
                    } else {
                        yield temp;
                    };
                defer free(data);

            const arena = fix_nm(ctxt, buff, all.arena.nm);
            // load arena size
            fmt::fprintfln(buff, "\t{0}.length =l loadl {0}", arena)!;
            // load arena pointer
            fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", arena)!;
            fmt::fprintfln(buff, "\t{0}.at =l loadl {0}.ptr", arena)!;
            // load arena memory base pointer
            fmt::fprintfln(buff, "\t{0}.ptr =l add {0}.ptr, 8", arena)!;
            fmt::fprintfln(buff, "\t{0}.base =l loadl {0}.ptr", arena)!;
            // load current memory position
            fmt::fprintfln(buff, "\t{0}.pos =l add {0}.base, {0}.at", arena)!;
            // reset to arena pointer
            fmt::fprintfln(buff, "\t{0}.ptr =l sub {0}.ptr, 8", arena)!;

            // size known at compile time
            if(!is_subtype(all.tpe, quick_t(primitive::STR, true)) &&
                !(all.tpe.base is *array)){
                fmt::fprintfln(buff, "\t{0}.after =l add {0}.at, {1}",
                    arena, type_size(all.tpe))!;
            // dynamic size
            } else {
                fmt::fprintfln(buff, "\t%data.length.{} =l loadl {}",
                    all.pos, data)!;
                fmt::fprintfln(buff,
                    "\t%data.length.{0} =l add %data.length.{0}, 16", all.pos)!;
                fmt::fprintfln(buff,
                    "\t{0}.after =l add {0}.at, %data.length.{1}",
                    arena, all.pos)!;
            };
            fmt::fprintfln(buff,
                "\t%arena.enough =l culel {0}.after, {0}.length", arena)!;
            if(all.prop is void || (all.prop as operator) == operator::BUBBLE){
                fmt::fprintfln(buff,
                    "\tjnz %arena.enough, @arena.alloc.{0}, @arena.fail.{0}",
                    all.pos)!;
            } else {
                fmt::fprintfln(buff,
                    "\tjnz %arena.enough, @arena.alloc.{}, @fail", all.pos)!;
            };
            if(all.prop is void){
                fmt::fprintfln(buff, "@arena.alloc.{}", all.pos)!;
                fmt::fprintfln(buff, "\t{} =l alloc8 32", dest)!;
                fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
                fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
                fmt::fprintfln(buff, "\tstorel {}.pos, {}.ptr", arena, dest)!;
                fmt::fprintfln(buff, "\t{0}.ptr =l sub {0}.ptr, 8", arena)!;
                fmt::fprintfln(buff, "\tstorel {0}.after, {0}.ptr", arena)!;
            } else {
                fmt::fprintfln(buff, "@arena.alloc.{}", all.pos)!;
                fmt::fprintfln(buff, "\t{0}.ptr =l sub {0}.ptr, 8", arena)!;
                fmt::fprintfln(buff, "\tstorel {0}.after, {0}.ptr", arena)!;
            };    
            // allocate data
            if(!size_known(all.tpe)){
                // fix length
                fmt::fprintfln(buff,
                    "\t%data.length.{0} =l sub %data.length.{0}, 16",
                    all.pos)!;
                // allocate stack handle
                fmt::fprintfln(buff, "\t{} =l copy {}.pos", dest, arena)!;
                fmt::fprintfln(buff,
                    "\tstorel %data.length.{}, {}", all.pos, dest)!;
                fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
                fmt::fprintfln(buff, "\t{0}.data =l add {0}, 16", dest)!;
                fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", data)!;
                fmt::fprintfln(buff, "\t{0}.data =l loadl {0}.ptr", data)!;
                fmt::fprintfln(buff,
                    "\tcall $rt.copy(l {}.data, l {}.data, l %data.length.{})", 
                    dest, data, all.pos)!;
                fmt::fprintfln(buff, "\tstorel {0}.data, {0}.ptr", dest)!;
            } else {
                fmt::fprintfln(buff, "\t{} =l copy {}.pos", dest, arena)!;
                fmt::fprintfln(buff, "\tblit {}, {}, {}",
                    data, dest, type_size(all.tpe, true))!;
            };
            if(all.prop is operator &&
                all.prop as operator == operator::BUBBLE){
                fmt::fprintfln(buff, "\tjmp @arena.end.{}", all.pos)!;
                fmt::fprintfln(buff, "@arena.fail.{}", all.pos)!;
                fmt::fprintfln(buff, "\t{} =l alloc8 {}",
                    dest, type_size(all.host))!;
                fmt::fprintfln(buff, "\tstorel 0, {}", dest)!;
                fmt::fprintfln(buff, "\tret {}", dest)!;
                fmt::fprintf(buff, "@arena.end.{}", all.pos)!;
            };
            yield (dest, all.tpe, true);
        case let kwd: keyword =>
            yield switch(kwd){
            case keyword::TRUE =>
                return strings::dup("1")!;
            case keyword::FALSE =>
                return strings::dup("0")!;
            case keyword::NOMEM =>
                fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                    memb.pos, type_size(exp_t))!;
                fmt::fprintfln(buff, "\tstorel 0, %opt.{}", memb.pos)!;
                return fmt::asprintf("%opt.{}", memb.pos)!;
            case keyword::FAIL =>
                fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                    memb.pos, type_size(memb.tpe))!;
                fmt::fprintfln(buff, "\tstorel -1, %opt.{}", memb.pos)!;
                return fmt::asprintf("%opt.{}", memb.pos)!;
            case =>
                fmt::fatal("assign_memb: unreachable");
            };
        };
    // member has propagation
    if(memb.prop is propagation){
        gen_prop(ctxt, buff, memb.prop as propagation,
            exp_t, tpe, memb.pos, dest, val);
    };
    if(!skip){
        defer free(val);
        gen_cast(ctxt, buff, val, tpe, dest, exp_t);
    };
    if(memb.prop is propagation){
        const prop = memb.prop as propagation;
        if(prop.1 is path_meta){
            fmt::fprintfln(buff, "@skip.{}", memb.pos)!;
        };
    };
    return "";
};

fn gen_arr_lit(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    exp_t: lichen_t,
    arr_lit: *array_lit_meta,
) void = {
    const as_arr = arr_lit.tpe.base as *array;
    if(as_arr.length is size && (arr_lit.tpe.fail || exp_t.fail)){
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", 
            dest, type_size(as_arr.base))!;
        fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
        fmt::fprintfln(buff, "\tstorel {}, {}.ptr", as_arr.length, dest)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
    } else if(as_arr.length is size){
        fmt::fprintfln(buff, "\t{} =l alloc8 {}",
            dest, type_size(arr_lit.tpe))!;
        fmt::fprintfln(buff, "\t{0}.ptr =l copy {0}", dest)!;
        fmt::fprintfln(buff, "\tstorel {}, {}.ptr", as_arr.length, dest)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
    } else {
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", 
            dest, type_size(as_arr.base))!;
        if(arr_lit.tpe.fail || exp_t.fail){
            fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
            fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
        } else {
            fmt::fprintfln(buff, "\t{0}.ptr =l copy {0}", dest)!;
        };
        fmt::fprintfln(buff, "\tstorel 0, {}.ptr", dest)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
        todo("dynamic allocation");
    };
    const spread =
        match(arr_lit.spreads_at){
        case let e: size => yield e;
        case void => yield len(arr_lit.items);
        };
    let last_val = "";
    let last_set = false;
    for(let i = 0z; i < len(arr_lit.items); i += 1){
        fmt::fprint(buff, "\n")!;
        if(i < spread){
            const wrap = fmt::asprintf("{}.itm.{}", dest, i)!;
            defer free(wrap);
            const val = gen_exp(ctxt, buff, wrap, as_arr.base,
                arr_lit.items[i]);
            const asg_val =
                if(val != ""){
                    last_set = false;
                    yield val;
                } else {
                    last_set = true;
                    yield wrap;
                };
            defer if(val != "") free(val);
            fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
                qbe_t(ctxt, as_arr.base), asg_val, dest)!;
        } else {
            const wrap = fmt::asprintf("{}.itm.{}", dest, spread)!;
            defer free(wrap);
            if(i == 0 || !last_set){
                last_val = gen_exp(ctxt, buff, wrap, as_arr.base,
                    arr_lit.items[i]);
                if(last_val != ""){
                    fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
                        qbe_t(ctxt, as_arr.base), last_val, dest)!;
                } else {
                    fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
                        qbe_t(ctxt, as_arr.base), wrap, dest)!;
                };
            } else if(last_val != ""){
                    fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
                    qbe_t(ctxt, as_arr.base), last_val, dest)!;
            } else {
                fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
                    qbe_t(ctxt, as_arr.base), wrap, dest)!;
            };
        };
        if(last_val != "") free(last_val);
        const real = type_size(as_arr.base);
        const offst =
            if(real % 4 > 0){
                yield 4 - real % 4;
            } else {
                yield 0z;
            };
        fmt::fprintfln(buff,
            "\t{0}.ptr =l add {0}.ptr, {1}", dest, real + offst)!;
    };
};

fn unwrap_fields_and_indexes(
    ctxt: *context,
    buff: *memio::stream, 
    access: (*field_meta | *indexing_meta)
) (str, lichen_t, bool) = {
    const load_stack: [](*field_meta | *indexing_meta) = [];
    let next: (void | *field_meta | *indexing_meta) = access;
    let root: (*field_meta | *indexing_meta) = access;
    for(next is (*field_meta | *indexing_meta)){
        const valid = next as (*field_meta | *indexing_meta);
        root = valid;
        append(load_stack, valid)!;
        match(valid){
        case let idx: *indexing_meta =>
            next = idx.before;
        case let fld: *field_meta =>
            next = fld.before;
        };
    };
    const base =
        match(root){
        case let idx: *indexing_meta =>
            yield idx.base as *member_meta;
        case let fld: *field_meta =>
            yield fld.base as *member_meta;
        };
    let last =
        if(root is *field_meta){
            yield fmt::asprintf("%rec.{}",
                (root as *field_meta).pos)!;
        } else {
            yield fmt::asprintf("%arr.{}",
                (root as *indexing_meta).pos)!;
        };
    assign_memb(ctxt, buff, last, base.tpe, base);

    let last_t = base.tpe;
    for(let f = len(load_stack); f > 0; f -= 1){
        const this = load_stack[f - 1];
        if(this is *field_meta){
            const lastest = last;
            last = gen_field(ctxt, buff, last, last_t,
                f, this as *field_meta);
            last_t = (this as *field_meta).tpe;
            free(lastest);
        } else {
            const lastest = last;
            last = gen_index(ctxt, buff, last, last_t,
                f, this as *indexing_meta);
            free(lastest);
            last_t = (this as *indexing_meta).tpe;
        };
    };
    return (last, last_t, false);
};

fn gen_field(
    ctxt: *context,
    buff: *memio::stream,
    base: str,
    base_t: lichen_t,
    idx: size,
    this: *field_meta,
) str = {
    const ptr = fmt::asprintf("%rec.ptr.{}", this.pos + idx)!;
    defer free(ptr);
    const field = fmt::asprintf("%rec.field.{}", this.pos + idx)!;
    const offst = field_offset(this.from_tpe.base as *record, 
        this.field.var.nm.name);
    const val =
        if(offst > 0){
            fmt::fprintfln(buff, "\t{} =l add {}, {}", ptr, base, offst)!;
            yield ptr;
        } else if(idx > 0){
            fmt::fprintfln(buff, "\t{} =l copy {}", ptr, base)!;
            yield ptr;
        } else {
            yield base;
        };
    const type_l = type_size(this.field.var.nm.tpe);
    if(type_l <= 8 && !this.field.var.nm.tpe.fail){
        fmt::fprintfln(buff, "\t{} ={} load{} {}", field,
            qbe_t(ctxt, this.tpe, mode::ASSIGN),
            qbe_t(ctxt, this.field.var.nm.tpe, mode::LOAD), val)!;
    } else if(!this.field.var.nm.tpe.fail){
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", field, type_l)!;
        fmt::fprintfln(buff, "\tblit {}, {}, {}", val, field, type_l)!;
    } else {
        fmt::fprintfln(buff, "\t{}.wrap =l alloc8 {}", field, type_l)!;
        fmt::fprintfln(buff, "\tblit {}, {}.wrap, {}", val, field, type_l)!;
        // field has propagation
        if(this.prop is propagation){
            const prop = this.prop as propagation;
            const wrap = fmt::asprintf("{}.wrap", field)!;
            defer free(wrap);
            gen_prop(ctxt, buff, prop, base_t,
                this.tpe, this.pos, field, wrap);
            fmt::fprintfln(buff, "\t{0} =l add {0}, 8", wrap)!;
            let unwrap_t = this.field.var.nm.tpe;
            unwrap_t.fail = false;
            const res_type_l = type_size(unwrap_t);
            if(res_type_l <= 8){
                fmt::fprintfln(buff, "\t{} ={} load{} {}", field,
                    qbe_t(ctxt, unwrap_t, mode::ASSIGN),
                    qbe_t(ctxt, unwrap_t, mode::LOAD), wrap)!;
            } else {
                fmt::fprintfln(buff, "\t{} =l alloc8 {}", field, res_type_l)!;
                fmt::fprintfln(buff, "\tblit {}, {}, {}", wrap, field, res_type_l)!;
            };
            if(prop.1 is path_meta){
                fmt::fprintfln(buff, "@skip.{}", this.pos)!;
            };
        };
    };
    return field;
};

fn gen_index(
    ctxt: *context,
    buff: *memio::stream,
    base: str,
    base_t: lichen_t,
    idx: size,
    this: *indexing_meta,
) str = {
    // load actual array data
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", base)!;
    const (index, safe, zero): (str, bool, bool) =
        match(this.index){
        case let c: *const_meta =>
            // constant index
            const val = emit_constant(ctxt, buff, c, quick_t(primitive::U64));
            yield (val, true, val == "0");
        case let exp: *expr_meta =>
            // dynamic index
            const arr_idx = fmt::asprintf("{}.idx", base)!;
            const val = gen_exp(ctxt, buff, arr_idx,
                quick_t(primitive::U64), exp);
            // assert for casting
            yield if(val != "" && (!strings::hasprefix(val, "%") ||
                comp_type(exp.tpe, quick_t(primitive::U64)))){
                yield (val, false, val == "0");
            } else if(!comp_type(exp.tpe, quick_t(primitive::U64))){
                const wrap = fmt::asprintf("{}.wrap", arr_idx)!;
                defer free(arr_idx);
                if(val != ""){
                    defer free(val);
                    fmt::fprintfln(buff, "\t{} =l extuw {}", wrap, val)!;
                } else {
                    fmt::fprintfln(buff, "\t{} =l extuw {}", wrap, arr_idx)!;
                };
                yield (wrap, false, false);
            } else {
                yield (arr_idx, false, false);
            };
        };
    defer free(index);
    // adjust offset
    const offst = fmt::asprintf("{}.offset", base)!;
    if(!zero){
        const real = type_size(this.tpe);
        const offst =
            if(real % 4 > 0){
                yield 4 - real % 4;
            } else {
                yield 0z;
            };
        fmt::fprintfln(buff, "\t{}.offset =l mul {}, {}", base, index, real + offst)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}.ptr, {0}.offset", base)!;
    };
    const item = fmt::asprintf("{}.item", base)!;
    const arr = base_t.base as *array;
    if(!safe){
        fmt::fprintfln(buff, "\t{0}.len =l loadl {0}", base)!;
        fmt::fprintfln(buff, "\t%idex.safe =l cultl {}, {}.len", index, base)!;
        fmt::fprintfln(buff,
            "\tjnz %idex.safe, @some.item.{0}, @no.item.{0}\n@no.item.{0}",
            this.pos + idx)!;
        fmt::fprintfln(buff, "\t{} ={} copy {}", item,
                qbe_t(ctxt, arr.base, mode::ASSIGN),
                zeroed_value(ctxt, buff, arr.base))!;
        fmt::fprintfln(buff,
            "\tjmp @index.end.{0}\n@some.item.{0}", this.pos + idx)!;
    };
    const size_t = type_size(arr.base);
    if(size_t <= 8){
        fmt::fprintfln(buff, "\t{} ={} load{} {}.ptr", item,
            qbe_t(ctxt, arr.base, mode::ASSIGN),
            qbe_t(ctxt, arr.base, mode::LOAD), base)!;
    } else {
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", item, size_t)!;
        fmt::fprintfln(buff, "\tblit {}.ptr, {}, {}", base, item, size_t)!;
    };
    if(!safe){
        fmt::fprintfln(buff, "@index.end.{}", this.pos + idx)!;
    };
    return item;
};

fn gen_prop(
    ctxt: *context,
    buff: *memio::stream,
    prop: propagation,
    exp_t: lichen_t,
    tpe: lichen_t,
    pos: size,
    dest: str,
    val: str,
) void = {
    fmt::fprintfln(buff, "\t%fail.code =l loadl {}", val)!;
    fmt::fprintln(buff, "\t%assert.fail =l csltl %fail.code, 1")!;
    // no assertion expression
    if(prop.1 is void){
        if(prop.0 == operator::BUBBLE){
            fmt::fprintfln(buff, "\tjnz %assert.fail, @bubble.{0}, @ok.{0}",
                pos)!;
            fmt::fprintfln(buff, "@bubble.{0}\n\tret {1}\n@ok.{0}", pos, val)!;
        } else {
            fmt::fprintfln(buff, "\tjnz %assert.fail, @fail, @ok.{0}\n@ok.{0}",
                pos)!;
        };
    } else {
        if(prop.0 == operator::BUBBLE){
            const exp = prop.1 as *expr_meta;
            fmt::fprintfln(buff,
                "\tjnz %assert.fail, @bubble.{0}, @ok.{0}\n@bubble.{0}", pos)!;
            const wrap = fmt::asprintf("%default.{}", pos)!;
            defer free(wrap);
            const val = gen_exp(ctxt, buff, wrap, tpe, exp);
            const asg_val =
                if(val != ""){
                    yield val;
                } else {
                    yield wrap;
                };
            defer if(val != "") free(val);
            fmt::fprintfln(buff,
                "\t{1} ={2} copy {3}\n\tjmp @skip.{0}\n@ok.{0}",
                pos, dest, qbe_t(ctxt, exp_t, mode::ASSIGN), asg_val)!;
        } else {
            const stt = prop.1 as path_meta;
            fmt::fprintfln(buff,
                "\tjnz %assert.fail, @fail.{0}, @ok.{0}\n@fail.{0}", pos)!;
            const zero = zeroed_value(ctxt, buff, exp_t);
            defer free(zero);
            fmt::fprintfln(buff, "\t{} ={} copy {}", dest,
                qbe_t(ctxt, exp_t, mode::ASSIGN), zero)!;
            gen_stt(ctxt, buff, stt);
            fmt::fprintfln(buff, "\tjmp @skip.{0}\n@ok.{0}", pos)!;
        };
    };
};

fn gen_funcall(
    ctxt: *context,
    buff: *memio::stream,
    call: *funcall_meta,
    dest: str,
) str = {
    const base_name = strings::replace(call.fun.fun.name, "'", ".q")!;
    defer free(base_name);
    const name =
        if(call.fun.fun.ffi is str){
            yield fmt::asprintf("${}",
                call.fun.fun.ffi as str)!;
        } else if(ctxt.file != call.fun.origin || !ctxt.main){
            const mod = strings::rcut(
                strings::rcut(call.fun.origin, "/").1, ".").0;
            yield fmt::asprintf("${}.{}", mod,
                base_name)!;
        } else {
            yield fmt::asprintf("${}", base_name)!;
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
            owner = ctxt,
            pos = exp.pos,
            lifetime = void,
        };
        append(defs, alloc(temp)!)!;
    };
    if(dest != "" && !comp_type(call.fun.fun.tpe, quick_t(primitive::UNIT))){
        if(call.fun.fun.tpe.fail && call.fun.fun.tpe.base is *record){
            fmt::fprintf(buff, "\t{} ={}.opt call {}", dest,
                qbe_t(ctxt, call.fun.fun.tpe, mode::RETURN), name)!;
        } else {
            fmt::fprintf(buff, "\t{} ={} call {}", dest,
                qbe_t(ctxt, call.fun.fun.tpe, mode::RETURN), name)!;
        };
    } else {
        fmt::fprintf(buff, "\tcall {}", name)!;
    };
    gen_list(ctxt, buff, defs);
    fmt::fprint(buff, "\n")!;
    return strings::dup(dest)!;
};

// generates all needed type casting for an assignment
fn gen_cast(
    ctxt: *context,
    buff: *memio::stream,
    src: str,
    src_t: lichen_t,
    dest: str,
    dest_t: lichen_t,
) void = {
    const dest_qbe_t = qbe_t(ctxt, dest_t, mode::ASSIGN);
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
                qbe_t(ctxt, dest_t, mode::ASSIGN),
                itof(quick_t(primitive::I64), d_tpe_p), src)!;
            return;
        } else if(is_ratio(src_t) &&
            is_subtype(dest_t, primitive::NUMBER)){
            fmt::fprintfln(buff, "\t{} ={} {} {}", dest,
                qbe_t(ctxt, dest_t, mode::ASSIGN),
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
                    dest, dest_qbe_t, qbe_t(ctxt, src_t, mode::LOAD), src)!;
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
                fmt::fprintfln(buff, "\t{} ={} cast {}", dest, dest_qbe_t,
                    src)!;
            };
        } else {
            fmt::fprintfln(buff, "\t{} ={} copy {}", dest, dest_qbe_t, src)!;
        };
    // unwrap
    } else if(src_t.fail && !dest_t.fail){
        // offset loading point to actual data
        fmt::fprintfln(buff, "\t{0} =l add {0}, 8", src)!;
        // deal with data type casting
        const unwrap_t = src_t;
        unwrap_t.fail = false;
        const temp = fmt::asprintf("{}.wrap", dest)!;
        defer free(temp);
        if(!comp_type(unwrap_t, dest_t) && size_mismatch(unwrap_t, dest_t)){
            if(dest_t.base is primitive){
                fmt::fprintfln(buff, "\t{} ={} load{} {}", temp,
                    qbe_t(ctxt, dest_t, mode::ASSIGN), qbe_t(ctxt, dest_t, mode::LOAD), src)!;
            } else {
                fmt::fprintfln(buff, "\t{} =l copy {}", temp, src)!;
            };
            // cast loaded value to desired type
            gen_cast(ctxt, buff, temp, unwrap_t, dest, dest_t);
        } else if(dest_t.base is primitive){
            fmt::fprintfln(buff, "\t{} ={} load{} {}", dest,
                qbe_t(ctxt, dest_t, mode::ASSIGN), qbe_t(ctxt, dest_t, mode::LOAD), src)!;
        } else {
            fmt::fprintfln(buff, "\t{} =l copy {}", dest, src)!;
        };
        // undo offset
        fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", src)!;
    // concrete to partial
    } else if(!src_t.fail && dest_t.fail){
        const size_t = type_size(dest_t);
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", dest, size_t)!;
        fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
        fmt::fprintfln(buff, "\t{0} =l add {0}, 8", dest)!;
        if(size_t <= 8){
            fmt::fprintfln(buff, "\tstore{} {}, {}", qbe_t(ctxt, src_t),
                src, dest)!;
        // TODO: assert for dynamically allocated arrays
        } else {
            fmt::fprintfln(buff, "\tblit {}, {}, {}", src, dest, size_t)!;
        };
        fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", dest)!;
    // both error types;
    } else {
        fmt::fprintfln(buff, "\t{} =l copy {}", dest, src)!;
    };
};

fn fix_nm(ctxt: *context, buff: *memio::stream, nm: namespace) str = {
    if(nm.ffi is str){
        fmt::fprintfln(buff, "\t%{0} ={1} load{2} ${0}", nm.ffi,
            qbe_t(ctxt, nm.tpe, mode::ASSIGN), qbe_t(ctxt, nm.tpe, mode::LOAD))!;
        return fmt::asprintf("%{}", nm.ffi as str)!;
    };
    const name = strings::replace(nm.name, "'", ".q")!;
    defer free(name);
    if(!ctxt.main && nm.glob){
        const mod = strings::rcut(
            strings::rcut(ctxt.file, "/").0, ".").0;
        const wrap = fmt::asprintf("%{}.{}", mod, name)!;
        fmt::fprintfln(buff, "\t{} ={} load{} ${}.{}", wrap,
            qbe_t(ctxt, nm.tpe, mode::ASSIGN), qbe_t(ctxt, nm.tpe, mode::LOAD),
            mod, name)!;
        return wrap;
    } else if(nm.glob){
        fmt::fprintfln(buff, "\t%{0} ={1} load{2} ${0}", name,
            qbe_t(ctxt, nm.tpe, mode::ASSIGN), qbe_t(ctxt, nm.tpe, mode::LOAD))!;
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
        const rec = tpe.base as *record;
        const name = fmt::asprintf("%{}.zero", rec.name.name)!;
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", name, type_size(tpe))!;
        fmt::fprintfln(buff, "\t{0}.ptr =l copy {0}", name)!;
        for(let field .. rec.fields){
            const offst = field_offset(rec, field.1.var.nm.name);
            if(offst > 0){
                fmt::fprintfln(buff, "\t{0}.ptr =l add {0}.ptr, {1}", name,
                    offst)!;
            };
            const zero = zeroed_value(ctxt, buff, field.1.var.nm.tpe);
            fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
                qbe_t(ctxt, field.1.var.nm.tpe), zero, name)!;
        };
        return name;
    };
};
