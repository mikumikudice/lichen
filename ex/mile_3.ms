use IO;

// third milestone of the compiler
pub main = fn() : unit {
    arg = 4 : u32;
    res = fun(arg, 5);

    if res == 20 {
        IO::write(IO::stdout, "workin!\n");
    } else {
        IO::write(IO::stdout, "failed!\n");
    };
};

fun = fn(x, y : u32) : u32 {
    return x * y;
};
