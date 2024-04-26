use IO : "io.asm";

pub def fail = err u8;

write = fn(data : str, strm: u32) : u64 | fail \ IO {
    if errv = IO.write(data, strm); errv {
        return fail;
    } else {
        return len(data);
    };
};

read = fn(len : u64, strm : u32) : @str | fail \ IO {
    buff = IO.alloc(str, len) : @str;
    if errv = IO.read(buff, len, fail); errv {
        return fail;
    } else {
        return buff;
    };
};
