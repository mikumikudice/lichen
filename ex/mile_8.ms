use fmt;

pub main = fn() void & fmt {
    loop(0, 10);
};

loop = fn(c u64, max u64) unit & fmt {
    fmt::debug("here!\n");
    if c == max {
        loop(c + 1, max)
    }
};
