use io;
use fmt;

fn free_context(ctxt: *context, main: bool = false) void = {
    free(ctxt.src);
    free(ctxt.tokens);
    for(let meta .. ctxt.global.defs){
        if(meta is *module_meta){
            const mod = meta as *module_meta;
            if(!mod.freed){
                free_context(mod.ctxt);
                mod.freed = true;
            };
            free(mod);
        } else {
            free_nodes(meta);
        };
    };
    free(ctxt.global.defs);
    free(ctxt.global);
    if(main){
        free(ctxt.literals);
        free_names();
    };
    free(ctxt);
};

fn free_nodes(this: path_meta) void = {
    match(this){
    case let meta: *const_meta =>
        free(meta);
    case let meta: *array_lit_meta =>
        const max =
            match(meta.spreads_at){
            case let e: size => yield e + 1;
            case void => yield len(meta.items);
            };
        for(let i = 0z; i < max; i += 1){
            free_nodes(meta.items[i]);
        };
        free(meta.items);
        free(meta);
    case let meta: *indexing_meta =>
        if(meta.before is *field_meta)
            free_nodes(meta.before as *field_meta);

        if(meta.base is *member_meta)
            free_nodes(meta.base as *member_meta);

        free_nodes(meta.index);
        free(meta);
    case let meta: *record_lit_meta =>
        for(let val .. meta.values){
            free_nodes(val.1);
        };
        free(meta.values);
        free(meta);
    case let meta: *field_meta =>
        if(meta.before is *field_meta)
            free_nodes(meta.before as *field_meta);

        if(meta.base is *member_meta)
            free_nodes(meta.base as *member_meta);
        free(meta);
    case let meta: *decl_meta =>
        if(!(meta.val is void))
            free_nodes(meta.val as (*const_meta | ...hand_t));
        free_nodes(meta.var);
        free(meta);
    case let meta: *var_meta =>
        free(meta);
    case let meta: *fun_meta =>
        for(let param .. meta.params){
            free_nodes(param);
        };
        free(meta.params);
        free(meta.effect);
        if(meta.body is *scope_meta)
            free_nodes(meta.body as *scope_meta);
        free(meta);
    case let meta: *funcall_meta =>
        for(let arg .. meta.args){
            free_nodes(arg);
        };
        free(meta);
    case let meta: *scope_meta =>
        for(let defn .. meta.self.defs){
            free_nodes(defn);
        };
        free(meta.self.defs);
        free(meta.stt);
        free(meta.self);
        free(meta);
    case let meta: *expr_meta =>
        if(meta.val is hand_t)
            free_nodes(meta.val as hand_t);
        free(meta);
    case let meta: *hand_meta =>
        free_nodes(meta.lft);
        free_nodes(meta.rgt);
        free(meta);
    case let meta: *member_meta =>
        if(!(meta.val is keyword))
            free_nodes(meta.val as member_t);
        if(meta.prop is propagation){
            const prop = meta.prop as propagation;
            if(prop.1 is path_meta)
                free_nodes(prop.1 as path_meta);
        };
        free(meta);
    case let meta: *branch_meta =>
        for(let cond .. meta.conds){
            free_nodes(cond);
        };
        free(meta.conds);
        for(let body .. meta.bodies){
            if(body.0 is *decl_meta)
                free_nodes(body.0 as *decl_meta);
            free_nodes(body.1);
        };
        free(meta.bodies);
        free(meta);
    case let meta: *ternary_meta =>
        free_nodes(meta.positive);
        free_nodes(meta.negative);
        free_nodes(meta.condition);
        free(meta);
    case let meta: *return_meta =>
        free_nodes(meta.val);
        free(meta);
    case let meta: *type_meta =>
        if(meta.self.base is *record){
            const rec = meta.self.base as *record;
            free(rec.export_name);
        };
        free(meta);
    case let meta: *module_meta => assert(false);
    };
};
