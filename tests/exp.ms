pub fn main() void = {
    let x = 7 u32;
    let y = x + foo(x);
    let z = bar(y);
};

fn foo(x u32) u32 = {
    => x * x;
};

fn bar(x u32) u32 = {
    let y u32 = todo;
    => foo(x + y);
};
