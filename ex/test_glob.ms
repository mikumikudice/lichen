four = 4 : u32;
five = 5 : u64;
twenty = four * five : u32;

pub main = fn() : unit {
    mut x = twenty;
    x = x + 1;
};