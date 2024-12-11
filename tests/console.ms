use io;

pub main = fn() void & io {
    io::put("what's your name?\n> ");
    name = io::get(128);

    if not name {
        io::put("please say your name!\n");
    } else {
        io::put("hello, ");
        io::put(name);
        io::put("!\n");
    };
};
