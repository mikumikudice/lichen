use fmt;

pub main = fn() void & fmt {
    x = 6 : u64;
    y = 7 : u32;
    z = x * (y : u64);

    if x < y : u64 {
        fmt::debug("test 1 ok\n");
    } else {
        fmt::debug("test 1 fail\n");
    };

    if x + 1 == y : u64 {
        fmt::debug("test 2 ok\n");
    } else {
        fmt::debug("test 2 fail\n");
    };

    if z > y : u64 and z == (x * (y : u64)) {
        fmt::debug("test 3 ok\n");
    } else {
        fmt::debug("test 3 fail\n");
    };

    if x : u32 == y or x < z {
        fmt::debug("test 4 ok\n");
    } else {
        fmt::debug("test 4 fail\n");
    };
};