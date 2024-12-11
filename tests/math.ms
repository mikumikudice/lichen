use io;

pub main = fn() void & io {
    x = 1 / 4 u32;
    y = (x - 1) i32;

    if x == 0 and y == -1 {
        io::put("test ok\n");
    } else {
        io::put("test fail\n");
    };
};
