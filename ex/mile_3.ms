use rt;
use fmt;

pub main = fn() void & fmt & rt {
    arena = rt::arena(128);
    fmt::debug("what's your name?\n> ");
    name = fmt::read(arena);

    if not name {
        fmt::debug("please say your name!\n");
    } else {
        fmt::debug("hello, ");
        fmt::debug(name);
        fmt::debug("!\n");
    };
    rt::free(arena);
};
