use fmt;

pub main = fn() void & fmt {
    x = 7 u32;
    y = if x > 4 {
        4
    } else {
        x
    };

    if y == 4 {
        fmt::debug("test 1 ok\n");
    };

    z = foo();
    if z == _ and not z {
        fmt::debug("test 2 ok\n");
    };
};

foo = fn() unit { };
