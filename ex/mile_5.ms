use fmt;

pub main = fn() void & fmt {
    x = 1 / 4 u32;
    y = (x - 1) i32;

    if x == 0 and y == -1 {
        fmt::debug("test ok\n");
    } else {
        fmt::debug("test fail\n");
    };
};
