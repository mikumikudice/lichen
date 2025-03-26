use fmt;
use strings;

fn finds(strs: []str, itm: str) (size | void) = {
    const max = len(strs);
    for(let i = 0z; i < max; i += 1){
        if(strs[i] == itm) return i;
    };
};
