pub fn get(size u64) str = do {
    => @rt.gets(rt::stdin, bz);
};

pub fn put(data str) unit = do {
    @rt::puts(rt::stdout, data);
}; 
