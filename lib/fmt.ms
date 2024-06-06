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
    mut arg = 1 : u64;
    mut set = 0 : u8;
    for i = 0 .. fmt.len - 1 {
        if fmt[i] == '%' {
            if set {
                IO::putb(IO::stdout, fmt[i]);
                set = 0;
            } else {
                set = 1;
            };
            next;
        };
        if set {
            mut this : raw;
            if arg == 1 {
                this = a1;
            } else if arg == 2 {
                this = a2;
            } else if arg == 3 {
                this = a3;
            } else if arg == 4 {
                this = a4;
            } else {
                put("args overflow");
                return;
            };
            if fmt[i] == 's' {
                put(this: str);
            } else if fmt[i] == 'u' {
                num = itoa(this: u64, 512);
                put(num);
                MEM::free(num);
            } else if fmt[i] == 'i' {
                val = this: i64;
                if val < 0 {
                    IO::putb(IO::stdout, '-');
                };
                num = itoa(val: u64, 512);
                put(num);
                MEM::free(num);
            } else {
                put("invalid escape char: \"");
                IO::putb(IO::stdout, fmt[i]);
                IO::putb(IO::stdout, '"');
                return;
            };
            arg += 1;
            set = 0;
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
    if src == 0 {
        buff = MEM::alloc(9) : str;
        MEM::strlset(buff, 9);
        MEM::strcpy(buff, "0", 9);
        return buff;
    };
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
