use MEM;

// recieves an union of a any-struct or raw type array
// and returns a heap-allocated copy of the given data
// value. returns !u32 in case of allocation failure.
alloc = fn(data : rec | []raw) : @raw ! u32 \ MEM {
    res = MEM::alloc(data.len);
    if res < 0 {
        return res : !u32;
    } else {
        MEM::copy(rs, data, len);
        return res;
    };
};

// duplicates the given data and then returns the two
// copies of the given linear object. returns !u32 in
// case of allocation failure.
dup = fn(src : @raw) : (@raw, @raw) ! u32 {
    new = alloc(src)?;
    src' = src;
    return (new, src');
};
