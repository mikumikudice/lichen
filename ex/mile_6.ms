use fmt;

pub main = fn() never & fmt {
    num = [ 1, 2, 3, 4, 5 ]: [*]u32;
    two = num.map(
        fn(a : u32) : u32 {
            a * 2
        };
    );
    sum = two.reduce();
    fmt::debug(sum);
};
