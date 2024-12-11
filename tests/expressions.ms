use io;

pub main = fn() void & io {
    x = 7 u32;
    y = if x > 4 {
        4
    } else {
        x
    };
    if y == 4 {
        io::put("test 1 ok\n");
    };
    z = foo();
    if z == _ and not z {
        io::put("test 2 ok\n");
    };
};

foo = fn() unit { };
