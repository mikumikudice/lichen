use fmt;

pub main = fn() : unit \ fmt {
    arr = [ 1, 2, 3, 4 ] : []u32;
    arr[0] = arr[1];
    arr[-1] = 5;

    if arr[0] == 2 and arr[3] == 5 {
        fmt::putl("workin!");
    } else {
        fmt::putl(IO::stdout, "failed!");
    };
};
