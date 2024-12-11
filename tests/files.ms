use rt;

pub main = fn() void & rt {
    file = rt::open("foo.txt", 64 | 2, 0o700);
    if file > 0 {
        rt::puts(file, "mornin' sailor!\n");
        rt::close(file);
        rt::unlink("foo.txt");
    } else {
        rt::exit(file);
    };
};
