use fmt;
use MEM;

pub main = fn() : unit \ fmt & MEM {
    fmt::put("what's your name?\n > ");
    name = fmt::get(256);

    fmt::put("hello, traveler ");
    fmt::put(name);
    fmt::putl("!");

    MEM::free(name);
};
