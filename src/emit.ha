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
        if(tpe.partial){
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
            os::exit(4);
        };
    } else if(tpe.base is *record){
        if(md == mode::RETURN){
            const rec = tpe.base as *record;
            return rec.export_name;
        };
        return "l";
    } else if(tpe.base is *array){
        if(md == mode::RETURN){
            for(let tdef .. ctxt.types){
                if(comp_type(tdef.self, tpe))
                    return tdef.name.name;
            };
            assert(false);
        };
        return "l";
    } else {
        return "l";
    };
};

// gets the given type's in memory type
fn type_size(tpe: lichen_t, ignore_err: bool = false) size = {
    const arg = strtype(tpe);
    defer free(arg);
    assert(!untyped(tpe), arg);

    if(tpe.base is primitive){
        if(tpe.partial && !ignore_err){
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
    } else if(tpe.base is *enum_t){
        const enu = tpe.base as *enum_t;
        return type_size(quick_t(enu.base));
    } else if(tpe.base is *record){
        const rec = tpe.base as *record;
        let length = 0z;
        let prev_tpe = rec.fields[0].1.var.nm.tpe;
        for(let field .. rec.fields){
            const real = type_size(field.1.var.nm.tpe);
            const prev_alignment = type_alignment(prev_tpe);
            const curr_alignment = type_alignment(field.1.var.nm.tpe);
            const offst =
                if(prev_alignment % curr_alignment > 0){
                    yield curr_alignment - prev_alignment % curr_alignment;
                } else {
                    yield 0z;
                };
            length += real + offst;
            prev_tpe = field.1.var.nm.tpe;
        };
        if(tpe.partial) length += 8;
        return length;
    } else if(tpe.base is *tuple){
        todo("tuples");
    } else if(tpe.base is *array){
        const arr = tpe.base as *array;
        const item_size = type_size(arr.base);
        if(arr.length is void){
            if(tpe.partial) return 24;
            return 16;
        } else if(tpe.partial){
            return arr.length as size * item_size + 16;
        } else {
            return arr.length as size * item_size + 8;
        };
    } else {
        assert(false, "unreachable");
        return 0;
    };
};

fn type_alignment(tpe: lichen_t) size = {
    match(tpe.base){
    case primitive =>
        return type_size(tpe);
    case let enu: *enum_t =>
        return type_alignment(quick_t(enu.base));
    case let rec: *record =>
        let max_size = 0z;
        for(let field .. rec.fields){
            const sz = type_alignment(field.1.var.nm.tpe);
            if(sz > max_size){
                max_size = sz;
            };
        };
        return max_size;
    case let tup: *tuple =>
        todo("tuples");
    case let arr: *array =>
        if(arr.length is size){
            return type_alignment(arr.base);
        } else {
            return 8;
        };
    };
};

// fetches the memory offset of a given record field for a given record type
fn field_offset(rec: *record, field_name: str) size = {
    let acc = 0z;
    let found = false;
    let last_tpe = rec.fields[0].1.var.nm.tpe;
    for(let field .. rec.fields){
        if(field.1.var.nm.name == field_name){
            found = true;
            break;
        };
        const real = type_size(field.1.var.nm.tpe);
        const prev_alignment = type_alignment(last_tpe);
        const curr_alignment = type_alignment(field.1.var.nm.tpe);
        const offst =
            if(acc > 0 && curr_alignment % prev_alignment > 0){
                yield curr_alignment - curr_alignment % prev_alignment;
            } else {
                yield 0z;
            };
        acc += real + offst;
        last_tpe = field.1.var.nm.tpe;
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
    assert(!is_ratio(int_t) && is_ratio(float_t));
    // signed
    if(is_subtype(primitive::I8, int_t)){
        if(type_size(int_t) == 4) return "swtof";
        return "sltof";
    // unsigned
    } else {
        if(type_size(int_t) == 4) return "uwtof";
        return "ultof";
    };
};

// casts a floating type to an integer
fn ftoi(float_t: lichen_t, int_t: lichen_t) str = {
    assert(!is_ratio(int_t) && is_ratio(float_t));
    // signed
    if(is_subtype(primitive::I8, int_t)){
        if(type_size(int_t) == 4) return "stosi";
        return "dtosi";
    // unsigned
    } else {
        if(type_size(int_t) == 4) return "stoui";
        return "dtoui";
    };
};

// emits a final object given:
// - the IR
// - its linking objects list
// - the target file name
// - the stdlib path
// - if shared object was set
// - if static archive was set
// - if compiler should keep the temporary files
// - if compilation should be silent
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
            os::exit(4);
        };
    io::write(object, strings::toutf8(memio::string(ir)!))!;
    io::close(object)!;
    // emit assembly
    run_cmd(silent, "qbe", "-o", asm_src, qbe_out);

    const host = os::sysname();
    // append runtime to assembly emission
    const rt_src = fmt::asprintf("{}rt/rt+{}.s", lib_path, host)!;
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
    // append prelude to assembly emission
    const pre_asm = &memio::dynamic();
    defer io::close(pre_asm)!;
    if(!static_lib && !shared_lib){
        const pre_src = fmt::asprintf("{}rt/pre+{}.s", lib_path, host)!;
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

// emits the IR of a given context
fn gen_qbe_ir(ctxt: *context) memio::stream = {
    const ir = memio::dynamic();
    fmt::fprintfln(&ir, "# code emitted by lcc v{}", version)!;
    // emit built-in types
    fmt::fprintln(&ir, "type :opt.t = { l, l }")!;
    fmt::fprintln(&ir, "type :mem.t = { l, l, l }")!;
    fmt::fprintln(&ir, "type :mem.t.opt = { l, l, l, l }")!;
    fmt::fprintln(&ir, "type :str.t = { l, l }")!;
    fmt::fprintln(&ir, "type :str.t.opt = { l, l, l }")!;
    // emit user-defined types
    for(let t .. ctxt.types){
        match(t.self.base){
        case let rec: *record =>
            // emit concrete version
            fmt::fprintf(&ir, "type {} = align 8 {{ ", rec.export_name)!;
            emit_type_lit(ctxt, &ir, t.self);
            fmt::fprintln(&ir, "}")!;
            // emit partial version
            fmt::fprintf(&ir, "type {}.opt = align 8 {{ l, ", rec.export_name)!;
            emit_type_lit(ctxt, &ir, t.self);
            fmt::fprintln(&ir, "}")!;
            // emit zeroed value
            fmt::fprintfln(&ir, "section \".rodata\"")!;
            fmt::fprintfln(&ir, "data ${}.zero = align 8 {{ z {} }}",
                strings::sub(rec.export_name, 1), type_size(t.self))!;
        case *array =>
            fmt::fprintf(&ir, "type {} = align 8 {{ ", t.name.name)!;
            emit_type_lit(ctxt, &ir, t.self);
            fmt::fprintln(&ir, "}")!;
        case let enu: *enum_t =>
            todo("enum types");
        };
    };
    gen_module(ctxt, &ir);
    // emit string literals
    for(let lit = 0z; lit < len(ctxt.literals); lit += 1){
        // emit string literal
        fmt::fprintfln(&ir, "section \".rodata\"")!;
        fmt::fprintfln(&ir, "data $lit.{} = align 8 {{ b \"{}\", b 0 }}",
            lit, ctxt.literals[lit])!;
        // emit constant string value
        fmt::fprintfln(&ir, "section \".rodata\"")!;
        fmt::fprintfln(&ir,
            "data $str.{0} = align 16 {{ l {1}, l $lit.{0} }}",
            lit, true_size(ctxt.literals[lit]))!;
    };
    return ir;
};

fn emit_type_lit(ctxt: *context, buff: *memio::stream, tpe: lichen_t) void = {
    if(tpe.partial){
        fmt::fprint(buff, "l, ")!;
    };
    match(tpe.base){
    case let prim: primitive =>
        fmt::fprintf(buff, "{}, ", qbe_t(ctxt, tpe))!;
    case let rec: *record =>
        for(let field .. rec.fields){
            const this = field.1.var.nm.tpe;
            emit_type_lit(ctxt, buff, this);
        };
    case let arr: *array =>
        fmt::fprint(buff, "l, ")!;
        if(arr.length is void){
            fmt::fprintf(buff, "l, ")!;
        } else if(arr.length is size){
            fmt::fprintf(buff, "{} {}, ",
                qbe_t(ctxt, tpe), arr.length as size)!;
        };
    case => todo("enums emitting");
    };
};

// emits the IR for a given context into the given buffer
fn gen_module(ctxt: *context, buff: *memio::stream) void = {
    for(let defn .. ctxt.global.defs){
        match(defn){
        case let meta: *decl_meta =>
            if(meta.var.nm.ffi is str) continue;
            fmt::fprint(buff, "\n")!;
            const name =
                if(!ctxt.main){
                    const mod = strings::rcut(
                        strings::rcut(ctxt.file, "/").1, ".").0;
                    yield fmt::asprintf("${}.{}", mod,
                        meta.var.nm.name)!;
                } else {
                    yield fmt::asprintf("${}", meta.var.nm.name)!;
                };
            defer free(name);
            if(meta.var.nm.pub) fmt::fprintln(buff, "export ")!;
            // gen value
            const val_meta = meta.val as *const_meta;
            const val = fmt::asprintf("{} {}", qbe_t(ctxt, meta.var.nm.tpe),
                emit_constant(ctxt, buff, val_meta, meta.var.nm.tpe))!;
            defer free(val);
            // emit constant
            fmt::fprintfln(buff, "data {} = align 16 {{ {} }}", name, val)!;
        case let meta: *fun_meta =>
            const old_host = ctxt.host_fun;
            ctxt.host_fun = meta;
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
            } else if(meta.fun.tpe.partial && meta.fun.tpe.base is *record){
                fmt::fprintf(buff, "{}.opt {}",
                    qbe_t(ctxt, meta.fun.tpe, mode::RETURN), name)!;
            } else {
                fmt::fprintf(buff, "{} {}",
                    qbe_t(ctxt, meta.fun.tpe, mode::RETURN), name)!;
            };
            const params: []*var_meta = [];
            defer free(params);
            for(let p .. meta.params){
                const dup = alloc(*p.var)!;
                append(allocd_nodes, dup)!;
                dup.nm.name = fix_nm(ctxt, buff, dup.nm);
                append(params, dup)!;
            };
            // gen parameter list
            gen_list(ctxt, buff, params);
            // gen function body scope
            gen_scope(ctxt, buff, meta.body as *scope_meta, void,
                "@start", true, meta.recursive);
            ctxt.host_fun = old_host;
        case let tpe: *type_meta => void;
        case let module: *module_meta =>
            if(!module.emitted){
                gen_module(module.ctxt, buff);
                module.emitted = true;
            };
        case *effect_t => void;
        };
    };
};

// emits a list of namespaces
// used for function parameters and function call arguments
fn gen_list(ctxt: *context, buff: *memio::stream, names: []*var_meta, ffi: bool = false) void = {
    fmt::fprint(buff, "(")!;
    for(let n .. names){
        if(ffi && is_aggregated(n.nm.tpe) && size_known(n.nm.tpe)){
            fmt::fprintf(buff, "{} {}, ",
                qbe_t(ctxt, n.nm.tpe, mode::RETURN), n.nm.name)!;
        } else {
            fmt::fprintf(buff, "{} {}, ",
                qbe_t(ctxt, n.nm.tpe, mode::ASSIGN), n.nm.name)!;
        };
    };
    fmt::fprint(buff, ")")!;
};

// emits a scope and its statements
// ini_tag is the label declared at the beginning of the scope
// if has_fail is set, a @fail label is declared at the end of
// the scope. use only for function scopes
fn gen_scope(
    ctxt: *context,
    buff: *memio::stream,
    scope: *scope_meta,
    defer_id: (void | size),
    ini_tag: str = "",
    has_fail: bool = false,
    recursive: bool = false,
) void = {
    if(has_fail){
        assert(ini_tag != "");
        fmt::fprintfln(buff, "{{\n{}", ini_tag)!;
        if(recursive){
            fmt::fprintln(buff, "@recursive")!;
        };
    };
    const idx = len(ctxt.defer_stack);
    append(ctxt.defer_stack, scope.defer_stack...)!;
    for(let stt = 0z; stt < len(scope.stt); stt += 1){
        if(stt == len(scope.stt) - 1 && scope.rets){
            for(let d = len(ctxt.defer_stack); d > 0; d -= 1){
                gen_stt(ctxt, buff, ctxt.defer_stack[d - 1], d - 1);
            };
        };
        gen_stt(ctxt, buff, scope.stt[stt], defer_id);
    };
    delete(ctxt.defer_stack[idx..]);
    // unwrap defers
    if(!scope.rets){
        for(let d = len(scope.defer_stack); d > 0; d -= 1){
            gen_stt(ctxt, buff, scope.defer_stack[d - 1], defer_id);
        };
    };
    if(!scope.rets && has_fail){
        if(comp_type(scope.tpe, primitive::VOID)){
            fmt::fprintfln(buff, "\tcall $rt.exit(w 0)\n\thlt")!;
        } else if(comp_type(scope.tpe, quick_t(primitive::VOID, true))){
            fmt::fprintfln(buff, "\tcall $rt.exit(w 1)\n\thlt")!;
        } else if(comp_type(scope.tpe, quick_t(primitive::UNIT))){
            fmt::fprintln(buff, "\tret")!;
        } else if(comp_type(scope.tpe, quick_t(primitive::UNIT, true))){
            fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                scope.pos, type_size(scope.tpe))!;
            fmt::fprintfln(buff, "\tstorel 1, %opt.{}", scope.pos)!;
            fmt::fprintfln(buff, "\tret %opt.{}", scope.pos)!;
        };
    };
    if(has_fail){
        fmt::fprintln(buff, "@fail\n"
            "\tcall $rt.write(w 2, l $rt.errmsg)\n"
            "\tcall $rt.exit(w 1)\n""\thlt\n}")!;
    };
};

