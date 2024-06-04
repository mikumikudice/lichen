use fmt;
use MEM;

pub main = fn() : unit \ fmt & MEM {
    mut in = fmt::get(256);
    x = fmt::atoi(in);
    MEM::free(in);

    in = fmt::get(256);
    y = fmt::atoi(in);
    MEM::free(in);

    if x % 5 == 0 and y % 3 == 0 {
        fmt::putl("if!");
    } else if x % 5 == 0 
        or y % 3 == 0  {
        fmt::putl("else if!");
    } else {
        fmt::putl("else!");
    };
};
