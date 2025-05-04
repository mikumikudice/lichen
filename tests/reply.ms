// temporary example to check if stdio is working
// and if nested function (calls) and modules are
// working properly.
io  = use "io.ms";
mem = use "mem.ms";

pub fn main() void = io & mem {
    io::print("hi! what's your name?\n > ");

    let buff = io::scan(mem::buffer(128));

    io::print("hello, ");
    io::print(buff);

    mem::free(buff);
};
