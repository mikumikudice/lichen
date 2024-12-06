use fmt;

pub main = fn() void & fmt {
    num = [ 1, 2, 3, 4, 5 ] []u32;
    two = for n .. num {
        n * 2
    };
    sum = for a, i .. two {
        a + i
    };
    if sum == 15 {
        fmt::debug("success!\n");
    } else {
        fmt::debug("fail!\n");
    };
};
