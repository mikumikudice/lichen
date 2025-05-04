mem = use "mem.ms";

pub stdin u32 = $rt_stdin;
pub stdout u32 = $rt_stdout;

fn rt_gets(handle u32, buff str) i32 = rt$rt_gets;
fn rt_puts(handle u32, data str) i32 = rt$rt_puts;
fn rt_strcpy(dest str, src str, len u64) unit = rt$rt_strcpy;

pub fn scan(buff str) str = rt & mem {
    => fscan(stdin, buff);
}; 

pub fn print(data str) unit = rt {
    rt_puts(stdout, data);
}; 

pub fn fscan(handle u32, buff str) str = rt & mem {
    let read  = rt_gets(handle, buff);
    let buff' = mem::buffer(read u64);
    rt_strcpy(buff', buff, read u64);
    mem::free(buff);
    => buff';
};

pub fn fprint(handle u32, data str) unit = rt {
    rt_puts(handle, data);
};
