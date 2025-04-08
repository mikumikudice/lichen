pub fn scan(size u64) str = do {
    => @rt.gets(rt::stdin, bz);
};

pub fn print(data str) unit = do {
    @rt::puts(rt::stdout, data);
}; 
