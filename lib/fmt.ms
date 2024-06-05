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

pub putf = fn(fmt : str, a1 : raw, a2 : raw, a3 : raw, a4 : raw): unit \ IO & MEM {
    mut arg = 0 : u64;
    mut set = 0 : u8;
    for i = 0 .. fmt.len - 1 {
        if fmt[i] == '%' {
            if set {
                IO::putb(IO::stdout, fmt[i]);
            };
            set = 1 - set;
        } else if set {
            mut a : raw;
            if arg == 0 {
                a = a1;
            } else if arg == 1 {
                a = a2;
            } else if arg == 2 {
                a = a3;
            } else if arg == 3 {
                a = a4;
            };
            if fmt[i] == 's' {
                put(a : str);
            } else if fmt[i] == 'u' {
                num = itoa(a : u64, 512);
                put(num);
                MEM::free(num);
            } else if fmt[i] == 'i' {
                src = a : i64;
                if src >= 0 {
                    num = itoa(a : u64, 512);
                    put(num);
                    MEM::free(num);
                } else {
                    IO::putb(IO::stdout, '-');
                    num = itoa(src : u64, 512);
                    put(num);
                    MEM::free(num);
                };
            };
            set = 0;
            arg += 1;
        } else {
            IO::putb(IO::stdout, fmt[i]);
        };
    };
};

pub putfl = fn(fmt : str, a1 : raw, a2 : raw, a3 : raw, a4 : raw): unit \ IO & MEM {
    putf(fmt : str, a1, a2, a3, a4);
    putl(...);
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
    flen = ptr + 8;
    buff' = MEM::alloc(flen) : str;
    MEM::strcpy(buff', buff, flen);

    return MEM::strrev(buff');
};

pub atoi = fn(src : str) : u64 {
    mut out = 0 : u64;
    mut pow = src.len - 1;
    // TODO: assert for empty strings
    // when unions are available
    for i = 0 .. src.len - 1 {
        mut chr = src[i] : u64 - '0';
        for r = 1 .. pow {
            chr = chr * 10;
        };
        pow -= 1;
        out += chr;
    };
    return out;
};
