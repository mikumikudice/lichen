use IO;

pub main = fn() : unit {
    print("working!");
};

print = fn(txt : str) : unit {
    IO::write(IO::stdout, txt);
    IO::write(IO::stdout, "\n");
};
