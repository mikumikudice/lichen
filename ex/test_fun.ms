use fmt;

pub main = fn() : unit \ fmt {
    x = print("working!");
    y = ret(x / 2);
    fmt::putfl("%u", y, ...);
};

print = fn(txt : str) : u64 \ fmt {
    fmt::putl(txt);
    return txt.len;
};

ret = fn(num : u64) : u64 {
    return num;
};
