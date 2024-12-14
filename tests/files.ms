use rt;

pub main = fn() void & rt {
    file = rt::open("foo.txt", 64 | 2, 0o700);
    if file > 0 {
        rt::puts(file u32, "mornin' sailor!\n");
        rt::close(file u32);
        rt::unlink("foo.txt");
    } else {
        rt::exit(file);
    };
};
