named core.stdio;

extrn err    = !nil;
extrn stdout = 0b01;
extrn stdin  = 0b10;

#--
prints [s] to the stdin and returns the number
of non-meta characters printed

if the given string has an invalid UTF-8 char,
stdio::err is returned
--#
extrn puts = fn(d = str) BM > IO {u64 | err} {
    cnt = 0;
    for c = u64 0..(u64 d) {
        if d[c] /= 0 {
            if d[c] > 127 {
                return err;
            };
            putc(d[c], stdout);

            if (d[c] > 31 and d[c] < 128)
            or (d[c] == '\n' or d[c] == '\t') {
                cnt += 1;
            };
        } else {
            return err;
        };
    };
    return u64 cnt;
};

#--
returns a string up to [s] bytes in size with
the contents from stdin.

if the given size is 0 or smaller than the
data in stdin, stdio::err is returned.

note that [out] is a string slice, therefore,
a linear type.
--#
extrn gets = fn(s = u64) BM > IO {str | err} {
    # invalid size
    if s == 0 {
        return err;
    };
    out = [s]str{0...};

    cnt = u64;
    for cnt = 0..s {
        c = getc(stdin);
        out[i] = c;
        cnt = i;
        
        # end loop if reached eof
        if c == '\n' {
            break;
        };
    };
    # size is too small
    if out[s - 1] /= '\n' {
        return err;
    };
    # shrink slice
    if cnt < s {
        out = ext(out, cnt);
    };
    return out;
};
