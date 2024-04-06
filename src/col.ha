use fmt;

// message coloring
const CMD: []str =
    [ "\x1b[0m"
    , "\x1b[0;31m"
    , "\x1b[0;32m"
    , "\x1b[0;33m"
    , "\x1b[0;34m"
    , "\x1b[0;40m"
    , "\x1b[0;41m"
    , "\x1b[0j"
    , "\x1b[7"
    , "\x1b[8"
    ];
type cmd = enum int {
    DEF, RED, GRN, YEL, BLU, BOX_BLK, BOX_RED,
    CLR, SVC, RSC,
};

fn col(t: fmt::formattable, c: cmd) str = {
    return fmt::asprintf("{}{}{}", CMD[c], t, CMD[cmd::DEF]);
};
fn clr() void = {
    fmt::printf("{}{}", CMD[cmd::RSC], CMD[cmd::CLR])!;
};