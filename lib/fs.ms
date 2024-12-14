use rt;

// flags
R_ONLY = 0o0 u32;
W_ONLY = 0o1 u32;
RWONLY = 0o2 u32;
CREATE = 0o0100 u32;
EXECTB = 0o0200 u32;
APPEND = 0o2000 u32;

// permissions
RW_USR = 0o700 u32; // user has read/write and execute permissions
RD_USR = 0o400 u32; // user has read permission
WD_USR = 0o200 u32; // user has write permission
EX_USR = 0o100 u32; // user has execute permission

pub open = fn(fpath str, flags u32) u32 & rt {
    file = rt::open(fpath, flags, RW_USR);
    if file > 0 {
        file u32
    } else {
        0
    }
};

pub close = fn(handle u32) unit & rt {
    rt::close(handle);
};

pub get = fn(handle u32, bz u64) str & rt {
    rt::gets(handle, bz)
};

pub put = fn(handle u32, data str) unit & rt {
    rt::puts(handle, data);
};

pub rm = fn(fpath str) unit & rt {
    rt::unlink(fpath);
};
