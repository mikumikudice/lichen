use fmt;

pub main = fn() unit {
    loop(10, [ 1, 1, 0, 1, 0, 1, 1, 0 ... ] : [16]u32);
};

loop = fn(cnt : u64, stt : []u32) void {
    if cnt > 0 {
        stt' = stt.inter(fn(b : u32, m : u32, a : u32) : u32 {
            pat = b << 2 + m << 1 + a;
            match pat {
            0 => 0
            1 => 1
            }
        });
        loop(cnt - 1, stt')
    }
};