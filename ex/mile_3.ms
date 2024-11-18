use fmt;
use rt;

pub main = fn() void & fmt & rt {
    fmt::debug("what's your name?\n> ");
    name = fmt::read(128);

    if not name {
        fmt::debug("please say your name!\n");
    } else {
        fmt::debug("hello, ");
        fmt::debug(name);
        fmt::debug("!\n");
    };
};
