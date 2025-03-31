io = use "io.ms";

pub fn main() void = io {
    let x u32 = 1 / 4;
    let y = (x - 1) i32;

    if x == 0 && y == -1 {
        io::put("test ok\n");
    } else {
        io::put("test fail\n");
    };
};
