use io;
use fmt;

fn free_context(ctxt: *context, main: bool = false) void = {
    for(let meta .. ctxt.global.defs){
        if(meta is *module_meta){
            const mod = meta as *module_meta;
            if(!mod.freed){
                free_context(mod.ctxt);
                mod.freed = true;
            };
        };
    };
    free(ctxt.global.defs);
    free(ctxt.global);
    if(main){
        free(ctxt.literals);
        free_nodes();
        free_names();
        free(ctxt.src);
        free(ctxt.tokens);
        for(let mod .. compiled_modules){
            free(mod);
        };
        free(compiled_modules);
    };
    free(ctxt);
};

let allocd_nodes: []path_meta = [];

fn free_nodes() void = {
    for(let this .. allocd_nodes){
        match(this){
        case let meta: *const_meta =>
            free(meta);
        case let meta: *array_lit_meta =>
            free(meta.items);
            free(meta);
        case let meta: *indexing_meta =>
            free(meta);
        case let meta: *slicing_meta =>
            free(meta);
        case let meta: *record_lit_meta =>
            free(meta.values);
            free(meta);
        case let meta: *field_meta =>
            free(meta);
        case let meta: *decl_meta =>
            free(meta);
        case let meta: *assign_meta =>
            free(meta);
        case let meta: *arena_meta =>
            free(meta);
        case let meta: *alloc_meta =>
            free(meta);
        case let meta: *var_meta =>
            free(meta);
        case let meta: *fun_meta =>
            free(meta.params);
            //free(meta.effect);
            free(meta.shares_efx);
            free(meta);
        case let meta: *fn_ptr_meta =>
            free(meta);
        case let meta: *funcall_meta =>
            free(meta.args);
            free(meta);
        case let meta: *scope_meta =>
            free(meta.stt);
            free(meta.defer_stack);
            free(meta);
        case let meta: *expr_meta =>
            free(meta);
        case let meta: *hand_meta =>
            free(meta);
        case let meta: *member_meta =>
            free(meta);
        case let meta: *branch_meta =>
            free(meta.conds);
            free(meta.bodies);
            free(meta);
        case let meta: *ternary_meta =>
            free(meta);
        case let meta: *return_meta =>
            free(meta);
        case let meta: *test_meta =>
            io::close(meta.buffer)!;
            free(meta.buffer);
            free(meta);
        case let meta: *for_meta =>
            free(meta);
        case let meta: *while_meta =>
            free(meta);
        case let meta: *switch_meta =>
            free(meta);
        case let meta: *type_meta =>
            if(meta.self.base is *record){
                const rec = meta.self.base as *record;
                free(rec.export_name);
            };
            free(meta);
        case let meta: *defer_meta =>
            free(meta);
        case => assert(false);
        };
    };
    free(allocd_nodes);
};
