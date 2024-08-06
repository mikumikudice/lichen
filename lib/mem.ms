use rt;

pub arena = fn(size u64) u64 & rt {
    rt::arena(size)
};

pub free = fn(arena u64) unit & rt {
    rt::free(arena);
};
