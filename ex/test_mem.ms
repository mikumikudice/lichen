use IO;
use MEM;

pub main = fn() : unit {
    buff = MEM::alloc(128 + 8);
    MEM::strlset(buff, 128 + 8);

    res = IO::read(IO::stdin, buff);
    read = MEM::alloc(res + 8);

    MEM::strcpy(read, buff, res + 8);
    MEM::free(buff);

    text = read : str;
    IO::write(IO::stdout, read);
    MEM::free(read);
};
