use IO;

pub put = fn(data : str) : unit {
    IO::write(IO::stdout, data);
};

pub putl = fn(data : str) : unit {
    put(data);
    put("\n");
};