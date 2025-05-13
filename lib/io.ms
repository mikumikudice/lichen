pub stdin u32 = $rt_stdin;
pub stdout u32 = $rt_stdout;

fn rt_gets(handle u32, buff str) i32 = rt$rt_gets;
fn rt_puts(handle u32, data str) i32 = rt$rt_puts;

pub fn scan(buff str) unit = rt {
    fscan(stdin, buff);
};

pub fn print(data str) unit = rt {
    rt_puts(stdout, data);
};

pub fn println(data str) unit = rt {
    print(data);
    print("\n"); // TODO: make it a single call with string concatenation
};

pub fn fscan(handle u32, buff str) unit = rt {
    rt_gets(handle, buff);
};

pub fn fprint(handle u32, data str) unit = rt {
    rt_puts(handle, data);
};
