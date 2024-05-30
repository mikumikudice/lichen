use IO;

pub main = fn() : unit {
    x = print("working!");
};

print = fn(txt : str) : u32 {
    IO::write(IO::stdout, txt);
    IO::write(IO::stdout, "\n");
    return 8;
};
