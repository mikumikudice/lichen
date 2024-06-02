use IO;
use MEM;

pub main = fn() : unit \ IO & MEM {
    buff = MEM::alloc(128 + 8) : str;
    MEM::strlset(buff, 128 + 8);

    res = IO::read(IO::stdin, buff);
    buff' = MEM::alloc(res + 8) : str;

    MEM::strcpy(buff', buff, res + 8);
    MEM::free(buff);

    text = buff' : str;
    IO::write(IO::stdout, text);
    MEM::free(text);
};
