use IO;
use MEM;

pub main = fn() : unit {
    buff = MEM::alloc(128 + 8);
    MEM::memset(buff, 128, 1);

    res = IO::read(IO::stdin, buff);
    read = MEM::alloc(res + 8);

    MEM::strcpy(read, buff, res);
    MEM::free(buff);

    text = read : str;
    IO::write(IO::stdout, read);
    MEM::free(read);
};
