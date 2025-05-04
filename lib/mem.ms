fn alloc(size u64) str = rt$rt_alloc;
pub fn free(ptr str) unit = rt$rt_free;
pub fn memcpy(dest str, len u64) unit = rt$rt_setlen;

pub fn buffer(size u64) str = rt {
    let buff = alloc(size + 8);
    memcpy(buff, size + 8);
    => buff;
};
