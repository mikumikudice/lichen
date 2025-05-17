// test for conflict between module binding
// and local variable name duplication

io = use "io.ms";

pub fn main() void = io {
    let io u32 = 0;
};
