use strings;
use bufio;
use fmt;

type unmatched = !void;
type index_oob = !void; 

type match_err = !(unmatched | index_oob);

// searches for the first occurance of ``pat`` in ``src`` and returns its
// index. returns a ``unmatched`` error if the pattern cannot be found
fn find(src: str, pat: str) (size | match_err) = {
    // avoid a lot of calls
    let slen = len(src): size;
    let plen = len(pat): size;

    if(slen == plen){
        if(strings::compare(src, pat) == 0) return 0;
    };
    // loop until the end
    for(let c: size = 0; c + plen <= slen; c += 1){
        let sub = strings::sub(src, c: size, (c + plen): size);
        if(strings::compare(sub, pat) == 0){
            return c;
        };
    };
    return unmatched;
};

// searches for the first occurance of ``pat`` in ``src`` after the index ``aft``
// and returns its index. returns a ``unmatched`` error if the pattern cannot be
// found
fn finda(src: str, pat: str, aft: size) (size | match_err) = {
    // avoid a lot of calls
    let slen = len(src): size;
    let plen = len(pat): size;

    if(aft > slen) return index_oob;

    if(slen == plen){
        if(strings::compare(src, pat) == 0) return 0;
    };
    // loop until the end
    for(let c = aft; c + plen <= slen; c += 1){
        let sub = strings::sub(src, c: size, (c + plen): size);
        if(strings::compare(sub, pat) == 0){
            return c;
        };
    };
    return unmatched;
};

// replaces every occurance of ``pat`` on ``src`` by ``sub`` and returns
// a copy of the result
fn replace(src: str, pat: str, sub: str) str = {
    // avoid a lot of calls
    let slen = len(src): size;
    let plen = len(pat): size;
    let blen = len(sub): size;

    if(strings::compare(src, sub) == 0){
        return sub;
    };
    // loop until the end
    for(let c = 0: size; c + plen <= slen; c += 1){
        // split the string in pre, middle and post
        let pre = strings::sub(src, 0, c: size);
        let mid = strings::sub(src, c: size, (c + plen): size);
        let pst = strings::sub(src, (c + plen): size, strings::end);

        if(strings::compare(mid, pat) == 0){
            src = strings::concat(pre, sub, pst);
            // update length
            c += len(src) - slen + blen;
            slen = len(src);
        };
    };
    return src;
};

// replaces every occurance of ``pat`` on ``src`` by ``sub`` if the match is not
// scaped by `bfr` (and `aft`) and returns a copy of the result. if `aft` is void
// only `bfr` is checked as scape sequence
fn sreplace(src: str, pat: str, sub: str, bfr: str, aft: (str | void)) str = {
    // avoid a lot of calls
    let slen = len(src): size;
    let plen = len(pat): size;
    let blen = len(sub): size;
    let flen = len(bfr): size;
    let alen = 0: size;
    if (!(aft is void)) alen = len(aft: str);

    if(strings::compare(src, sub) == 0){
        return sub;
    };
    // loop until the end
    for(let c = 0: size; c + plen <= slen; c += 1){
        // both before and after
        if(!(aft is void) && c + plen + alen <= slen){
            let bsub = strings::sub(src, (c - blen): size, c: size);
            let asub = strings::sub(src, (c + plen): size, (c + plen + alen): size);

            if(strings::compare(bsub, bfr) == 0 && strings::compare(asub, aft: str) == 0) continue;
        // only before
        } else {
            let bsub = strings::sub(src, (c - blen): size, c: size);
            if(strings::compare(bsub, bfr) == 0) continue;
        };

        // split the string in pre, middle and post
        let pre = strings::sub(src, 0, c: size);
        let mid = strings::sub(src, c: size, (c + plen): size);
        let pst = strings::sub(src, (c + plen): size, strings::end);

        if(strings::compare(mid, pat) == 0){
            src = strings::concat(pre, sub, pst);
            // update length
            c += len(src) - slen + blen;
            slen = len(src);
        };
    };
    return src;
};

fn uppercase(s: str) str = {
    let src = strings::toutf8(s);
    let max = len(src);
    for(let i = 0: size; i < max; i += 1){
        let c = src[i];
        if(c >= 'a' && c <= 'z'){
            src[i] = c - ('a': u8 - 'A': u8);
        };
    };
    return strings::fromutf8(src)!;
};

fn strlfind(haystack: []str, needle: str) (size | void) = {
    let max = len(haystack);
    for(let i = 0: size; i < max; i += 1){
        if(strings::compare(haystack[i], needle) == 0) return i;
    };
    return void;
};