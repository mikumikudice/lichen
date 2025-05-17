// the io module implements functions to writing
// to and reading from file handlers.

// runtime wrappers for the std handles
pub stdin  u32 = $rt_stdin;
pub stdout u32 = $rt_stdout;
pub stderr u32 = $rt_stderr;

// runtime wrappers for io functions
fn rt_gets(handle u32, buff str) i32 = rt$rt_gets;
fn rt_puts(handle u32, data str) i32 = rt$rt_puts;

// prints `data` to the stdout
pub fn print(data str) unit = rt {
    fprint(stdout, data);
};

// prints `data` followed by a new line to the stdout
pub fn println(data str) unit = rt {
    if #data {
        print(data);
    };
    print("\n"); // TODO: make it a single call with string concatenation
};

// prints `data` to the stderr
pub fn error(data str) unit = rt {
    fprint(stderr, data);
};

// prints `data` followed by a new line to the stderr
pub fn errorln(data str) unit = rt {
    error(data);
    error("\n"); // TODO: make it a single call with string concatenation
};

// prints `data` to the given handle
pub fn fprint(handle u32, data str) unit = rt {
    if #data {
        rt_puts(handle, data);
    };
};

// [to be deprecated]
// reads the stdin up to the capacity of the given
// buffer and writes the read data to it
pub fn scan(buff str) unit = rt {
    fscan(stdin, buff);
};

// [to be deprecated]
// reads the given `handle` up to the capacity of the
// given buffer and writes the read data to it
pub fn fscan(handle u32, buff str) unit = rt {
    rt_gets(handle, buff);
};

