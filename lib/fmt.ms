use IO;
use MEM;

// prints `data` to stdout.
pub put = fn(data : str) : unit {
    if data {
        IO::write(IO::stdout, data);
    };
};

// prints `data` followed by a line feed to stdout
pub putl = fn(data : str) : unit {
    put(data);
    put("\n");
};

// reads `size` bytes from the stdin and consumes the
// trailing line feed. the returned data is allocated
// on the heap and hence must be freed.
pub get = fn(size : u64) : str {
    buff = MEM::alloc(size + 8) : str;
    MEM::strlset(buff, size + 8);

    res = IO::read(IO::stdin, buff) + 7;
    read = MEM::alloc(res) : str;

    MEM::strcpy(read, buff, res);
    MEM::free(buff);

    return read : str;
};
