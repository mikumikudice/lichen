use fmt;

export fn main() void = {
    let x: []int = [1, 2, 3];
    let y: []int = [4, 5, 6];
    append(x, y...);

    for(let i = 0; i < 6; i += 1){
        fmt::println(x[i])!; 
    };
};