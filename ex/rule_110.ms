use IO;

pub main = fn() : unit {
    rule =
        [ 0, 1, 1, 1
        , 0, 1, 1, 0
        ];
    mut map = 0;
    mut old = 1 << 31;
    for g = 0 .. 31 {
        for i = 0 .. 31 {
            pat = (old >> i) & 7;
            map = map | (rule[pat] << i);
            if rule[pat] == 1 {
                IO::write(IO::stdout, " #");
            } else {
                IO::write(IO::stdout, "  ");
            };
        };
        IO::write(IO::stdout, "\n");
        old = map;
        map = 0;
    };
};