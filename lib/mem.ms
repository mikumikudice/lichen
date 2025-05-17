// [to be deprecated]
// the mem module implements rudimentary tools to deal
// with dynamically allocated string buffers

// runtime wrapper to the mmap syscall
fn alloc(size u64) str = rt$rt_alloc;

// runtime wrapper to the munmap syscall
pub fn free(ptr str) unit = rt$rt_free;

// runtime wrapper for assigning string capacity
pub fn assigncap(dest str, len u64) unit = rt$rt_setlen;

// [to be deprecated]
// instantiates a mutable string buffer allocated
// on the heap. the given `size` is how many writable
// bytes will be available, not how many bytes will
// be actually allocated.
pub fn buffer(size u64) str = rt {
    let buff = alloc(size + 16);
    assigncap(buff, size + 16);
    => buff;
};
