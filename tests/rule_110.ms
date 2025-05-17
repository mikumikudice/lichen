io = use "io.ms";

pub fn main() void = io {
    rule([0, 0, 0, 0, 0, 0, 0, 1], 0);
};

fn rule(map []u8, gen u64) unit = io {
    let map' =
        for b, c, a .. map {
            let c' =
                if b << 2 | c << 1 | c == 0b111 {
                    => 0;
                } else if b << 2 | c << 1 | c == 0b110 {
                    => 1;
                } else if b << 2 | c << 1 | c == 0b101 {
                    => 1;
                } else if b << 2 | c << 1 | c == 0b100 {
                    => 0;
                } else if b << 2 | c << 1 | c == 0b011 {
                    => 1;
                } else if b << 2 | c << 1 | c == 0b010 {
                    => 1;
                } else if b << 2 | c << 1 | c == 0b001 {
                    => 1;
                } else {
                    => 0;
                };
            if c' {
                io::print("#");
            } else {
                io::print(".");
            };
            => c';
        };
    io::print("\n");

    if gen < 128 {
        rule(map', gen + 1);
    };
};
