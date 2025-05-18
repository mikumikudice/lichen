// parsing test for function calls,
// lazy dispatch and return values

pub fn main() void = {
    foo(1);
};

fn foo(x u32) u32 = {
    => bar(x, x + 1);
};

fn bar(x u32, y u32) u32 = {
    => x + y;
};

fn unused() unit = { };
