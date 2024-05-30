use IO;
use MEM;

pub main = fn() : unit {
    buff = MEM::alloc(128 + 8);
    MEM::memset(buff, 128, 1);

    IO::read(IO::stdin, buff);
    read = buff : str;

    IO::write(IO::stdout, read);
};