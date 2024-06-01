use fmt;

pub main = fn() : unit \ fmt {
    rule =
        [ 0, 1, 1, 1
        , 0, 1, 1, 0
        ] : [4]u8;
    mut map = 0;
    mut old = 1 << 31;
    for g = 0 .. 31 {
        for i = 0 .. 31 {
            pat = (old >> i) & 7;
            map = map | (rule[pat] << i);
            if rule[pat] == 1 {
                fmt::put(" #");
            } else {
                fmt::put("  ");
            };
        };
        fmt::putl(...);
        old = map;
        map = 0;
    };
};
