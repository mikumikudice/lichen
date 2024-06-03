const io_read =
    func { // read = fn(handle : u32, size : str) : @str
        fname = "read",
        param = [ kwd::U32_TYPE, kwd::STRING_T ],
        retrn = kwd::U32_TYPE,
        ret_n = "",
        origin = kernel::IO,
        public = true,
        impure = true,
        effect = [ "IO" ],
        ...
    };
const io_write =
    func { // write = fn(handle : u32, data : str) : u32
        fname = "write",
        param = [ kwd::U32_TYPE, kwd::STRING_T ],
        retrn = kwd::U32_TYPE,
        ret_n = "",
        origin = kernel::IO,
        public = true,
        impure = true,
        effect = [ "IO" ],
        ...
    };
const io_stdin =
    nmsp {
        ident = "stdin",
        vtype = kwd::U32_TYPE,
        mutbl = false,
        asgnd = true,
        origin = kernel::IO,
        global = true,
        value = 0: u64: num,
        public = true,
        ...
    };
const io_stdout =
    nmsp {
        ident = "stdout",
        vtype = kwd::U32_TYPE,
        mutbl = false,
        asgnd = true,
        origin = kernel::IO,
        global = true,
        value = 1: u64: num,
        public = true,
        ...
    };
const io_stderr =
    nmsp {
        ident = "stderr",
        vtype = kwd::U32_TYPE,
        mutbl = false,
        asgnd = true,
        origin = kernel::IO,
        global = true,
        value = 2: u64: num,
        public = true,
        ...
    };
const io_funs = [ &io_read, &io_write ];
const io_vars = [ &io_stdin, &io_stdout, &io_stderr ];

const mem_alloc =
    func { // alloc = fn(size: u32) : raw
        fname = "alloc",
        param = [ kwd::U64_TYPE ],
        retrn = kwd::RAW_TYPE,
        ret_n = "",
        origin = kernel::MEM,
        public = true,
        impure = true,
        effect = [ "MEM" ],
        ...
    };
const mem_free =
    func { // free = fn(obj : raw) : unit
        fname = "free",
        param = [ kwd::RAW_TYPE ],
        retrn = kwd::UNITTYPE,
        ret_n = "",
        origin = kernel::MEM,
        public = true,
        impure = true,
        effect = [ "MEM" ],
        ...
    };
const mem_copy =
    func { // copy = fn(dest : raw, src : raw, size : u64) : raw
        fname = "copy",
        param = [ kwd::RAW_TYPE, kwd::RAW_TYPE, kwd::U64_TYPE ],
        retrn = kwd::RAW_TYPE,
        ret_n = "",
        origin = kernel::MEM,
        public = true,
        impure = false,
        effect = [ "MEM" ],
        ...
    };
const mem_strlset =
    func { // strlset = fnfn(dest : str, size : u64) : unit
        fname = "strlset",
        param = [ kwd::STRING_T, kwd::U64_TYPE ],
        retrn = kwd::UNITTYPE,
        ret_n = "",
        origin = kernel::MEM,
        public = true,
        impure = false,
        effect = [ "MEM" ],
        ...
    };
const mem_strcpy =
    func { // strcpy = fn(dest : str, src : sre, size : u64) : unit
        fname = "strcpy",
        param = [ kwd::STRING_T, kwd::STRING_T, kwd::U64_TYPE ],
        retrn = kwd::UNITTYPE,
        ret_n = "",
        origin = kernel::MEM,
        public = true,
        impure = false,
        effect = [ "MEM" ],
        ...
    };
const mem_strrev =
    func { // strrev = fn(src : str) : str
        fname = "strrev",
        param = [ kwd::STRING_T ],
        retrn = kwd::STRING_T,
        ret_n = "",
        origin = kernel::MEM,
        public = true,
        impure = false,
        effect = [ "MEM" ],
        ...
    };
const mem_memset =
    func { // memset = fn(dest : raw, src : u8, size : u64) : unit
        fname = "memset",
        param = [ kwd::RAW_TYPE, kwd::U8__TYPE, kwd::U64_TYPE ],
        retrn = kwd::UNITTYPE,
        ret_n = "",
        origin = kernel::MEM,
        public = true,
        impure = false,
        effect = [ "MEM" ],
        ...
    };
const mem_funs =
    [ &mem_alloc  , &mem_free  , &mem_copy
    , &mem_memset
    , &mem_strlset, &mem_strcpy, &mem_strrev
    ];
const mem_defs = []: []*nmsp;
