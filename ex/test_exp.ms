pub main = fn() : unit {
    mut x : u8;
    x = 4;

    y = 128 : u32;
    x = y : u8 + x;

    z = x : u64; 
    x = y : u8 + z : u8;

    w = x : i32;
    a = w + x : i32;
};