// emits the IR for a given statement
fn gen_stt(
    ctxt: *context,
    buff: *memio::stream,
    stt: path_meta,
    defer_id: (void | size),
) void = {
    const lbl_append =
        if(defer_id is size) fmt::asprintf(".{}", defer_id as size)! else "";
    defer if(lbl_append != "") free(lbl_append);
    match(stt){
    case let test: *test_meta =>
        move_ptr(ctxt, ctxt.tokens[test.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        // generate defer-independent label
        const lbl = fmt::asprintf("{}{}", test.pos, lbl_append)!;
        defer free(lbl);
        const wrap = fmt::asprintf("%test.cond")!;
        defer free(wrap);
        const val = gen_exp(ctxt, buff, wrap,
            quick_t(primitive::BOOL), test.cond,defer_id);
        if(val != ""){
            defer free(val);
            fmt::fprintfln(buff,
                "\tjnz {0}, @test.ok.{1}, @fail.{1}", val, lbl)!;
        } else {
            fmt::fprintfln(buff,
                "\tjnz {0}, @test.ok.{1}, @fail.{1}", wrap, lbl)!;
        };
        fmt::fprintfln(buff, "@fail.{}", lbl)!;
        fmt::fprintfln(buff, "\tblit $str.{}, $rt.errmsg, 16", test.str_id)!;
        if(test.props){
            if(len(ctxt.free_on_ret) > 0){
                for(let f .. ctxt.free_on_ret){
                    fmt::fprintln(buff, f)!;
                };
            };
            fmt::fprintfln(buff, "\tstorel 1, $rt.errmsgset")!;
            fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                lbl, type_size(test.host_tpe as lichen_t))!;
            fmt::fprintfln(buff, "\tstorel 0, %opt.{}", lbl)!;
            fmt::fprintfln(buff, "\tret %opt.{}", lbl)!;
            fmt::fprintfln(buff, "@test.ok.{}", lbl)!;
        } else {
            fmt::fprintfln(buff, "\tstorel 1, $rt.errmsgset\n\tjmp @fail")!;
            fmt::fprintfln(buff, "@test.ok.{}", lbl)!;
        };
    case let loop: *for_meta =>
        move_ptr(ctxt, ctxt.tokens[loop.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        // generate defer-independent label
        const lbl = fmt::asprintf("{}{}", loop.pos, lbl_append)!;
        defer free(lbl);
        // local variable
        if(loop.local is *decl_meta){
            gen_decl(ctxt, buff, loop.local as *decl_meta, defer_id);
        };
        // fetch iterator
        const iter = fetch_iterator(ctxt, buff, loop.pos,
            loop.iter, loop.iter_t, defer_id);
        defer free(iter);
        const (arr_tpe, _) = wrap_array(ctxt, loop.iter_t);
        const as_arr = arr_tpe.base as *array;
        if(as_arr.length is void){
            fmt::fprintfln(buff,
            "\t{0}.data =l add {0}, 8\n\t{0}.data =l loadl {0}.data",
            iter)!;
        } else {
            fmt::fprintfln(buff, "\t{0}.data =l add {0}, 8", iter)!;
        };
        // loop condition
        fmt::fprintfln(buff, "\t%loop.max.{} =l loadl {}", lbl, iter)!;
        const idx =
            if(loop.indx == null){
                yield fmt::asprintf("%loop.idx.{}", lbl)!;
            } else {
                yield fix_nm(ctxt, buff, (loop.indx as *decl_meta).var.nm);
            };
        defer free(idx);
        fmt::fprintfln(buff, "\t{} =l copy 0", idx)!;
        const item_sz = type_size(loop.item.var.nm.tpe);
        // iteration item
        const item = fix_nm(ctxt, buff, loop.item.var.nm);
        if(item_sz > 8){
            fmt::fprintfln(buff, "\t{} =l alloc8 {}", item, item_sz)!;
        };
        // main loop condition checking
        fmt::fprintfln(buff,
            "@loop.rep.{0}\n"
            "\t%loop.rep.{0} =l cultl {1}, %loop.max.{0}",
            lbl, idx)!;
        fmt::fprintfln(buff,
            "\tjnz %loop.rep.{0}, @loop.pre.{0}, @loop.end.{0}", lbl)!;
        // process array offset
        fmt::fprintfln(buff, "@loop.pre.{}", lbl)!;
        const tpe_sz = type_size(loop.item.var.nm.tpe);
        if(tpe_sz > 1){
            fmt::fprintfln(buff, "\t%loop.offset.{} =l mul {}, {}",
                lbl, idx, tpe_sz)!;
        } else {
            fmt::fprintfln(buff, "\t%loop.offset.{} =l copy {}", lbl, idx)!;
        };
        // offset array
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}.data, %loop.offset.{1}",
            iter, lbl)!;
        // iteration item assignment
        defer free(item);
        if(item_sz <= 8){
            fmt::fprintfln(buff, "\t{} ={} load{} {}.ptr", item,
                qbe_t(ctxt, loop.item.var.nm.tpe, mode::ASSIGN),
                qbe_t(ctxt, loop.item.var.nm.tpe, mode::LOAD), iter)!;
        } else {
            fmt::fprintfln(buff,
                "\tblit {}.ptr, {}, {}", iter, item, item_sz)!;
        };
        // body scope
        fmt::fprintfln(buff, "@loop.body.{}", lbl)!;
        gen_scope(ctxt, buff, loop.body, defer_id);
        fmt::fprintfln(buff,
            "@loop.next.{0}\n\t{1} =l add {1}, 1", lbl, idx)!;
        if(loop.mut){
            const tpe_sz = type_size(loop.item.var.nm.tpe);
            if(tpe_sz <= 8){
                fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
                    qbe_t(ctxt, loop.item.var.nm.tpe),
                    item, iter)!;
            } else {
                fmt::fprintfln(buff, "\tblit {}, {}.ptr, {}",
                    item, iter, tpe_sz)!;
            };
        };
        fmt::fprintfln(buff, "\tjmp @loop.rep.{0}\n@loop.end.{0}", lbl)!;
    case let loop: *while_meta =>
        move_ptr(ctxt, ctxt.tokens[loop.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        // generate defer-independent label
        const lbl = fmt::asprintf("{}{}", loop.pos, lbl_append)!;
        defer free(lbl);
        // local variable
        if(loop.local is *decl_meta){
            gen_decl(ctxt, buff, loop.local as *decl_meta, defer_id);
        };
        const cond = fmt::asprintf("%cond.{}", lbl)!;
        fmt::fprintfln(buff, "@loop.rep.{}", lbl)!;
        const val = gen_exp(ctxt, buff, cond, quick_t(primitive::BOOL),
            loop.cond, defer_id);
        if(val != ""){
            defer free(val);
            fmt::fprintfln(buff, "\t{} =l copy {}", cond, val)!;
        };
        // main loop condition checking
        fmt::fprintfln(buff,
            "\tjnz {0}, @loop.body.{1}, @loop.end.{1}",
            cond, lbl)!;
        // body scope
        fmt::fprintfln(buff, "@loop.body.{}", lbl)!;
        gen_scope(ctxt, buff, loop.body, defer_id);
        fmt::fprintfln(buff, "\tjmp @loop.rep.{0}\n@loop.end.{0}", lbl)!;
    case let swtch: *switch_meta =>
        move_ptr(ctxt, ctxt.tokens[swtch.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        // generate defer-independent label
        const lbl = fmt::asprintf("{}{}", swtch.pos, lbl_append)!;
        defer free(lbl);
        // local variable
        if(swtch.local is *decl_meta){
            gen_decl(ctxt, buff, swtch.local as *decl_meta, defer_id);
        };
        const check = fmt::asprintf("%switch.check.{}", lbl)!;
        defer free(check);
        const val = gen_exp(ctxt, buff, check,
            swtch.check.tpe, swtch.check, defer_id);
        if(val != ""){
            defer free(val);
            fmt::fprintfln(buff, "\t{} ={} copy {}", check,
                qbe_t(ctxt, swtch.check.tpe, mode::ASSIGN), val)!;
        };
        // emit all branches 
        for(let b = 0z; b < len(swtch.cases); b += 1){
            // except for else
            if(swtch.else_case is size &&
                b == swtch.else_case as size){
                continue;
            };
            fmt::fprintfln(buff, "@switch.case.{}.{}", lbl, b)!;
            const (_vals, op, body) = swtch.cases[b];
            const vals = _vals as []*const_meta;
            if(op is void || op as operator != operator::RANGE){
                for(let c = 0z; c < len(vals); c += 1){
                    const const_val = vals[c];
                    // emit current constant
                    const val = emit_constant(ctxt, buff,
                        const_val, swtch.check.tpe);
                    defer free(val);
                    if(!comp_type(swtch.check.tpe, primitive::STR)){
                        // fetch qbe instruction
                        const (inst, needs_free) = if(op is void || c + 1 < len(vals)){
                            yield fetch_instruct(ctxt, operator::EQL,
                                swtch.check.tpe, swtch.check.tpe);
                        } else {
                            assert(op is operator);
                            yield fetch_instruct(ctxt, operator::GEQ,
                                swtch.check.tpe, swtch.check.tpe);
                        };
                        defer if(needs_free) free(inst);
                        // check equality
                        fmt::fprintfln(buff,
                            "@switch.const.{0}.{1}.{2}\n"
                            "\t%switch.cond.{0} =l {3} %switch.check.{0}, {4}",
                            lbl, b, c, inst, val)!;
                    } else {
                        assert(op is void);
                        // check equality
                        fmt::fprintfln(buff,
                            "@switch.const.{0}.{1}.{2}\n"
                            "\t%switch.cond.{0} =l call $rt.strcmp(l %switch.check.{0}, l {3})",
                            lbl, b, c, val)!;
                    };
                    // jump to next constant
                    if(c + 1 < len(vals)){
                        fmt::fprintfln(buff,
                            "\tjnz %switch.cond.{0}, "
                            "@switch.case.{0}.{1}.ok, @switch.const.{0}.{1}.{2}",
                            lbl, b, c + 1)!;
                    // jump to next branch
                    } else if(b + 1 < len(swtch.cases) || swtch.else_case is void){
                        fmt::fprintfln(buff,
                            "\tjnz %switch.cond.{0}, @switch.case.{0}.{1}.ok, "
                            "@switch.case.{0}.{2}",
                            lbl, b, b + 1)!;
                    // jump to else case
                    } else {
                        const idx = swtch.else_case as size;
                        fmt::fprintfln(buff,
                            "\tjnz %switch.cond.{0}, @switch.case.{0}.{1}.ok, "
                            "@switch.case.{0}.{2}",
                            lbl, b, idx)!;
                    };
                };
            } else {
                // emit ranges
                const start_range = emit_constant(ctxt,
                    buff, vals[0], swtch.check.tpe);
                defer free(start_range);
                const end_range = emit_constant(ctxt,
                    buff, vals[1], swtch.check.tpe);
                defer free(end_range);
                // fetch qbe instructions
                const (start_inst, free_start) =
                    fetch_instruct(ctxt, operator::GEQ,
                    swtch.check.tpe, swtch.check.tpe);
                defer if(free_start) free(start_inst);
                const (end_inst, free_end) =
                    fetch_instruct(ctxt, operator::LEQ,
                    swtch.check.tpe, swtch.check.tpe);
                defer if(free_end) free(end_inst);
                // check equality for start interval
                fmt::fprintfln(buff,
                    "@switch.const.{0}.{1}.{2}\n"
                    "\t%switch.cond.{0}.start =l {3} %switch.check.{0}, {4}",
                    lbl, b, c, start_inst, start_range)!;
                fmt::fprintfln(buff,
                    "\t%switch.cond.{0}.end =l {1} %switch.check.{0}, {2}",
                    lbl, end_inst, end_range)!;
                fmt::fprintfln(buff,
                    "\t%switch.cond.{0} =l and %switch.cond.{0}.start, "
                    "%switch.cond.{0}.end", lbl)!;
                // jump to next branch
                if(b + 1 < len(swtch.cases) || swtch.else_case is void){
                    fmt::fprintfln(buff,
                        "\tjnz %switch.cond.{0}, @switch.case.{0}.{1}.ok, "
                        "@switch.case.{0}.{2}",
                        lbl, b, b + 1)!;
                // jump to else case
                } else {
                    const idx = swtch.else_case as size;
                    fmt::fprintfln(buff,
                        "\tjnz %switch.cond.{0}, @switch.case.{0}.{1}.ok, "
                        "@switch.case.{0}.{2}",
                        lbl, b, idx)!;
                };
            };
            fmt::fprintfln(buff, "@switch.case.{0}.{1}.ok", lbl, b)!;
            if(body is *scope_meta){
                (ctxt, buff, body as *scope_meta,);
                if(!(body as *scope_meta).rets &&
                    !is_terminal((body as *scope_meta).tpe)){
                    fmt::fprintfln(buff, "\tjmp @switch.end.{0}", lbl)!;
                };
            } else {
                gen_stt(ctxt, buff, body, defer_id);
                // check if a jump is necessary
                const (_, last_tpe, _) = fetch_ret_state(ctxt,
                    quick_t(primitive::ANY), false, body);
                if(!is_terminal(last_tpe)){
                    fmt::fprintfln(buff, "\tjmp @switch.end.{0}", lbl)!;
                };
            };
        };
        if(swtch.else_case is size){
            const idx = swtch.else_case as size;
            const (_, _, body) = swtch.cases[idx];
            fmt::fprintfln(buff, "@switch.case.{0}.{1}", lbl, idx)!;
            if(body is *scope_meta){
                gen_scope(ctxt, buff, body as *scope_meta, defer_id);
                if(!(body as *scope_meta).rets &&
                    !is_terminal((body as *scope_meta).tpe)){
                    fmt::fprintfln(buff, "\tjmp @switch.end.{0}", lbl)!;
                };
            } else {
                gen_stt(ctxt, buff, body, defer_id);
                // check if a jump is necessary
                const (_, last_tpe, _) = fetch_ret_state(ctxt,
                    quick_t(primitive::ANY), false, body);
                if(!is_terminal(last_tpe)){
                    fmt::fprintfln(buff, "\tjmp @switch.end.{0}", lbl)!;
                };
            };
        };
        if(!swtch.rets){
            fmt::fprintfln(buff, "@switch.end.{0}", lbl)!;
        };
    case let decl: *decl_meta =>
        gen_decl(ctxt, buff, decl, defer_id);
    case let asg: *assign_meta =>
        move_ptr(ctxt, ctxt.tokens[asg.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        const wrap = fmt::asprintf("%asg.val.{}", asg.pos)!;
        defer free(wrap);
        const name = fix_nm(ctxt, buff, asg.var.nm);
        defer free(name);
        if(asg.host is void){
            const val = gen_exp(ctxt, buff, wrap,
                asg.var.nm.tpe, asg.val, defer_id);
            const asg_val =
                if(val != ""){
                    yield val;
                } else {
                    yield wrap;
                };
            defer if(val != "") free(val);
            if(is_aggregated(asg.var.nm.tpe) && size_known(asg.var.nm.tpe)){
                const mem_size = type_size(asg.var.nm.tpe);
                fmt::fprintfln(buff, "\tblit {}, {}, {}",
                    asg_val, name, mem_size)!;
            } else {
                fmt::fprintfln(buff, "\t{} ={} copy {}", name,
                    qbe_t(ctxt, asg.var.nm.tpe, mode::ASSIGN), asg_val)!;
            };
        } else {
            const load_stack: []chain_exp_t = [];
            let next: (void | ...chain_exp_t) = asg.host;
            let root: chain_exp_t = asg.host as chain_exp_t;
            for(next is chain_exp_t){
                const valid = next as chain_exp_t;
                root = valid;
                append(load_stack, valid)!;
                match(valid){
                case let idx: *indexing_meta =>
                    next = idx.before;
                case let slc: *slicing_meta =>
                    next = slc.before;
                case let fld: *field_meta =>
                    next = fld.before;
                };
            };
            const base =
                match(root){
                case let idx: *indexing_meta =>
                    yield idx.base as *member_meta;
                case let slc: *slicing_meta =>
                    yield slc.base as *member_meta;
                case let fld: *field_meta =>
                    yield fld.base as *member_meta;
                };
            let last =
                if(root is *field_meta){
                    yield fmt::asprintf("%rec.{}",
                        (root as *field_meta).pos)!;
                } else if(root is *indexing_meta){
                    yield fmt::asprintf("%arr.{}",
                        (root as *indexing_meta).pos)!;
                } else {
                    yield fmt::asprintf("%slc.{}",
                        (root as *slicing_meta).pos)!;
                };
            assign_memb(ctxt, buff, last, base.tpe, base, defer_id);
            let last_t = asg.var.nm.tpe;
            for(let f = len(load_stack); f > 0; f -= 1){
                const this = load_stack[f - 1];
                match(this){
                case let idx: *indexing_meta =>
                    const new = gen_index(ctxt, buff, last,
                        idx.from_tpe, f, idx, defer_id, true);
                    last_t = idx.tpe;
                    free(last);
                    last = new;
                case let fld: *field_meta =>
                    const new = gen_field(ctxt, buff, last,
                        fld.tpe, f, fld, defer_id, true);
                    last_t = fld.tpe;
                    free(last);
                    last = new;
                case let slc: *slicing_meta =>
                    const new = gen_slice(ctxt, buff, last,
                        slc.tpe, f, slc, defer_id);
                    last_t = slc.tpe;
                    free(last);
                    last = new;
                };
            };
            defer free(last);
            const val = gen_exp(ctxt, buff, wrap,
                last_t, asg.val, defer_id);
            const asg_val =
                if(val != ""){
                    yield val;
                } else {
                    yield wrap;
                };
            defer if(val != "") free(val);
            const val_tpe_sz = type_size(last_t);
            if(val_tpe_sz <= 8){
                fmt::fprintfln(buff, "\tstore{} {}, {}",
                    qbe_t(ctxt, last_t), asg_val, last)!;
            } else {
                fmt::fprintfln(buff, "\tblit {}, {}, {}",
                    asg_val, last, val_tpe_sz)!;
            };
        };
    case let arena: *arena_meta =>
        move_ptr(ctxt, ctxt.tokens[arena.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        // generate defer-independent label
        const lbl = fmt::asprintf("{}{}", arena.pos, lbl_append)!;
        defer free(lbl);
        // initialize arena
        const temp = fmt::asprintf("%arena.length.{}", lbl)!;
        const val = gen_exp(ctxt, buff, temp,
            arena.length.tpe, arena.length, defer_id);
        const length =
            if(val != ""){
                free(temp);
                yield val;
            } else {
                yield temp;
            };
        defer free(length);
        const dummy = fmt::asprintf("%tmp.arena.{}", lbl)!;
        defer free(dummy);

        // save previous free on return state
        append(ctxt.free_on_ret, fmt::asprintf(
            "\tcall $rt.free(l {}.chunk, l {})", dummy, length)!)!;

        fmt::fprintfln(buff, "\t{} =l alloc8 {}",
            dummy, type_size(arena.self.var.nm.tpe))!;
        // store length
        fmt::fprintfln(buff, "\tstorel {}, {}", length, dummy)!;
        // store arena pointer
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dummy)!;
        fmt::fprintfln(buff, "\tstorel 0, {}.ptr", dummy)!;
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
            fmt::fprintfln(buff, "\tblit $str.{}, $rt.errmsg, 16", prop.2)!;
            if(prop.1 is void && prop.0 == operator::BANG){
                fmt::fprintfln(buff,
                    "\tjnz {0}.chunk, @arena.ok.{1}, @fail",
                    dummy, lbl)!;
            } else {
                fmt::fprintfln(buff,
                    "\tjnz {0}.chunk, @arena.ok.{1}, @fail.{1}",
                    dummy, lbl)!;
            };
            if(prop.0 == operator::BUBBLE && prop.1 is *expr_meta){
                const exp = prop.1 as *expr_meta;
                const wrap = fmt::asprintf("%default.{}", lbl)!;
                defer free(wrap);
                const val = gen_exp(ctxt, buff, wrap,
                    arena.self.var.nm.tpe, exp, defer_id);
                const asg_val =
                    if(val != ""){
                        yield val;
                    } else {
                        yield wrap;
                    };
                defer if(val != "") free(val);
                fmt::fprintfln(buff,
                    "@fail.{0}\n\t{1} ={2} copy {3}\n@arena.ok.{0}",
                    lbl, dest,
                    qbe_t(ctxt, arena.self.var.nm.tpe, mode::ASSIGN),
                    asg_val)!;
            } else {
                fmt::fprintfln(buff, "@arena.ok.{}", lbl)!;
            };
        };
        // assign arena with its memory pointer
        const name = fix_nm(ctxt, buff, arena.self.var.nm);
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 16", dummy)!;
        fmt::fprintfln(buff, "\tstorel {0}.chunk, {0}.ptr", dummy)!;
        fmt::fprintfln(buff, "\t{} =l copy {}", name, dummy)!;
        // gen arena scope
        fmt::fprintfln(buff, "@{}.body", strings::sub(name, 1))!;
        gen_scope(ctxt, buff, arena.body, defer_id);
        // free arena memory
        if(!arena.body.rets){
            fmt::fprintln(buff,
                ctxt.free_on_ret[len(ctxt.free_on_ret) - 1])!;
        };
        free(ctxt.free_on_ret[len(ctxt.free_on_ret) - 1]);
        delete(ctxt.free_on_ret[len(ctxt.free_on_ret) - 1]);
        if(arena.prop is propagation){
            const prop = arena.prop as propagation;
            if(prop.0 == operator::BANG && prop.1 is path_meta){
                if(!arena.body.rets){
                    fmt::fprintfln(buff, "\tjmp @skip.{}", lbl)!;
                };
                fmt::fprintfln(buff, "@fail.{}", lbl)!;
                const stt = prop.1 as path_meta;
                gen_stt(ctxt, buff, stt, defer_id);
                if(!arena.body.rets){
                    fmt::fprintfln(buff, "@skip.{0}", lbl)!;
                };
            } else if(prop.0 == operator::BUBBLE && prop.1 is void){
                if(!arena.body.rets){
                    fmt::fprintfln(buff, "\tjmp @skip.{}", lbl)!;
                };
                fmt::fprintfln(buff, "@fail.{}", lbl)!;
                if(len(ctxt.free_on_ret) > 0){
                    for(let f .. ctxt.free_on_ret){
                        fmt::fprintln(buff, f)!;
                    };
                };
                fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                    lbl, type_size(arena.host))!;
                fmt::fprintfln(buff, "\tstorel 0, %opt.{}", lbl)!;
                fmt::fprintfln(buff, "\tret %opt.{0}\n@skip.{0}", lbl)!;
            };
        };
    case let branch: *branch_meta =>
        move_ptr(ctxt, ctxt.tokens[branch.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        // generate defer-independent label
        const lbl = fmt::asprintf("{}{}", branch.pos, lbl_append)!;
        defer free(lbl);
        const cond = fmt::asprintf("%cond.{}", lbl)!;
        for(let i = 0z; i < len(branch.bodies); i += 1){
            if(i < len(branch.conds)){
                if(branch.bodies[i].0 is *decl_meta){
                    gen_decl(ctxt, buff,
                        branch.bodies[i].0 as *decl_meta, defer_id);
                };
                const val = gen_exp(ctxt, buff, cond,
                    quick_t(primitive::BOOL),
                    branch.conds[i], defer_id);
                if(val == "1"){
                    free(val);
                } else if(val != ""){
                    defer free(val);
                    fmt::fprintfln(buff,
                        "\tjnz {0}, @true.{1}.{2}, @false.{1}.{2}", val,
                        lbl, i)!;
                } else {
                    fmt::fprintfln(buff,
                        "\tjnz {0}, @true.{1}.{2}, @false.{1}.{2}", cond,
                        lbl, i)!;
                };
                fmt::fprintfln(buff, "@true.{}.{}", lbl, i)!;
                gen_scope(ctxt, buff, branch.bodies[i].1, defer_id);
                if(!branch.bodies[i].1.rets &&
                    !is_terminal(branch.bodies[i].1.tpe)){
                    fmt::fprintfln(buff, "\tjmp @end.{}", lbl)!;
                };
                fmt::fprintfln(buff, "@false.{}.{}", lbl, i)!;
            } else {
                gen_scope(ctxt, buff, branch.bodies[i].1, defer_id);
                if(!branch.bodies[i].1.rets &&
                    !is_terminal(branch.bodies[i].1.tpe)){
                    fmt::fprintfln(buff, "\tjmp @end.{}", lbl)!;
                };
            };
        };
        if(!(branch.rets && len(branch.bodies) > len(branch.conds))){
            fmt::fprintfln(buff, "@end.{}", lbl)!;
        };
    case let ret: *return_meta =>
        move_ptr(ctxt, ctxt.tokens[ret.pos]);
        const (l, c) = get_pos(ctxt);
        fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
        if(len(ctxt.free_on_ret) > 0){
            for(let f .. ctxt.free_on_ret){
                fmt::fprintln(buff, f)!;
            };
        };
        // skip expression for empty returns
        if(ret.val.val is void || comp_type(ret.val.tpe, primitive::UNIT)){
            if(comp_type(ret.tpe, quick_t(primitive::VOID))){
                fmt::fprintln(buff, "\tcall $rt.exit(w 0)\n\thlt")!;
            } else if(comp_type(ret.tpe, quick_t(primitive::VOID, true))){
                fmt::fprintln(buff, "\tcall $rt.exit(w 1)\n\thlt")!;
            } else {
                if(!ret.tpe.partial){
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
        const memb = gen_exp(ctxt, buff, temp, ret.val.tpe, ret.val, defer_id);
        if(memb != ""){
            defer free(memb);
            if(ret.tpe.partial &&
                ret.tpe.base is primitive &&
                ret.val.val is hand_t &&
                assert_no_error_val(ret.val.val as hand_t)){    
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
        } else if(ret.tpe.partial &&
            ret.tpe.base is primitive &&
            !ret.val.tpe.partial){
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
        // generate expression and assign it to temporary
        const temp = fmt::asprintf("%exp.{}", exp.pos)!;
        defer free(temp);
        const memb = gen_exp(ctxt, buff, temp, exp.tpe, exp, defer_id);
    case let pos: loop_break =>
        fmt::fprintfln(buff, "\tjmp @loop.end.{}{}", pos: size, lbl_append)!;
    case let pos: loop_next =>
        fmt::fprintfln(buff, "\tjmp @loop.next.{}{}", pos: size, lbl_append)!;
    case *defer_meta => void;
    case unreachable =>
        fmt::fprintfln(buff, "\thlt")!;
    };
};

fn fetch_iterator(
    ctxt: *context,
    buff: *memio::stream,
    pos: size,
    iter: iterator_t,
    iter_t: lichen_t,
    defer_id: (void | size),
    allocate_at: (void | str) = void,
) str = {
    match(iter){
    case let var: *var_meta =>
        return fix_nm(ctxt, buff, var.nm);
    case let call: *funcall_meta =>
        const anon = fmt::asprintf("%anon.arr.{}", pos)!;
        gen_funcall(ctxt, buff, call, anon, defer_id);
        return anon;
    case let arr: *array_lit_meta =>
        const anon = fmt::asprintf("%anon.arr.{}", pos)!;
        gen_arr_lit(ctxt, buff, anon, arr.tpe, arr, defer_id, allocate_at);
        return anon;
    case let access: *indexing_meta =>
        const anon = fmt::asprintf("%indx.arr.{}", pos)!;
        const (val, tpe, _) =
            unwrap_fields_and_indexes(ctxt, buff, access, defer_id);
        fmt::fprintfln(buff, "\t{} =l copy {}", anon, val)!;
        return anon;
    case let access: *slicing_meta =>
        const anon = fmt::asprintf("%indx.arr.{}", pos)!;
        const (val, tpe, _) =
            unwrap_fields_and_indexes(ctxt, buff, access, defer_id);
        fmt::fprintfln(buff, "\t{} =l copy {}", anon, val)!;
        return anon;
    case let access: *field_meta =>
        const anon = fmt::asprintf("%field.arr.{}", pos)!;
        const (val, tpe, _) =
            unwrap_fields_and_indexes(ctxt, buff, access, defer_id);
        fmt::fprintfln(buff, "\t{} =l copy {}", anon, val)!;
        return anon;
    case let all: *alloc_meta =>
        const anon = fmt::asprintf("%anon.arr.{}", pos)!;
        gen_alloc(ctxt, buff, anon, all, defer_id);
        return anon;
    case let lit: *const_meta =>
        const val = emit_constant(ctxt, buff, lit, iter_t);
        const anon = fmt::asprintf("%anon.arr.{}", pos)!;
        fmt::fprintfln(buff, "\t{} =l copy {}", anon, val)!;
        return anon;
    };
};

// asserts a given hand_t is not a fail singleton literal
fn assert_no_error_val(val: hand_t) bool = {
    if(val is *member_meta){
        const memb = val as *member_meta;
        return !(memb.val is keyword &&
            (comp_tk(memb.val as keyword, keyword::ERROR) ||
            comp_tk(memb.val as keyword, keyword::NIL)));
    };
    return true;
};

// emits a variable declaration
fn gen_decl(
    ctxt: *context,
    buff: *memio::stream,
    decl: *decl_meta,
    defer_id: (void | size),
) void = {
    move_ptr(ctxt, ctxt.tokens[decl.var.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;

    const name = fix_nm(ctxt, buff, decl.var.nm);
    defer free(name);
    const val_exp = decl.val as hand_t;
    const root = extract_root(val_exp as *expr_meta);
    // value is a literal of something
    if(val_exp is *expr_meta && root is *const_meta){
        // extract const
        const const_val = root as *const_meta;
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
    } else if(is_aggregated(decl.var.nm.tpe) && size_known(decl.var.nm.tpe) &&
        !(root is *alloc_meta) && !(root is *record_lit_meta) &&
        !(root is *array_lit_meta)){
        const val = gen_exp(ctxt, buff, "%stack.dup",
            decl.var.nm.tpe, val_exp, defer_id);
        const mem_size = type_size(decl.var.nm.tpe);
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", name, mem_size)!;
        if(val != ""){
            defer free(val);
            fmt::fprintfln(buff, "\tblit {}, {}, {}", val, name, mem_size)!;
        } else {
            fmt::fprintfln(buff, "\tblit %stack.dup, {}, {}", name, mem_size)!;
        };
    } else {
        const val = gen_exp(ctxt, buff, name,
            decl.var.nm.tpe, val_exp, defer_id);
        if(val != ""){
            defer free(val);
            fmt::fprintfln(buff, "\t{} ={} copy {}", name,
                qbe_t(ctxt, decl.var.nm.tpe, mode::ASSIGN), val)!;
        };
    };
};

// emits a given expression
// if a final result is generated, returns the value or temporary name, if not
// returns an empty string
fn gen_exp(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    exp_t: lichen_t,
    exp: hand_t,
    defer_id: (void | size),
) str = {
    match(exp){
    case let hand: *hand_meta =>
        gen_arithmetic(ctxt, buff, dest, exp_t, hand, defer_id);
    case let memb: *member_meta =>
        const wrap = assign_memb(ctxt, buff, dest, exp_t, memb, defer_id);
        if(memb.pre is operator){
            switch(memb.pre as operator){
            case operator::PLS =>
                if(wrap != ""){
                    return wrap;
                };
            case operator::MIN =>
                if(wrap != ""){
                    fmt::fprintfln(buff, "\t{} ={} neg {}",
                        dest, qbe_t(ctxt, exp_t, mode::ASSIGN), wrap)!;
                } else {
                    fmt::fprintfln(buff, "\t{0} ={1} neg {0}",
                        dest, qbe_t(ctxt, exp_t, mode::ASSIGN))!;
                };
            case operator::NOT =>
                if(wrap != ""){
                    fmt::fprintfln(buff,
                        "\t{} ={} xor {}, 18446744073709551615",
                        dest, qbe_t(ctxt, exp_t, mode::ASSIGN), wrap)!;
                } else {
                    fmt::fprintfln(buff,
                        "\t{0} ={1} xor {0}, 18446744073709551615",
                        dest, qbe_t(ctxt, exp_t, mode::ASSIGN))!;
                };
            case operator::BANG =>
                if(wrap != ""){
                    fmt::fprintfln(buff, "\t{} ={} ceql {}, 0",
                        dest, qbe_t(ctxt, exp_t, mode::ASSIGN), wrap)!;
                } else {
                    fmt::fprintfln(buff, "\t{0} ={1} ceql {0}, 0",
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
                fmt::println(oper_value[memb.pre as operator])!;
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
                exp.val as hand_t, defer_id);
            if(memb != ""){
                gen_cast(ctxt, buff, memb, pre_cast, dest, exp_t);
            } else {
                gen_cast(ctxt, buff, temp, pre_cast, dest, exp_t);
            };
        } else if(exp.val is hand_t){
            return gen_exp(ctxt, buff, dest,
                exp_t, exp.val as hand_t, defer_id);
        };
    case let ternary: *ternary_meta =>
        // gen condition
        const cond = fmt::asprintf("%cond.{}", ternary.pos)!;
        defer free(cond);
        gen_exp(ctxt, buff, cond, quick_t(primitive::BOOL),
            ternary.condition, defer_id);
        // evaluate
        fmt::fprintfln(buff,
            "\tjnz {0}, @true.val.{1}, @false.val.{1}\n@true.val.{1}",
            cond, ternary.pos)!;
        const pos_val_tmp = fmt::asprintf("%positive.{}", ternary.pos)!;
        defer free(pos_val_tmp);
        const pos_val_lit = gen_exp(ctxt, buff, pos_val_tmp,
            ternary.tpe, ternary.positive, defer_id);
        defer if(pos_val_lit != "") free(pos_val_lit);

        const pos_val = if(pos_val_lit != "") pos_val_lit else pos_val_tmp;
        gen_cast(ctxt, buff, pos_val, ternary.tpe, dest, exp_t);
        fmt::fprintfln(buff, "\tjmp @end.{0}\n@false.val.{0}", ternary.pos)!;

        const neg_val_tmp = fmt::asprintf("%negative.{}", ternary.pos)!;
        defer free(neg_val_tmp);
        const neg_val_lit = gen_exp(ctxt, buff, neg_val_tmp,
            ternary.tpe, ternary.negative, defer_id);
        defer if(neg_val_lit != "") free(neg_val_lit);

        const neg_val = if(neg_val_lit != "") neg_val_lit else neg_val_tmp;
        gen_cast(ctxt, buff, neg_val, ternary.tpe, dest, exp_t);
        fmt::fprintfln(buff, "\tjmp @end.{0}\n@end.{0}", ternary.pos)!;
    };
    return "";
};

// emits an arithmetic expression given a hand meta
fn gen_arithmetic(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    exp_t: lichen_t,
    hand: *hand_meta,
    defer_id: (void | size),
) void = {
    if(hand.opr > operator::LAND){
        const asg_t = qbe_t(ctxt, exp_t, mode::ASSIGN);
        const lft_h = fmt::asprintf("%l.{}", hand.pos)!;
        const lft_t = extract_hand_type(hand.lft);
        const short_l = gen_exp(ctxt, buff, lft_h, lft_t, hand.lft, defer_id);
        if(short_l != ""){
            free(lft_h);
            lft_h = short_l;
        };
        defer free(lft_h);
        
        const rgt_h = fmt::asprintf("%r.{}", hand.pos)!;
        const rgt_t = extract_hand_type(hand.rgt);
        const short_r = gen_exp(ctxt, buff, rgt_h, rgt_t, hand.rgt, defer_id);
        if(short_r != ""){
            free(rgt_h);
            rgt_h = short_r;
        };
        defer free(rgt_h);
        let needs_free = false;
        const (inst, needs_free) =
            fetch_instruct(ctxt, hand.opr, lft_t, exp_t);
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
            move_ptr(ctxt, ctxt.tokens[hand.pos]);
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
        const short_l = gen_exp(ctxt, buff, lft_h, lft_t, hand.lft, defer_id);
        if(short_l != ""){
            free(lft_h);
            lft_h = short_l;
        };
        defer free(lft_h);
        fmt::fprintfln(buff, "\tjnz {0}, @mid.{1}, @false.{1}\n@mid.{1}", lft_h, hand.pos)!;

        const rgt_h = fmt::asprintf("%r.{}", hand.pos)!;
        const rgt_t = extract_hand_type(hand.rgt);
        const short_r = gen_exp(ctxt, buff, rgt_h, rgt_t, hand.rgt, defer_id);
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
        const short_l = gen_exp(ctxt, buff, lft_h, lft_t, hand.lft,defer_id);
        if(short_l != ""){
            free(lft_h);
            lft_h = short_l;
        };
        defer free(lft_h);
        fmt::fprintfln(buff,
            "\tjnz {0}, @true.{1}, @mid.{1}\n@mid.{1}", lft_h, hand.pos)!;
        const rgt_h = fmt::asprintf("%r.{}", hand.pos)!;
        const rgt_t = extract_hand_type(hand.rgt);
        const short_r = gen_exp(ctxt, buff, rgt_h, rgt_t, hand.rgt, defer_id);
        if(short_r != ""){
            free(rgt_h);
            rgt_h = short_r;
        };
        defer free(rgt_h);
        fmt::fprintfln(buff,
            "\tjnz {0}, @true.{1}, @false.{1}", rgt_h, hand.pos)!;
        fmt::fprintfln(buff,
            "@true.{1}\n\t{0} =l copy 1\n\tjmp @end.{1}\n"
            "@false.{1}\n\t{0} =l copy 0\n\tjmp @end.{1}\n@end.{1}",
            dest, hand.pos)!;
    };
};

fn fetch_instruct(
    ctxt: *context,
    opr: operator,
    tpe: lichen_t,
    exp_t: lichen_t,
) (str, bool) = {
    switch(opr){
    case operator::EQL =>
        return (fmt::asprintf("ceq{}",
            qbe_t(ctxt, tpe, mode::ASSIGN))!, true);
    case operator::NEQ =>
        return (fmt::asprintf("cne{}",
            qbe_t(ctxt, tpe, mode::ASSIGN))!, true);
    case operator::LEQ =>
        const i = if(is_subtype(tpe, primitive::U64)){
            yield fmt::asprintf("cule{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        } else if(is_subtype(tpe, primitive::I64)){
            yield fmt::asprintf("csle{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        } else {
            yield fmt::asprintf("cle{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        };
        return (i, true);
    case operator::GEQ =>
        const i = if(is_subtype(tpe, primitive::U64)){
            yield fmt::asprintf("cuge{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        } else if(is_subtype(tpe, primitive::I64)){
            yield fmt::asprintf("csge{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        } else {
            yield fmt::asprintf("cge{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        };
        return (i, true);
    case operator::LST =>
        const i = if(is_subtype(tpe, primitive::U64)){
            yield fmt::asprintf("cult{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        } else if(is_subtype(tpe, primitive::I64)){
            yield fmt::asprintf("cslt{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        } else {
            yield fmt::asprintf("clt{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        };
        return (i, true);
    case operator::GTT =>
        const i = if(is_subtype(tpe, primitive::U64)){
            yield fmt::asprintf("cugt{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        } else if(is_subtype(tpe, primitive::I64)){
            yield fmt::asprintf("csgt{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        } else {
            yield fmt::asprintf("cgt{}", qbe_t(ctxt, tpe, mode::ASSIGN))!;
        };
        return (i, true);
    case operator::BAND => return ("and", false);
    case operator::BOR => return ("or", false);
    case operator::PLS => return ("add", false);
    case operator::MIN => return ("sub", false);
    case operator::MUL => return ("mul", false);
    case operator::DIV =>
        // address for signed types or ratios
        return if(is_subtype(exp_t, primitive::U64)){
            yield ("udiv", false);
        } else {
            yield ("div", false);
        };
    case operator::MOD =>
        // address for signed types or ratios
        return if(is_subtype(exp_t, primitive::U64)){
            yield ("urem", false);
        } else {
            yield ("rem", false);
        };
    case operator::SHL => return ("shl", false);
    case operator::SHR =>
        // address for signed types or ratios
        return if(is_subtype(exp_t, primitive::U64)){
            yield ("shr", false);
        } else {
            yield ("sar", false);
        };
    case =>
        fmt::fatalf("gen_arithmetic: unreachable operator {}",
            oper_value[opr]);
    };
};

// assigns a given member to a `dest` temporary
// if a final result is generated, returns the value or temporary name, if not
// returns an empty string
fn assign_memb(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    exp_t: lichen_t,
    memb: *member_meta,
    defer_id: (void | size),
) str = {
    move_ptr(ctxt, ctxt.tokens[memb.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
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
            gen_arr_lit(ctxt, buff, dest, exp_t, arr_lit, defer_id);
            yield (strings::dup(dest)!, arr_lit.tpe, true);
        case let access: *indexing_meta =>
            yield unwrap_fields_and_indexes(ctxt, buff, access, defer_id);
        case let access: *slicing_meta =>
            yield unwrap_fields_and_indexes(ctxt, buff, access, defer_id);
        case let rec_lit: *record_lit_meta =>
            const as_rec = rec_lit.tpe.base as *record;
            fmt::fprintfln(buff, "\t{} =l alloc8 {}", dest, type_size(exp_t))!;
            if(exp_t.partial){
                fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
                fmt::fprintfln(buff, "\t{0} =l add {0}, 8", dest)!;
            };
            for(let f = 0z; f < len(as_rec.fields); f += 1){
                const val = rec_lit.values[f];
                const rec_field = as_rec.fields[val.1];
                const offst = field_offset(rec_lit.tpe.base as *record, val.0);
                if(offst > 0){
                    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, {1}", dest, offst)!;
                } else {
                    fmt::fprintfln(buff, "\t{0}.ptr =l copy {0}", dest)!;
                };
                const field = fmt::asprintf("%field.{}", val.2.pos)!;
                defer free(field);
                const res = gen_exp(ctxt, buff, field,
                    val.2.tpe, val.2, defer_id);
                const asg_val =
                    if(res != ""){
                        yield res;
                    } else {
                        yield field;
                    };
                defer if(res != "") free(res);
                const field_src = fmt::asprintf("{}.src", field)!;
                defer free(field_src);
                const type_l = type_size(rec_field.1.var.nm.tpe);
                if(!comp_type(rec_field.1.var.nm.tpe, val.2.tpe)){
                    gen_cast(ctxt, buff, asg_val, val.2.tpe,
                        field_src, rec_field.1.var.nm.tpe);
                } else {
                    fmt::fprintfln(buff, "\t{} ={} copy {}", field_src,
                        qbe_t(ctxt, rec_field.1.var.nm.tpe, mode::ASSIGN),
                        asg_val)!;
                };
                if(type_l <= 8){
                    fmt::fprintfln(buff, "\tstore{} {}, {}.ptr",
                        qbe_t(ctxt, rec_field.1.var.nm.tpe),
                        field_src, dest)!;
                } else {
                    fmt::fprintfln(buff, "\tblit {}, {}.ptr, {}",
                        field_src, dest, type_l)!;
                };
            };
            if(exp_t.partial){
                fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", dest)!;
            };
            yield ("", rec_lit.tpe, true);
        case let access: *field_meta =>
            yield unwrap_fields_and_indexes(ctxt, buff, access, defer_id);
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
            yield(gen_funcall(ctxt, buff, call, nm, defer_id),
                call.fun.fun.tpe, nm == dest);
        case let all: *alloc_meta =>
            gen_alloc(ctxt, buff, dest, all, defer_id);
            yield (dest, all.tpe, true);
        case let cat: *concat_meta =>
            gen_concat(ctxt, buff, dest, cat, defer_id);
            yield (dest, cat.tpe, true);
        case let kwd: keyword =>
            yield switch(kwd){
            case keyword::TRUE =>
                return strings::dup("1")!;
            case keyword::FALSE =>
                return strings::dup("0")!;
            case keyword::NIL =>
                fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                    memb.pos, type_size(exp_t))!;
                fmt::fprintfln(buff, "\tstorel 0, %opt.{}", memb.pos)!;
                return fmt::asprintf("%opt.{}", memb.pos)!;
            case keyword::ERROR =>
                fmt::fprintfln(buff, "\t%opt.{} =l alloc8 {}",
                    memb.pos, type_size(memb.tpe))!;
                fmt::fprintfln(buff, "\tstorel -1, %opt.{}", memb.pos)!;
                return fmt::asprintf("%opt.{}", memb.pos)!;
            case =>
                fmt::fatal("assign_memb: unreachable");
            };
        case let ptr: *fn_ptr_meta =>
            return strings::dup(fix_nm(ctxt, buff, ptr.points_to.fun))!;
        };
    // member has propagation
    if(memb.prop is propagation){
        gen_prop(ctxt, buff, memb.prop as propagation,
            exp_t, tpe, memb.pos, dest, val, defer_id);
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

fn gen_alloc(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    all: *alloc_meta,
    defer_id: (void | size),
) void = {
    move_ptr(ctxt, ctxt.tokens[all.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
    // generate defer-independent label
    const lbl_append =
        if(defer_id is size) fmt::asprintf(".{}", defer_id as size)! else "";
    defer if(lbl_append != "") free(lbl_append);
    const lbl = fmt::asprintf("{}{}", all.pos, lbl_append)!;
    defer free(lbl);
    // fetch arena qbe temporary's name
    const arena = fix_nm(ctxt, buff, all.arena.nm);
    // load arena size
    fmt::fprintfln(buff, "\t{0}.length =l loadl {0}", arena)!;
    // load arena pointer
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", arena)!;
    fmt::fprintfln(buff, "\t{0}.at =l loadl {0}.ptr", arena)!;
    // load arena memory base pointer
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 16", arena)!;
    fmt::fprintfln(buff, "\t{0}.base =l loadl {0}.ptr", arena)!;
    // load current memory position
    fmt::fprintfln(buff, "\t{0}.pos =l add {0}.base, {0}.at", arena)!;

    // allocation data temporary
    const data = fmt::asprintf("%arena.src.{}", all.pos)!;
    defer free(data);

    // size known at compile time
    if(size_known(all.tpe)){
        // emit source data
        const val = assign_memb(ctxt, buff, data,
            all.tpe, all.val, defer_id);
        if(val != ""){
            defer free(val);
            fmt::fprintfln(buff, "\t{} =l copy {}", data, val)!;
        };
        fmt::fprintfln(buff, "\t{0}.after =l add {0}.at, {1}",
            arena, type_size(all.tpe))!;
    // dynamically sized array or string
    } else {
        // emit string or non-literal array
        if(is_subtype(all.tpe, quick_t(primitive::STR, true)) ||
            (all.tpe.base is *array && !(all.val.val is *array_lit_meta))){
            const val = assign_memb(ctxt, buff, data,
                all.tpe, all.val, defer_id);
            if(val != ""){
                defer free(val);
                fmt::fprintfln(buff, "\t{} =l copy {}", data, val)!;
            };
            fmt::fprintfln(buff, "\t{}.length =l loadl {}", dest, data)!;
            fmt::fprintfln(buff,
                "\t%data.length.{} =l add {}.length, 16", lbl, dest)!;
        } else {
            const length = fmt::asprintf("{}.length", dest)!;
            defer free(length);
            const tmp = fmt::asprintf("{}.length.exp", data)!;
            defer free(tmp);
            const lit = all.val.val as *array_lit_meta;
            const exp = lit.length as *expr_meta;
            const val = gen_exp(ctxt, buff, tmp, exp.tpe, exp, defer_id);
            // assert for length type
            if(!comp_type(exp.tpe, primitive::U64)){
                if(val != ""){
                    defer free(val);
                    gen_cast(ctxt, buff, val, exp.tpe,
                        length, quick_t(primitive::U64));
                } else {
                    gen_cast(ctxt, buff, tmp, exp.tpe,
                        length, quick_t(primitive::U64));
                };
            } else if(val != ""){
                defer free(val);
                fmt::fprintfln(buff, "\t{} =l copy {}", length, val)!;
            } else {
                fmt::fprintfln(buff, "\t{} =l copy {}", length, tmp)!;
            };
            // assert for minimum length
            const min =
                if(lit.spreads_at is void) len(lit.items)
                else len(lit.items) - 1;
            fmt::fprintfln(buff,
                "\t%data.length.ok =l culel {}, {}.length",
                    min, dest)!;
            // assertion jump
            if(all.prop is void ||
                (all.prop as short_prop).0 == operator::BUBBLE){
                if(all.prop is short_prop){
                    const prop = all.prop as short_prop;
                    fmt::fprintfln(buff,
                        "\tblit $str.{}, $rt.errmsg, 16", prop.1)!;
                };
                fmt::fprintfln(buff,
                    "\tjnz %data.length.ok, @length.ok.{0}, "
                    "@arena.fail.{0}\n@length.ok.{0}",
                    lbl)!;
            } else {
                const prop = all.prop as short_prop;
                fmt::fprintfln(buff,
                    "\tblit $str.{}, $rt.errmsg, 16", prop.1)!;
                fmt::fprintfln(buff,
                    "\tjnz %data.length.ok, @length.ok.{}, "
                    "@fail\n@length.ok.{0}", lbl)!;
            };
            // calculate total length in bytes
            const sz = type_size((all.tpe.base as *array).base);
            if(sz > 1){
                fmt::fprintfln(buff,
                    "\t%data.length.{} =l mul {}.length, {}", lbl,
                    dest, sz)!;
                fmt::fprintfln(buff,
                    "\t%data.length.{0} =l add %data.length.{0}, 16",
                    lbl)!;
            } else {
                fmt::fprintfln(buff,
                    "\t%data.length.{} =l add {}.length, 16",
                    lbl, dest)!;
            };
        };
        fmt::fprintfln(buff,
            "\t{0}.after =l add {0}.at, %data.length.{1}",
            arena, lbl)!;
    };
    // assert for total available arena's size
    fmt::fprintfln(buff,
        "\t%arena.enough =l culel {0}.after, {0}.length", arena)!;
    if(all.prop is void || (all.prop as short_prop).0 == operator::BUBBLE){ 
        if(all.prop is short_prop){
            const prop = all.prop as short_prop;
            fmt::fprintfln(buff, "\tblit $str.{}, $rt.errmsg, 16", prop.1)!;
        };
        fmt::fprintfln(buff,
            "\tjnz %arena.enough, @arena.alloc.{0}, @arena.fail.{0}",
            lbl)!;
    } else {
        const prop = all.prop as short_prop;
        fmt::fprintfln(buff, "\tblit $str.{}, $rt.errmsg, 16", prop.1)!;
        fmt::fprintfln(buff,
            "\tjnz %arena.enough, @arena.alloc.{}, @fail", lbl)!;
    };
    fmt::fprintfln(buff, "@arena.alloc.{}", lbl)!;
    fmt::fprintfln(buff, "\t{} =l copy {}.pos", dest, arena)!;
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", arena)!;
    fmt::fprintfln(buff, "\tstorel {0}.after, {0}.ptr", arena)!;
    // offset if partial
    if(all.prop is void && !size_known(all.tpe)){
        fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
        fmt::fprintfln(buff, "\t{0} =l add {0}, 8", dest)!;
    };
    // emit dynamic array literal
    if(!size_known(all.tpe) && all.tpe.base is *array){
        fmt::fprintfln(buff, "\tstorel {0}.length, {0}", dest)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
        fmt::fprintfln(buff, "\t{0}.data =l add {0}, 16", dest)!;
        fmt::fprintfln(buff, "\tstorel {0}.data, {0}.ptr", dest)!;
        if(all.val.val is *array_lit_meta){
            const at = fmt::asprintf("{}.data", dest)!;
            defer free(at);
            gen_arr_lit(ctxt, buff, dest, all.tpe,
                all.val.val as *array_lit_meta, defer_id, at);
        } else {
            fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", data)!;
            fmt::fprintfln(buff, "\t{0}.ptr =l loadl {0}.ptr", data)!;
            const itm_tpe = unwrap_array(all.tpe);
            const itm_tpe_sz = type_size(itm_tpe);
            if(itm_tpe_sz == 1){
                fmt::fprintfln(buff,
                    "\tcall $rt.copy(l {0}.data, l {1}.ptr, l {0}.length)",
                    dest, data)!;
            } else if(itm_tpe_sz <= 8){
                fmt::fprintfln(buff,
                    "\tcall $rt.copy{}(l {1}.data, l {2}.ptr, l {1}.length)",
                    qbe_t(ctxt, itm_tpe), dest, data)!;
            };
        };
    // emit string literal
    } else if(!size_known(all.tpe)){
        fmt::fprintfln(buff, "\tstorel {0}.length, {0}", dest)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
        fmt::fprintfln(buff, "\t{0}.data =l add {0}, 16", dest)!;
        fmt::fprintfln(buff, "\tstorel {0}.data, {0}.ptr", dest)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", data)!;
        fmt::fprintfln(buff, "\t{0}.ptr =l loadl {0}.ptr", data)!;
        fmt::fprintfln(buff,
            "\tcall $rt.copy(l {0}.data, l {1}.ptr, l {0}.length)",
            dest, data)!;
    // emit record literal
    } else {
        fmt::fprintfln(buff, "\tblit {}, {}, {}",
            data, dest, type_size(all.tpe, true))!;
    };
    // undo offset
    if(all.prop is void && !size_known(all.tpe)){
        fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", dest)!;
    };
    // allocation failure assertion
    if(all.prop is void ||
        (all.prop as short_prop).0 == operator::BUBBLE){
        fmt::fprintfln(buff, "\tjmp @arena.end.{}", lbl)!;
        fmt::fprintfln(buff, "@arena.fail.{}", lbl)!;
        if(all.prop is void){
            fmt::fprintfln(buff, "\t{} =l alloc8 {}",
                dest, type_size(all.tpe))!;
            fmt::fprintfln(buff, "\tstorel 0, {}", dest)!;
        } else {
            fmt::fprintfln(buff, "\t{} =l alloc8 {}",
                dest, type_size(all.host))!;
            fmt::fprintfln(buff, "\tstorel 0, {}", dest)!;
            fmt::fprintfln(buff, "\tret {}", dest)!;
        };
        fmt::fprintfln(buff, "@arena.end.{}", lbl)!;
    };
};

fn gen_concat(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    cat: *concat_meta,
    defer_id: (void | size),
) void = {
    move_ptr(ctxt, ctxt.tokens[cat.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
    // generate defer-independent label
    const lbl_append =
        if(defer_id is size) fmt::asprintf(".{}", defer_id as size)! else "";
    defer if(lbl_append != "") free(lbl_append);
    const lbl = fmt::asprintf("{}{}", cat.pos, lbl_append)!;
    defer free(lbl);
    // unwrapped type
    const unwrap = cat.tpe;
    unwrap.partial = false;
    // item size
    const itm_tpe = unwrap_array(cat.tpe);
    const itm_tpe_sz = type_size(itm_tpe);
    // lefthand
    const left = fetch_iterator(ctxt, buff, cat.pos, cat.left, unwrap, defer_id);
    defer free(left);
    // load lefthand size
    fmt::fprintfln(buff, "\t%cat.{}.left.length =l loadl {}", lbl, left)!;
    // righthand
    const right =
        if(cat.right is iterator_t){
            const right = fetch_iterator(ctxt, buff, cat.pos,
                cat.right as iterator_t, unwrap, defer_id);
            // calculate total size
            fmt::fprintfln(buff, "\t%cat.{}.right.length =l loadl {}",
                lbl, right)!;
            fmt::fprintfln(buff,
                "\t%cat.{0}.length =l add %cat.{0}.left.length, "
                "%cat.{0}.right.length", lbl)!;
            yield right;
        } else {
            const memb = cat.right as *member_meta;
            const item = fmt::asprintf("%cat.righthand")!;
            const val = assign_memb(ctxt, buff, item,
                memb.tpe, memb, defer_id);
            // calculate total size
            fmt::fprintfln(buff,
                "\t%cat.{0}.length =l add %cat.{0}.left.length, 1",
                cat.pos)!;
            yield if(val != ""){
                free(item);
                yield val;
            } else {
                yield item;
            };
        };
    defer free(right);

    // save array length
    fmt::fprintfln(buff,
        "\t%cat.{0}.arr.length =l copy %cat.{0}.length", lbl)!;
    // calculate total memory size
    if(itm_tpe_sz > 1){
        fmt::fprintfln(buff,
            "\t%cat.{0}.length =l mul %cat.{0}.length, {1}",
            lbl, itm_tpe_sz)!;
    };
    fmt::fprintfln(buff, "\t%data.length.{0} =l add %cat.{0}.length, 16",
        lbl)!;

    // fetch arena qbe temporary's name
    const arena = fix_nm(ctxt, buff, cat.arena.nm);
    // load arena size
    fmt::fprintfln(buff, "\t{0}.length =l loadl {0}", arena)!;
    // load arena pointer
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", arena)!;
    fmt::fprintfln(buff, "\t{0}.at =l loadl {0}.ptr", arena)!;
    // load arena memory base pointer
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 16", arena)!;
    fmt::fprintfln(buff, "\t{0}.base =l loadl {0}.ptr", arena)!;
    // load current memory position
    fmt::fprintfln(buff, "\t{0}.pos =l add {0}.base, {0}.at", arena)!;

    fmt::fprintfln(buff, "\t{0}.after =l add {0}.at, %data.length.{1}",
        arena, lbl)!;

    // TODO: optimize for in-place reallocation

    // assert for total available arena's size
    fmt::fprintfln(buff,
        "\t%arena.enough =l culel {0}.after, {0}.length", arena)!;
    if(cat.prop is void || (cat.prop as short_prop).0 == operator::BUBBLE){
        if(cat.prop is short_prop){
            const prop = cat.prop as short_prop;
            fmt::fprintfln(buff, "\tblit $str.{}, $rt.errmsg, 16", prop.1)!;
        };
        fmt::fprintfln(buff,
            "\tjnz %arena.enough, @arena.alloc.{0}, @arena.fail.{0}",
            lbl)!;
    } else {
        const prop = cat.prop as short_prop;
        fmt::fprintfln(buff, "\tblit $str.{}, $rt.errmsg, 16", prop.1)!;
        fmt::fprintfln(buff,
            "\tjnz %arena.enough, @arena.alloc.{}, @fail", lbl)!;
    };
    fmt::fprintfln(buff, "@arena.alloc.{}", lbl)!;
    fmt::fprintfln(buff, "\t{} =l copy {}.pos", dest, arena)!;
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", arena)!;
    fmt::fprintfln(buff, "\tstorel {0}.after, {0}.ptr", arena)!;
    // offset if partial
    if(cat.prop is void){
        fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
        fmt::fprintfln(buff, "\t{0} =l add {0}, 8", dest)!;
    };
    // generate final concatenation
    fmt::fprintfln(buff, "\tstorel %cat.{}.arr.length, {}", lbl, dest)!;
    // point to destination data segment
    if(cat.are_slices){
        fmt::fprintfln(buff, "\t{0}.data =l add {0}, 16", dest)!;
    } else {
        fmt::fprintfln(buff, "\t{0}.data =l add {0}, 8", dest)!;
    };
    // load lefthand data
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", left)!;
    if(cat.are_slices){
        fmt::fprintfln(buff, "\t{0}.ptr =l loadl {0}.ptr", left)!;
    };
    // copy data as a byte array
    if(itm_tpe_sz == 1){
        fmt::fprintfln(buff,
            "\tcall $rt.copy(l {}.data, l {}.ptr, l %cat.{}.left.length)",
            dest, left, lbl)!;
    // copy data as a primitive types array
    } else if(itm_tpe_sz <= 8){
        fmt::fprintfln(buff,
            "\tcall $rt.copy{}(l {}.data, l {}.ptr, l %cat.{}.left.length)",
            qbe_t(ctxt, itm_tpe), dest, left, lbl)!;
    // copy data as an aggregated types array
    } else {
        fmt::fprintfln(buff,
            "\t%cat.{0}.left.total =l mul %cat.{0}.left.length, {1}",
            lbl, itm_tpe_sz)!;
        fmt::fprintfln(buff,
            "\tcall $rt.copy{}(l {}.data, l {}.ptr, l %cat.{}.left.total)",
            qbe_t(ctxt, itm_tpe), dest, left, cat.pos)!;
    };
    // move to the righthand segment
    if(itm_tpe_sz > 1){
        fmt::fprintfln(buff,
            "\t{0}.data.offset =l mul %cat.{1}.left.length, {2}",
            dest, cat.pos, itm_tpe_sz)!;
        fmt::fprintfln(buff, "\t{0}.data.ptr =l add {0}.data, {0}.data.offset",
            dest)!;
    } else {
        fmt::fprintfln(buff,
            "\t{0}.data.ptr =l add {0}.data, %cat.{1}.left.length",
            dest, cat.pos)!;
    };
    if(cat.right is iterator_t){
        // load righthand data
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", right)!;
        if(cat.are_slices){
            fmt::fprintfln(buff, "\t{0}.ptr =l loadl {0}.ptr", right)!;
        };
        // copy data as a primitive types array
        if(itm_tpe_sz == 1){
            fmt::fprintfln(buff,
                "\tcall $rt.copy(l {}.data.ptr, l {}.ptr, "
                "l %cat.{}.right.length)",
                dest, right, lbl)!;
        // copy data as a primitive types array
        } else if(itm_tpe_sz <= 8){
            fmt::fprintfln(buff,
                "\tcall $rt.copy{}(l {}.data.ptr, l {}.ptr, "
                "l %cat.{}.right.length)",
                qbe_t(ctxt, itm_tpe), dest, right, lbl)!;
        // copy data as an aggregated types array
        } else {
            fmt::fprintfln(buff,
                "\t%cat.{0}.right.total =l mul %cat.{0}.right.length, {1}",
                lbl, itm_tpe_sz)!;
            fmt::fprintfln(buff,
                "\tcall $rt.copy{}(l {}.data.ptr, l {}.ptr, "
                "l %cat.{}.right.total)",
                qbe_t(ctxt, itm_tpe), dest, right, lbl)!;
        };
    } else if(itm_tpe_sz <= 8){
        const memb = cat.right as *member_meta;
        fmt::fprintfln(buff, "\tstore{} {}, {}.data.ptr",
            qbe_t(ctxt, memb.tpe), right, dest)!;
    } else {
        const memb = cat.right as *member_meta;
        fmt::fprintfln(buff, "\tblit {}, {}.data.ptr, {}",
            right, dest, itm_tpe_sz)!;
    };
    // store data pointer
    if(cat.are_slices){
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
        fmt::fprintfln(buff, "\tstorel {0}.data, {0}.ptr", dest)!;
    };
    // undo offset
    if(cat.prop is void){
        fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", dest)!;
    };
    // allocation failure assertion
    if(cat.prop is void ||
        (cat.prop as short_prop).0 == operator::BUBBLE){
        fmt::fprintfln(buff, "\tjmp @arena.end.{}", lbl)!;
        fmt::fprintfln(buff, "@arena.fail.{}", lbl)!;
        if(cat.prop is void){
            fmt::fprintfln(buff, "\t{} =l alloc8 {}",
                dest, type_size(cat.tpe))!;
            fmt::fprintfln(buff, "\tstorel 0, {}", dest)!;
        } else {
            fmt::fprintfln(buff, "\t{} =l alloc8 {}",
                dest, type_size(cat.host))!;
            fmt::fprintfln(buff, "\tstorel 0, {}", dest)!;
            fmt::fprintfln(buff, "\tret {}", dest)!;
        };
        fmt::fprintfln(buff, "@arena.end.{}", lbl)!;
    };
};

// emits the IR for an array literal
fn gen_arr_lit(
    ctxt: *context,
    buff: *memio::stream,
    dest: str,
    exp_t: lichen_t,
    arr_lit: *array_lit_meta,
    defer_id: (void | size),
    allocate_at: (void | str) = void,
) void = {
    move_ptr(ctxt, ctxt.tokens[arr_lit.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
    // generate defer-independent label
    const lbl_append =
        if(defer_id is size) fmt::asprintf(".{}", defer_id as size)! else "";
    defer if(lbl_append != "") free(lbl_append);
    const lbl = fmt::asprintf("{}{}", arr_lit.pos, lbl_append)!;
    defer free(lbl);

    const as_arr = arr_lit.tpe.base as *array;
    if(as_arr.length is size && (arr_lit.tpe.partial || exp_t.partial)){
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", 
            dest, type_size(as_arr.base))!;
        fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
        fmt::fprintfln(buff, "\t{0}.arr.ptr =l add {0}, 8", dest)!;
        fmt::fprintfln(buff, "\tstorel {}, {}.arr.ptr",
            as_arr.length as size, dest)!;
        if(as_arr.length as size > 0){
            fmt::fprintfln(buff, "\t{0}.arr.ptr =l add {0}, 8", dest)!;
        };
    } else if(as_arr.length is size){
        fmt::fprintfln(buff, "\t{} =l alloc8 {}",
            dest, type_size(arr_lit.tpe))!;
        fmt::fprintfln(buff, "\t{0}.arr.ptr =l copy {0}", dest)!;
        fmt::fprintfln(buff, "\tstorel {}, {}.arr.ptr",
            as_arr.length as size, dest)!;
        if(as_arr.length as size > 0){
            fmt::fprintfln(buff, "\t{0}.arr.ptr =l add {0}, 8", dest)!;
        };
    } else {
        fmt::fprintfln(buff, "\t{}.arr.ptr =l copy {}", dest, allocate_at as str)!;
    };
    const spread =
        match(arr_lit.spreads_at){
        case let e: size => yield e;
        case void => yield len(arr_lit.items);
        };
    let last_val = "";
    let last_set = false;
    const itm_tpe_sz = type_size(as_arr.base);
    for(let i = 0z; i < len(arr_lit.items); i += 1){
        const wrap = fmt::asprintf("{}.itm.{}", dest, i)!;
        defer free(wrap);
        // emit known items
        if(i < spread){
            const val = gen_exp(ctxt, buff, wrap, as_arr.base,
                arr_lit.items[i], defer_id);
            const asg_val =
                if(val != ""){
                    last_set = false;
                    yield val;
                } else {
                    last_set = true;
                    yield wrap;
                };
            defer if(val != "") free(val);
            if(itm_tpe_sz <= 8){
                fmt::fprintfln(buff, "\tstore{} {}, {}.arr.ptr",
                    qbe_t(ctxt, as_arr.base), asg_val, dest)!;
            } else {
                fmt::fprintfln(buff, "\tblit {}, {}.arr.ptr, {}",
                    asg_val, dest, itm_tpe_sz)!;
            };
            fmt::fprintfln(buff, "\t{0}.arr.ptr =l add {0}.arr.ptr, {1}",
                dest, type_size(as_arr.base))!;
        // fill within known size
        } else if(as_arr.length is size){
            const length = as_arr.length as size;
            fmt::fprintfln(buff, "\t%times.left.{} =l copy {}",
                lbl, length - i)!;
            fmt::fprintfln(buff,
                "@assign.static.{0}\n\tjnz %times.left.{0}, "
                "@arr.next.{0}, @arr.end.{0}\n@arr.next.{0}", lbl)!;
            const spread = gen_exp(ctxt, buff, wrap,
                as_arr.base, arr_lit.items[i], defer_id);
            const asg_val = if(spread != "") spread else wrap;
            if(itm_tpe_sz <= 8){
                fmt::fprintfln(buff, "\tstore{} {}, {}.arr.ptr",
                    qbe_t(ctxt, as_arr.base), asg_val, dest)!;
            } else {
                fmt::fprintfln(buff, "\tblit {}, {}.arr.ptr, {}",
                    asg_val, dest, itm_tpe_sz)!;
            };
            fmt::fprintfln(buff,
                "\t%times.left.{0} =l sub %times.left.{0}, 1", lbl)!;
            fmt::fprintfln(buff, "\t{0}.arr.ptr =l add {0}.arr.ptr, {1}",
                dest, type_size(as_arr.base))!;
            fmt::fprintfln(buff,
                "\tjmp @assign.static.{0}\n@arr.end.{0}", lbl)!;
        // loop til end of array
        } else {
            if(i == 0){
                fmt::fprintfln(buff, "\t%times.left.{} =l copy {}.length",
                    lbl, dest)!;
            } else {
                fmt::fprintfln(buff, "\t%times.left.{} =l sub {}.length, {}",
                    lbl, dest, len(arr_lit.items) - 1)!;
            };
            const spread = gen_exp(ctxt, buff, wrap,
                as_arr.base, arr_lit.items[i], defer_id);
            fmt::fprintfln(buff,
                "@assign.dynamic.{0}\n\tjnz %times.left.{0}, "
                "@arr.next.{0}, @arr.end.{0}\n@arr.next.{0}", lbl)!;
            const asg_val = if(spread != "") spread else wrap;
            if(itm_tpe_sz <= 8){
                fmt::fprintfln(buff, "\tstore{} {}, {}.arr.ptr",
                    qbe_t(ctxt, as_arr.base), asg_val, dest)!;
            } else {
                fmt::fprintfln(buff, "\tblit {}, {}.arr.ptr, {}",
                    asg_val, dest, itm_tpe_sz)!;
            };
            fmt::fprintfln(buff,
                "\t%times.left.{0} =l sub %times.left.{0}, 1", lbl)!;
            fmt::fprintfln(buff, "\t{0}.arr.ptr =l add {0}.arr.ptr, {1}",
                dest, type_size(as_arr.base))!;
            fmt::fprintfln(buff,
                "\tjmp @assign.dynamic.{0}\n@arr.end.{0}", lbl)!;
        };
    };
    if(last_val != "") free(last_val);
};

// unwraps the IR for a chain of field accesses and array indexing
fn unwrap_fields_and_indexes(
    ctxt: *context,
    buff: *memio::stream, 
    access: chain_exp_t,
    defer_id: (void | size),
) (str, lichen_t, bool) = {
    const load_stack: []chain_exp_t = [];
    let next: (void | ...chain_exp_t) = access;
    let root: chain_exp_t = access;
    for(next is chain_exp_t){
        const valid = next as chain_exp_t;
        root = valid;
        append(load_stack, valid)!;
        match(valid){
        case let idx: *indexing_meta =>
            next = idx.before;
        case let slc: *slicing_meta =>
            next = slc.before;
        case let fld: *field_meta =>
            next = fld.before;
        };
    };
    const base =
        match(root){
        case let idx: *indexing_meta =>
            yield idx.base as *member_meta;
        case let slc: *slicing_meta =>
            yield slc.base as *member_meta;
        case let fld: *field_meta =>
            yield fld.base as *member_meta;
        };
    let last =
        if(root is *field_meta){
            yield fmt::asprintf("%rec.{}",
                (root as *field_meta).pos)!;
        } else if(root is *indexing_meta){
            yield fmt::asprintf("%arr.{}",
                (root as *indexing_meta).pos)!;
        } else {
            yield fmt::asprintf("%slc.{}",
                (root as *slicing_meta).pos)!;
        };
    assign_memb(ctxt, buff, last, base.tpe, base, defer_id);

    let last_t = base.tpe;
    for(let f = len(load_stack); f > 0; f -= 1){
        const this = load_stack[f - 1];
        if(this is *field_meta){
            const lastest = last;
            last = gen_field(ctxt, buff, last, last_t,
                f, this as *field_meta, defer_id);
            last_t = (this as *field_meta).tpe;
            free(lastest);
        } else if(this is *indexing_meta){
            const lastest = last;
            last = gen_index(ctxt, buff, last, last_t,
                f, this as *indexing_meta,defer_id);
            free(lastest);
            last_t = (this as *indexing_meta).tpe;
        } else {
            const lastest = last;
            last = gen_slice(ctxt, buff, last, last_t,
                f, this as *slicing_meta, defer_id);
            free(lastest);
            last_t = (this as *slicing_meta).tpe;
        };
    };
    return (last, last_t, false);
};

// emits the IR for a field access
fn gen_field(
    ctxt: *context,
    buff: *memio::stream,
    base: str,
    base_t: lichen_t,
    idx: size,
    this: *field_meta,
    defer_id: (void | size),
    return_ptr: bool = false,
) str = {
    move_ptr(ctxt, ctxt.tokens[this.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
    // generate defer-independent label
    const lbl_append =
        if(defer_id is size) fmt::asprintf(".{}", defer_id as size)! else "";
    defer if(lbl_append != "") free(lbl_append);
    const lbl = fmt::asprintf("{}{}", this.pos, lbl_append)!;
    defer free(lbl);

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
    // we do not care about the current value, only the address of it
    if(return_ptr){
        // field has propagation
        if(this.prop is propagation){
            const prop = this.prop as propagation;
            const wrap = fmt::asprintf("{}.wrap", val)!;
            const unwrap_t = this.tpe;
            unwrap_t.partial = false;
            gen_prop(ctxt, buff, prop, this.tpe,
                unwrap_t, this.pos, wrap, val, defer_id);
            return wrap;
        };
        return strings::dup(val)!;
    };
    // read value
    const type_l = type_size(this.field.var.nm.tpe);
    if(type_l <= 8){
        fmt::fprintfln(buff, "\t{} ={} load{} {}", field,
            qbe_t(ctxt, this.tpe, mode::ASSIGN),
            qbe_t(ctxt, this.field.var.nm.tpe, mode::LOAD), val)!;
    } else {
        fmt::fprintfln(buff, "\t{} =l copy {}", field, val)!;
        // field has propagation
        if(this.prop is propagation){
            const prop = this.prop as propagation;
            const wrap = fmt::asprintf("{}.wrap", field)!;
            const unwrap_t = this.tpe;
            unwrap_t.partial = false;
            gen_prop(ctxt, buff, prop, this.tpe,
                unwrap_t, this.pos, wrap, field, defer_id);

            if(prop.1 is path_meta){
                fmt::fprintfln(buff, "@skip.{}", lbl)!;
            };
            return wrap;
        };
    };
    return field;
};

// emits the IR for an array indexing
fn gen_index(
    ctxt: *context,
    buff: *memio::stream,
    base: str,
    base_t: lichen_t,
    idx: size,
    this: *indexing_meta,
    defer_id: (void | size),
    return_ptr: bool = false,
) str = {
    move_ptr(ctxt, ctxt.tokens[this.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
    // generate defer-independent label
    const lbl_append =
        if(defer_id is size) fmt::asprintf(".{}", defer_id as size)! else "";
    defer if(lbl_append != "") free(lbl_append);
    const lbl = fmt::asprintf("{}{}", this.pos, lbl_append)!;
    defer free(lbl);

    const arr = base_t.base as *array;
    // load actual array data
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", base)!;
    // load fat pointer data if needed
    if(arr.length is void){
        fmt::fprintfln(buff, "\t{0}.ptr =l loadl {0}.ptr", base)!;
    };
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
                quick_t(primitive::U64), exp, defer_id);
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
    const item = fmt::asprintf("{}.item", base)!;
    const unwrap_sz = type_size(this.tpe);
    if(!zero){
        if(unwrap_sz > 1){
            fmt::fprintfln(buff, "\t{}.offset =l mul {}, {}",
                base, index, unwrap_sz)!;
            fmt::fprintfln(buff,
                "\t{0}.ptr =l add {0}.ptr, {0}.offset", base)!;
        } else {
            fmt::fprintfln(buff,
                "\t{0}.ptr =l add {0}.ptr, {1}", base, index)!;
        };
    };
    if(!safe){
        const item_t = unwrap_array(this.from_tpe);
        item_t.partial = true;

        fmt::fprintfln(buff, "\t{0}.len =l loadl {0}", base)!;
        fmt::fprintfln(buff, "\t%idex.safe =l cultl {}, {}.len", index, base)!;
        fmt::fprintfln(buff,
            "\tjnz %idex.safe, @some.item.{0}{1}, @no.item.{0}{1}\n@no.item.{0}{1}",
            this.pos + idx, lbl_append)!;
        const host = ctxt.host_fun as *fun_meta;
        fmt::fprintfln(buff, "\t{} =l alloc8 {}",
            item, type_size(host.fun.tpe))!;
        fmt::fprintfln(buff, "\tstorel 0, {}", item)!;
        // for reading item
        if(!return_ptr){
            fmt::fprintfln(buff,
                "\tjmp @index.end.{0}{1}\n@some.item.{0}{1}",
                this.pos + idx, lbl_append)!;
            fmt::fprintfln(buff, "\t{} =l alloc8 {}",
                item, type_size(item_t))!;
        // for writing to item
        } else {
            const prop = this.prop as propagation;
            if(prop.0 == operator::BUBBLE){
                fmt::fprintfln(buff, "\tret {}\n@some.item.{0}{1}",
                    item, this.pos + idx, lbl_append)!;
            } else {
                fmt::fprintfln(buff, "\tjmp @fail\n@some.item.{0}{1}",
                    this.pos + idx, lbl_append)!;
            };
            return fmt::asprintf("{}.ptr", base)!;
        };
        if(unwrap_sz <= 8){
            fmt::fprintfln(buff, "\tstorel 1, {}", item)!;
            fmt::fprintfln(buff, "\t{0} =l add {0}, 8", item)!;
            const data_t = qbe_t(ctxt, this.tpe);
            fmt::fprintfln(buff, "\t{}.data ={} load{} {}.ptr",
                item, qbe_t(ctxt, this.tpe, mode::ASSIGN),
                qbe_t(ctxt, this.tpe, mode::LOAD), base)!;
            fmt::fprintfln(buff, "\tstore{0} {1}.data, {1}", data_t, item)!;
            fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", item)!;
        } else {
            fmt::fprintfln(buff, "\tstorel 1, {}", item)!;
            fmt::fprintfln(buff, "\t{0} =l add {0}, 8", item)!;
            fmt::fprintfln(buff, "\tblit {}.ptr, {}, {}", base, item, unwrap_sz)!;
            fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", item)!;
        };
        fmt::fprintfln(buff, "@index.end.{}{}", this.pos + idx, lbl_append)!;

        if(this.prop is propagation){
            const prop = this.prop as propagation;
            const wrap = fmt::asprintf("{}.unwrap", item)!;
            defer free(item);
            gen_prop(ctxt, buff, prop, this.tpe,
                item_t, this.pos, wrap, item, defer_id);
            if(prop.1 is path_meta){
                fmt::fprintfln(buff, "@skip.{}", lbl)!;
            };
            return wrap;
        };
    } else if(return_ptr){
        return fmt::asprintf("{}.ptr", base)!;
    } else {
        fmt::fprintfln(buff, "\t{} ={} load{} {}.ptr",
            item, qbe_t(ctxt, this.tpe, mode::ASSIGN),
            qbe_t(ctxt, this.tpe, mode::LOAD), base)!;
    };
    return item;
};

fn gen_slice(
    ctxt: *context,
    buff: *memio::stream,
    base: str,
    base_t: lichen_t,
    idx: size,
    this: *slicing_meta,
    defer_id: (void | size),
) str = {
    move_ptr(ctxt, ctxt.tokens[this.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
    // generate defer-independent label
    const lbl_append =
        if(defer_id is size) fmt::asprintf(".{}", defer_id as size)! else "";
    defer if(lbl_append != "") free(lbl_append);
    const lbl = fmt::asprintf("{}{}", this.pos, lbl_append)!;
    defer free(lbl);

    const as_arr = base_t.base as *array;
    const slice = fmt::asprintf("{}.slice", base)!;

    if(!this.safe){
        fmt::fprintfln(buff, "\t{0}.length =l loadl {0}", base)!;
        fmt::fprintfln(buff, "\t{} =l alloc8 24", slice)!;
        fmt::fprintfln(buff, "\tstorel 1, {}", slice)!;
        fmt::fprintfln(buff, "\t{0} =l add {0}, 8", slice)!;
    } else {
        fmt::fprintfln(buff, "\t{} =l alloc8 16", slice)!;
    };

    const length = fmt::asprintf("{}.length", slice)!;
    defer free(length);

    const begin_idx = fmt::asprintf("{}.beginidx", slice)!;
    defer free(begin_idx);
    const begin_val = match(this.begin){
        case let exp: *expr_meta =>
            yield gen_exp(ctxt, buff, begin_idx, exp.tpe, exp, defer_id);
        case let lit: *const_meta =>
            yield fmt::asprint(lit.val as size)!;
        };
    defer if(begin_val != "") free(begin_val);
    if(begin_val != ""){
        fmt::fprintfln(buff, "\t{} =l copy {}",
            begin_idx, begin_val)!;
    };
    if(!this.safe){
        fmt::fprintfln(buff, "\t%begin.ok.{} =l cultl {}, {}.length",
            lbl, begin_idx, base)!;
        fmt::fprintfln(buff,
            "\tjnz %begin.ok.{0}, @begin.ok.{0}, @slice.fail.{0}\n@begin.ok.{0}",
            lbl)!;
    };
    const end_idx = fmt::asprintf("{}.endidx", slice)!;
    defer free(end_idx);
    const end_val = match(this.end){
        case let exp: *expr_meta =>
            yield gen_exp(ctxt, buff, end_idx, exp.tpe, exp, defer_id);
        case let lit: *const_meta =>
            yield fmt::asprint(lit.val as size)!;
        };
    if(!this.safe){
        if(end_val != ""){
            fmt::fprintfln(buff, "\t%end.ok.{} =l culel {}, {}.length",
                lbl, end_val, base)!;
        } else {
            fmt::fprintfln(buff, "\t%end.ok.{} =l culel {}, {}.length",
                lbl, end_idx, base)!;
        };
        fmt::fprintfln(buff,
            "\tjnz %end.ok.{0}, @end.ok.{0}, @slice.fail.{0}\n@end.ok.{0}",
            lbl)!;
    };
    if(end_val != ""){
        defer free(end_val);
        fmt::fprintfln(buff, "\t{} =l sub {}, {}",
            length, end_val, begin_idx)!;
    } else {
        fmt::fprintfln(buff, "\t{} =l sub {}, {}",
            length, end_idx, begin_idx)!;
    };
    fmt::fprintfln(buff, "\tstorel {}, {}", length, slice)!;
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", base)!;
    if(as_arr.length is void){
        fmt::fprintfln(buff, "\t{0}.ptr =l loadl {0}.ptr", base)!;
    };
    if(begin_val != "0"){
        fmt::fprintfln(buff, "\t{0}.ptr =l add {0}.ptr, {1}", base, begin_idx)!;
    };
    fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", slice)!;
    fmt::fprintfln(buff, "\tstorel {}.ptr, {}.ptr", base, slice)!;
    if(!this.safe){
        fmt::fprintfln(buff, "\t{0} =l sub {0}, 8\n\tjmp @slice.finish.{1}",
            slice, lbl)!;
        fmt::fprintfln(buff,
            "@slice.fail.{0}\n\tstorel -1, {1}\n"
            "\tjmp @slice.finish.{0}""\n@slice.finish.{0}",
            lbl, slice)!;
        if(this.prop is propagation){
            const prop = this.prop as propagation;
            const wrap = fmt::asprintf("{}.unwrap", slice)!;
            defer free(slice);
            const slice_t = this.tpe;
            slice_t.partial = true;

            gen_prop(ctxt, buff, prop, this.tpe,
                slice_t, this.pos, wrap, slice, defer_id);
            if(prop.1 is path_meta){
                fmt::fprintfln(buff, "@skip.{}", lbl)!;
            };
            return wrap;
        };
    };
    return slice;
};

// emits the IR for a propagation expression
fn gen_prop(
    ctxt: *context,
    buff: *memio::stream,
    prop: propagation,
    exp_t: lichen_t,
    tpe: lichen_t,
    pos: size,
    dest: str,
    val: str,
    defer_id: (void | size),
) void = {
    move_ptr(ctxt, ctxt.tokens[pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;
    // generate defer-independent label
    const lbl_append =
        if(defer_id is size) fmt::asprintf(".{}", defer_id as size)! else "";
    defer if(lbl_append != "") free(lbl_append);
    const lbl = fmt::asprintf("{}{}", pos, lbl_append)!;
    defer free(lbl);

    fmt::fprintfln(buff, "\t%fail.code =l loadl {}", val)!;
    fmt::fprintfln(buff, "\tblit $str.{}, $rt.errmsg, 16", prop.2)!;
    fmt::fprintln(buff, "\t%assert.fail =l csltl %fail.code, 1")!;
    // no assertion expression
    if(prop.1 is void){
        if(prop.0 == operator::BUBBLE){
            fmt::fprintfln(buff, "\tjnz %assert.fail, @bubble.{0}, @ok.{0}",
                lbl)!;
            if(len(ctxt.free_on_ret) > 0){
                for(let f .. ctxt.free_on_ret){
                    fmt::fprintln(buff, f)!;
                };
            };
            fmt::fprintfln(buff, "@bubble.{0}\n\tret {1}\n@ok.{0}", lbl, val)!;
        } else {
            fmt::fprintfln(buff, "\tjnz %assert.fail, @fail, @ok.{0}\n@ok.{0}",
                lbl)!;
        };
        if(!comp_type(exp_t, primitive::UNIT) &&
            !comp_type(exp_t, primitive::VOID)){
            const tpe_sz = type_size(exp_t);
            if(tpe_sz <= 8){
                fmt::fprintfln(buff,
                    "\t{1}.ok =l add {1}, 8\n\t{0} ={2} load{3} {1}.ok",
                    dest, val, qbe_t(ctxt, exp_t, mode::ASSIGN),
                    qbe_t(ctxt, exp_t, mode::LOAD))!;
            } else {
                fmt::fprintfln(buff, "\t{} =l add {}, 8", dest, val)!;
            };
        };
    } else {
        if(prop.0 == operator::BUBBLE){
            const exp = prop.1 as *expr_meta;
            fmt::fprintfln(buff,
                "\tjnz %assert.fail, @bubble.{0}, @ok.{0}\n@bubble.{0}", lbl)!;
            const wrap = fmt::asprintf("%default.{}", lbl)!;
            defer free(wrap);
            const unwrap_t = tpe;
            unwrap_t.partial = false;
            const def_val = gen_exp(ctxt, buff, wrap, unwrap_t, exp, defer_id);
            const asg_val =
                if(def_val != ""){
                    yield def_val;
                } else {
                    yield wrap;
                };
            defer if(def_val != "") free(def_val);
            fmt::fprintfln(buff,
                "\t{1} ={2} copy {3}\n\tjmp @skip.{0}\n@ok.{0}",
                lbl, dest, qbe_t(ctxt, exp_t, mode::ASSIGN), asg_val)!;
            const tpe_sz = type_size(exp_t, true);
            if(tpe_sz <= 8){
                fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", val)!;
                fmt::fprintfln(buff,
                    "\t{} ={} load{} {}.ptr",
                    dest, qbe_t(ctxt, exp_t, mode::ASSIGN),
                    qbe_t(ctxt, exp_t, mode::LOAD), val)!;
            } else {
                fmt::fprintfln(buff,
                    "\t{} =l add {}, 8", dest, val)!;
            };
        } else {
            const stt = prop.1 as path_meta;
            fmt::fprintfln(buff,
                "\tjnz %assert.fail, @fail.{0}, @ok.{0}\n@fail.{0}", lbl)!;
            const zero = zeroed_value(ctxt, buff, exp_t);
            defer free(zero);
            fmt::fprintfln(buff, "\t{} ={} copy {}", dest,
                qbe_t(ctxt, exp_t, mode::ASSIGN), zero)!;
            gen_stt(ctxt, buff, stt, defer_id);
            // check if a jump is necessary
            const (_, last_tpe, _) = fetch_ret_state(ctxt, tpe, false, stt);
            if(!is_terminal(last_tpe)){
                fmt::fprintfln(buff, "\tjmp @skip.{0}", lbl)!;
            };
            fmt::fprintfln(buff, "@ok.{0}", lbl)!;
        };
    };
};

// emits a funcall
fn gen_funcall(
    ctxt: *context,
    buff: *memio::stream,
    call: *funcall_meta,
    dest: str,
    defer_id: (void | size),
) str = {
    move_ptr(ctxt, ctxt.tokens[call.pos]);
    const (l, c) = get_pos(ctxt);
    fmt::fprintfln(buff, "\tdbgloc {}, {}", l, c)!;

    const base_name = strings::replace(call.fun.fun.name, "'", ".q")!;
    defer free(base_name);
    const name =
        if(call.fun.fun.ffi is str){
            const ffi = call.fun.fun.ffi as str;
            yield if(strings::hasprefix(ffi, "$") ||
                strings::hasprefix(ffi, "%")){
                yield strings::dup(ffi)!;
            } else {
                yield fmt::asprintf("${}", ffi)!;
            };
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
    for(let exp .. call.args){
        const wrap = fmt::asprintf("%exp.{}", exp.pos)!;
        const memb = gen_exp(ctxt, buff, wrap, exp.tpe, exp, defer_id);
        const name =
            if(memb != ""){
                free(wrap);
                yield memb;
            } else {
                yield wrap;
            };
        const root = extract_root(exp);
        const arg =
            // assert for slices
            if(root is *array_lit_meta){
                const lit = root as *array_lit_meta;
                yield if(!comp_type(lit.tpe, exp.tpe)){
                    defer free(name);
                    const cast = fmt::asprintf("{}.cast", name)!;
                    gen_cast(ctxt, buff, name, lit.tpe,
                        cast, exp.tpe);
                    yield cast;
                } else {
                    yield name;
                };
            } else {
                yield name;
            };
        const temp = var_meta {
            nm = namespace {
                name = arg,
                tpe = exp.tpe,
                ffi = void,
                owner = ctxt,
                ...
            },
            pos = exp.pos,
            lifetime = void,
            allocated = false,
        };
        append(defs, alloc(temp)!)!;
    };
    const keep_result = dest != "" &&
        !comp_type(call.fun.fun.tpe, quick_t(primitive::UNIT)) &&
        !is_terminal(call.fun.fun.tpe);

    const old_dest = dest;
    if(keep_result && is_aggregated(call.fun.fun.tpe) ||
        call.fun.fun.tpe.partial){
        dest = fmt::asprintf("{}.tmp", old_dest)!;
        fmt::fprintfln(buff, "\t{} =l alloc8 {}",
            old_dest, type_size(call.fun.fun.tpe))!;
    };
    if(keep_result){
        if(call.fun.fun.tpe.partial &&
            call.fun.fun.tpe.base is *record){
            fmt::fprintf(buff, "\t{} ={}.opt call {}", dest,
                qbe_t(ctxt, call.fun.fun.tpe, mode::RETURN), name)!;
        } else {
            fmt::fprintf(buff, "\t{} ={} call {}", dest,
                qbe_t(ctxt, call.fun.fun.tpe, mode::RETURN), name)!;
        };
    } else if(!call.tailcall){
        fmt::fprintf(buff, "\tcall {}", name)!;
    };
    if(!call.tailcall || keep_result){
        gen_list(ctxt, buff, defs, call.fun.fun.ffi is str);
        fmt::fprint(buff, "\n")!;
        if(old_dest != dest && keep_result){
            defer free(dest);
            fmt::fprintfln(buff, "\tblit {}, {}, {}", dest,
                old_dest, type_size(call.fun.fun.tpe))!;
            return strings::dup(old_dest)!;
        } else {
            return strings::dup(dest)!;
        };
    } else {
        for(let a = 0z; a < len(call.fun.params); a += 1){
            const arg = call.fun.params[a];
            const val = defs[a];
            const argname = fix_nm(ctxt, buff, arg.var.nm);
            defer free(argname);
            fmt::fprintfln(buff, "\t{} ={} copy {}", argname,
                qbe_t(ctxt, arg.var.nm.tpe, mode::ASSIGN), val.nm.name)!;
        };
        fmt::fprintln(buff, "\tjmp @recursive\n@unreachable")!;
        return strings::dup(dest)!;
    };
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
    if(src_t.base is primitive && !src_t.partial &&
        dest_t.base is primitive && !dest_t.partial){
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
            } else if(!is_ratio(src_t) && is_ratio(dest_t)){
                fmt::fprintfln(buff, "\t{} ={} {} {}",
                    dest, dest_qbe_t, itof(src_t, dest_t), src)!;
            // cast of float to integer
            } else if(is_ratio(src_t) && !is_ratio(dest_t)){
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
    // array
    } else if(src_t.base is *array && !src_t.partial &&
        dest_t.base is *array && !dest_t.partial){
        const src_arr = src_t.base as *array;
        const dest_arr = dest_t.base as *array;
        if((src_arr.length is size && dest_arr.length is size) ||
            (src_arr.length is void && dest_arr.length is void)){
            fmt::fprintfln(buff, "\t{} =l copy {}", dest, src)!;
        // slicing
        } else {
            assert(src_arr.length is size);
            fmt::fprintfln(buff, "\t{} =l alloc8 {}", dest, type_size(dest_t))!;
            if(dest_t.partial){
                fmt::fprintfln(buff, "\t{0} =l add {0}, 8", dest)!;
            };
            fmt::fprintfln(buff, "\t{0}.length =l loadl {0}", src)!;
            fmt::fprintfln(buff, "\tstorel {}.length, {}", src, dest)!;
            fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", dest)!;
            fmt::fprintfln(buff, "\t{0}.ptr =l add {0}, 8", src)!;
            fmt::fprintfln(buff, "\tstorel {}.ptr, {}.ptr", src, dest)!;
            if(dest_t.partial){
                fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", dest)!;
            };
        };
    // unwrap
    } else if(src_t.partial && !dest_t.partial){
        // offset loading point to actual data
        fmt::fprintfln(buff, "\t{0} =l add {0}, 8", src)!;
        // deal with data type casting
        const unwrap_t = src_t;
        unwrap_t.partial = false;
        const temp = fmt::asprintf("{}.wrap", dest)!;
        defer free(temp);
        if(!comp_type(unwrap_t, dest_t) && size_mismatch(unwrap_t, dest_t)){
            if(dest_t.base is primitive){
                fmt::fprintfln(buff, "\t{} ={} load{} {}", temp,
                    qbe_t(ctxt, dest_t, mode::ASSIGN),
                    qbe_t(ctxt, dest_t, mode::LOAD), src)!;
            } else {
                fmt::fprintfln(buff, "\t{} =l copy {}", temp, src)!;
            };
            // cast loaded value to desired type
            gen_cast(ctxt, buff, temp, unwrap_t, dest, dest_t);
        } else if(dest_t.base is primitive){
            fmt::fprintfln(buff, "\t{} ={} load{} {}", dest,
                qbe_t(ctxt, dest_t, mode::ASSIGN),
                qbe_t(ctxt, dest_t, mode::LOAD), src)!;
        } else {
            fmt::fprintfln(buff, "\t{} =l copy {}", dest, src)!;
        };
    // concrete to partial
    } else if(!src_t.partial && dest_t.partial){
        const src_sz = type_size(src_t);
        const dest_sz = type_size(dest_t);
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", dest, dest_sz)!;
        fmt::fprintfln(buff, "\tstorel 1, {}", dest)!;
        fmt::fprintfln(buff, "\t{0} =l add {0}, 8", dest)!;
        if(src_sz <= 8){
            fmt::fprintfln(buff, "\tstore{} {}, {}", qbe_t(ctxt, src_t),
                src, dest)!;
        } else {
            fmt::fprintfln(buff, "\tblit {}, {}, {}", src, dest, src_sz)!;
        };
        fmt::fprintfln(buff, "\t{0} =l sub {0}, 8", dest)!;
    // both error types;
    } else {
        fmt::fprintfln(buff, "\t{} =l copy {}", dest, src)!;
    };
};

// converts a given namespace to its correct temporary name
// if given namespace if global, emits the IR for loading the data
fn fix_nm(ctxt: *context, buff: *memio::stream, nm: namespace) str = {
    const base = strings::replace(nm.name, "'", ".q")!;
    defer free(base);
    const name =
        if((!ctxt.main || nm.owner.file != ctxt.file) && nm.glob){
            const mod = strings::rcut(
            strings::rcut(nm.owner.file, "/").1, ".").0;
            yield fmt::asprintf("{}.{}", mod, base)!;
        } else {
            yield strings::dup(base)!;
        };
    defer free(name);
    if(nm.kind == nm_kind::TYPE) return fmt::asprintf(":{}", name)!;
    if(nm.ffi is str){
        if(nm.kind != nm_kind::FUNC){
            fmt::fprintfln(buff, "\t%{} ={} load{} ${}", name,
                qbe_t(ctxt, nm.tpe, mode::ASSIGN),
                qbe_t(ctxt, nm.tpe, mode::LOAD), nm.ffi)!;
        } else {
            return nm.ffi as str;
        };
    } else if(nm.glob){
        if(nm.kind != nm_kind::FUNC){
            fmt::fprintfln(buff, "\t%{0} ={1} load{2} ${0}", name,
                qbe_t(ctxt, nm.tpe, mode::ASSIGN),
                qbe_t(ctxt, nm.tpe, mode::LOAD), name)!;
        } else {
            return fmt::asprintf("${}", name)!;
        };
    };
    return fmt::asprintf("%{}", name)!;
};

// returns the emitted code for a constant value
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
        case keyword::FALSE =>
            return strings::dup("0")!;
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

// returns the zeroed value equivalent to a given type
// if needed, aditional IR is emitted to generate the zeroed value
fn zeroed_value(ctxt: *context, buff: *memio::stream, tpe: lichen_t) str = {
    if(tpe.base is primitive){
        if(is_aggregated(tpe)){
            const name = fmt::asprintf("%.zero")!;
            fmt::fprintfln(buff, "\t{} =l alloc8 24", name)!;
            fmt::fprintfln(buff, "\tblit $rt.zero, {}, 24", name)!;
            return name;
        } else {
            return strings::dup("0")!;
        };
    } else if(tpe.base is *array){
        const name = fmt::asprintf("%.zero")!;
        fmt::fprintfln(buff, "\t{} =l alloc8 24", name)!;
        fmt::fprintfln(buff, "\tblit $rt.zero, {}, 24", name)!;
        return name;
    } else if(tpe.base is *enum_t){
        const e = tpe.base as *enum_t;
        return fix_nm(ctxt, buff, e.variant[0]);
    } else {
        const rec = tpe.base as *record;
        const tpe_sz = type_size(tpe);
        const name = fmt::asprintf("%{}.zero", rec.name.name)!;
        fmt::fprintfln(buff, "\t{} =l alloc8 {}", name, tpe_sz)!;
        fmt::fprintfln(buff, "\tblit ${}.zero, {}, {}",
            strings::sub(rec.export_name, 1), name, tpe_sz)!;
        return name;
    };
};
