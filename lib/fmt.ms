use IO;
use MEM;

// prints `data` to stdout.
pub put = fn(data : str) : unit \ IO {
    if data {
        IO::write(IO::stdout, data);
    };
};

// prints `data` followed by a line feed to stdout
pub putl = fn(data : str) : unit \ IO {
    put(data);
    put("\n");
};

// reads `size` bytes from the stdin and consumes the
// trailing line feed. the returned data is allocated
// on the heap and hence must be freed.
pub get = fn(size : u64) : str \ IO & MEM {
    buff = MEM::alloc(size + 8) : str;
    MEM::strlset(buff, size + 8);

    res = IO::read(IO::stdin, buff) + 7;
    buff' = MEM::alloc(res) : str;

    MEM::strcpy(buff', buff, res);
    MEM::free(buff);

    return buff' : str;
};

pub itoa = fn(src : u64, size : u64) : str \ MEM {
    buff = MEM::alloc(size + 8) : str;
    MEM::strlset(buff, size + 8);
    mut ptr = 0 : u64;
    mut num = src;
    for num > 0 {
        rem = num % 10;

        buff[ptr] = rem : u8 + '0';
        ptr += 1;

        num -= rem;
        num = num / 10;
    };
    return MEM::strrev(buff);
};

pub atoi = fn(src : str) : u64 \ IO {
    mut out = 0 : u64;
    mut pow = src.len - 1;

    for i = 0 .. src.len - 1 {
        mut chr = src[i]: u64 - '0';
        for r = 1 .. pow {
            chr = chr * 10;
        };
        pow -= 1;
        out += chr;
    };
    return out;
};
