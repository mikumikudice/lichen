pub stdin u32 = $rt_stdin;
pub stdout u32 = $rt_stdout;

fn rt_gets(handle u32, size u64) str = rt$rt_gets;
fn rt_puts(handle u32, data str) u32 = rt$rt_puts;

pub fn scan(size u64) str = rt {
    => rt_gets(stdin, size);
};

pub fn print(data str) unit = rt {
    rt_puts(stdout, data);
}; 

pub fn fprint(handle u32, data str) unit = rt {
    rt_puts(handle, data);
};
