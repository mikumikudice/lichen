io = use "io.ms";

msg str = "mornin' " + "sailor!";

pub fn main() void = io {
    let text = "mornin' sailor!";
    let length = #text;

    if msg == text {
        io::print("ok\n");
    } else {
        io::print("fail\n");
    };
};
