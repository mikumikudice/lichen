use fmt;

pub main = fn() : unit \ fmt {
    mut cnt = 0 : u32;
    for 1 {
        cnt += 1;
        if cnt % 2 == 0 {
            fmt::putl("hoy!");
            next;
        };
        fmt::putl("hi!");
        if cnt > 4 {
            break;
        };
    };
    for i = 0 .. 2 : u32 {
        fmt::putl("yay!");
    };
};
