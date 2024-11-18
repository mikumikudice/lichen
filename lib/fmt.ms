use rt;

pub debug = fn(data str) unit & rt {
    rt::puts(rt::stdout, data);
};

pub read = fn(bz u64) str & rt {
    rt::gets(rt::stdin, bz)
};
