use rt;

pub get = fn(bz u64) str & rt {
    rt::gets(rt::stdin, bz)
};

pub put = fn(data str) unit & rt {
    rt::puts(rt::stdout, data);
}; 
