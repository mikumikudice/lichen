pub stdin u32 = @rt_stdin;
pub stdout u32 = @rt_stdout;

pub fn scan(size u64) str = do {
    => @rt_gets(stdin, bz);
};

pub fn print(data str) unit = do {
    @rt_puts(stdout, data);
}; 
