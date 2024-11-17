use fmt;

pub main = fn() never & fmt {
    num = [ 1, 2, 3, 4, 5 ] []u32;
    two = for n .. num {
        n * 2
    };
    sum = for a, i .. two {
        a + i
    };
    fmt::debug(sum);
};
