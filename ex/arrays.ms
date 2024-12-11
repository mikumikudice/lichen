use io;

pub main = fn() void & io {
    num = [ 1, 2, 3, 4, 5 ] []u32;
    two = for n .. num {
        n * 2
    };
    sum = for a = 0; i .. two; a {
        a + i
    };
    if sum == 15 {
        io::put("success!\n");
    } else {
        io::put("fail!\n");
    };
};
