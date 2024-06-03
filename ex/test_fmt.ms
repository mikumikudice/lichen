use fmt;
use MEM;

pub main = fn() : unit \ fmt & MEM {
    src = fmt::get(256);
    
    num = fmt::atoi(src);
    dst = fmt::itoa(num, src.len);
    MEM::free(src);

    fmt::putl(dst);
    MEM::free(dst);
};
