pub fn main() void = {
    let true  u8 = 1;
    let false u8 = 0;

    let x  = true && true;
    let x' = true || false;

    let y  = false && false;
    let y' = false || false;

    let z = !true && true || false;
};