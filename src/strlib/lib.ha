use strings;
use math;

use fmt;

export type unmatched = !void;
export type index_oob = !void; 

export type match_err = !(unmatched | index_oob);

@test fn str_only() void = {
    assert(find("boba tea", "tea")! == 5);
    assert(find("boba tea", "coffee") is unmatched);

    assert(finda("boba tea", "a", 5)! == 7);
    assert(finda("boba tea", "boba", 1) is unmatched);

    assert(replace("boba tea", "tea", "coffee") == "boba coffee");
    assert(replace("boba tea", "cofee", "banana") == "boba tea");

    assert(uppercase("HellopE!") == "HELLOPE!");
    assert(lowercase("hELLOPe!") == "hellope!");
};

// searches for the first occurance of ``pat`` in ``src`` and returns its
// index. returns a ``unmatched`` error if the pattern cannot be found
export fn find(src: str, pat: str) (size | match_err) = {
    // avoid a lot of calls
    const slen = len(src);
    const plen = len(pat);

    if(slen == plen){
        if(src == pat) return 0;
    };
    // loop until the end
    for(let c = 0z; c + plen <= slen; c += 1){
        const sub = strings::sub(src, c, c + plen);
        if(sub == pat){
            return c;
        };
    };
    return unmatched;
};

// searches for the first occurance of ``pat`` in ``src`` after the index ``aft``
// and returns its index. returns a ``unmatched`` error if the pattern cannot be
// found
export fn finda(src: str, pat: str, aft: size) (size | match_err) = {
    // avoid a lot of calls
    const slen = len(src);
    const plen = len(pat);

    if(aft > slen) return index_oob;

    if(slen == plen){
        if(src == pat) return 0;
    };
    // loop until the end
    for(let c = aft; c + plen <= slen; c += 1){
        const sub = strings::sub(src, c, c + plen);
        if(sub == pat){
            return c;
        };
    };
    return unmatched;
};

// replaces every occurance of ``pat`` on ``src`` by ``sub`` and returns
// a copy of the result
export fn replace(src: str, pat: str, sub: str) str = {
    // avoid a lot of calls
    let slen = len(src);
    const plen = len(pat);
    const blen = len(sub);

    if(src == sub){
        return src;
    };
    if(src == pat){
        return sub;
    };
    // loop until the end
    for(let c = 0z; c + plen <= slen; c += 1){
        // split the string in pre, middle and post
        const end = c + plen;
        const pre = strings::sub(src, 0, c);
        const mid = strings::sub(src, c, end);
        const pst =
            if(end != slen - 1){
                yield strings::sub(src, end, strings::end);
            } else {
                yield "";
            };

        if(mid == pat){
            src = strings::concat(pre, sub, pst);
            // update length
            c += len(src) - slen + blen;
            slen = len(src);
        };
    };
    return src;
};

// returns a new instance of `s` in uppercase
export fn uppercase(s: str) str = {
    const src = strings::toutf8(s);
    const max = len(src);
    for(let i = 0z; i < max; i += 1){
        const c = src[i];
        if(c >= 'a' && c <= 'z'){
            src[i] = c - ('a': u8 - 'A': u8);
        };
    };
    return strings::fromutf8(src)!;
};

// returns a new instance of `s` in lowercase
export fn lowercase(s: str) str = {
    const src = strings::toutf8(s);
    const max = len(src);
    for(let i = 0z; i < max; i += 1){
        const c = src[i];
        if(c >= 'A' && c <= 'Z'){
            src[i] = c + ('a': u8 - 'A': u8);
        };
    };
    return strings::fromutf8(src)!;
};

// searches for `needle` in `haystack`. returns the index
// if found, otherwise returnd void
export fn findl(haystack: []str, needle: str) (size | void) = {
    let max = len(haystack);
    for(let i = 0z; i < max; i += 1){
        if(haystack[i] == needle) return i;
    };
};