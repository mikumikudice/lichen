use fmt;
use strings;

fn finds(strs: []str, itm: str) (size | void) = {
    const max = len(strs);
    for(let i = 0z; i < max; i += 1){
        if(strs[i] == itm) return i;
    };
};

fn ordnum(n: u64) str = {
    switch(n){
    case 1 => return strings::dup("first")!;
    case 2 => return strings::dup("second")!;
    case 3 => return strings::dup("third")!;
    case => return fmt::asprintf("{}th", n)!;
    };
};
