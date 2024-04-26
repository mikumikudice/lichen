use io;

pub def fail = err nil;

stdin  = 0;
stdout = 1;
stderr = 2;

putl = fn(data : str) : (u64 | fail) \ CLI {
    cat = data + "\n";
    puts(car)?;
};

puts = fn(data : str) : (u64 | fail) \ CLI {
    match io::write(data, stdout) {
        io::fail => return fail;
        len : u64 => return len;
    };
};

gets = fn(len : u64) : (str | fail) \ CLI {
    match io::read(len, stdin) {
        io::fail => return fail;
        out : str => return out;
    };
};
