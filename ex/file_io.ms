use fs;

pub main = fn() void & fs {
    file = fs::open("foo.txt", fs::CREATE | fs::RWONLY);
    fs::put(file, "mornin' sailor!\n");
    fs::close(file);
};
