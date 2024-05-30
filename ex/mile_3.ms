use IO;
use MEM;

// third milestone of the compiler
pub main = fn() : unit {
    input = scan(128);
    if input == "hi\n" {
        IO::write(IO::stdout, "hiii!\n");
    } else if input == "bye\n" {
        IO::write(IO::stdout, "bye bye!\n");
    } else {
        IO::write(IO::stdout, "hop!\n");
    };
    MEM::free(input);
};

scan = fn(max : u64) : str {
    buff = MEM::alloc(max + 8) : str;
    MEM::strlset(buff, max + 8);

    res = IO::read(IO::stdin, buff) + 8;
    read = MEM::alloc(res) : str;

    MEM::strcpy(read, buff, res);
    MEM::free(buff);

    return read : str;
};
