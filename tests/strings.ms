io = use "io.ms";

msg str = "mornin' " + "sailor!";

pub fn main() void = io {
    let text = "mornin' sailor!";
    let length = #text;
    let comp u64 = msg == text;

    if comp {
        io::print("ok\n");
    } else {
        io::print("fail\n");
    };
};
