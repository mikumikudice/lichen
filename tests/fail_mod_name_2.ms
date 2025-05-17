// test for conflict between function
// and module name duplication

fn io() u32 = { => 0 };
io = use "io.ms";
