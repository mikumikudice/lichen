use io;

pub main = fn() void & io {
    x = 6 u64;
    y = 7 u32;
    z = x * (y u64);

    if x < y u64 {
        io::put("test 1 ok\n");
    } else {
        io::put("test 1 fail\n");
    };

    if x + 1 == y u64 {
        io::put("test 2 ok\n");
    } else {
        io::put("test 2 fail\n");
    };

    if z > y u64 and z == (x * (y u64)) {
        io::put("test 3 ok\n");
    } else {
        io::put("test 3 fail\n");
    };

    if x u32 == y or x < z {
        io::put("test 4 ok\n");
    } else {
        io::put("test 4 fail\n");
    };
};