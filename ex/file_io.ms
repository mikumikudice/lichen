use fs;

pub main = fn() void & fs {
    file = fs::open("foo.txt", fs::W_ONLY);
    fs::put(file, "mornin' sailor!\n");
    fs::close(file);
};
