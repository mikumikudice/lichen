use IO;

pub main = fn() : unit {
    arr = [ 1, 2, 3, 4 ] : []u32;
    arr[0] = arr[1];
    arr[-1] = 5;

    if arr[0] == 2 and arr[3] == 5 {
        IO::write(IO::stdout, "workin!");
    } else {
        IO::write(IO::stdout, "failed!");
    };
};
