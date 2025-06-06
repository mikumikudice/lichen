# disclaimer
until the compiler is at 1.0, some of these features might be unavailable, considered invalid syntax, or cause compiler crashes.

# functions and variables and values

## types
lichen has a small type system which includes bare minimal for all common functionalities.
```rust
// unsigned integers
type unsigned = u8 | u16 | u32 | u64;

// signed integers
type signed = i8 | i16 | i32 | i64;

// floating points
type float = f32 | f64;

// string
type string = str;

// type "empty" unit, "never" void
type miscellany = unit | void;
```
lichen also has the keyword `todo` which evaluates to the zeroed-value of any given context. normally used for unfinished code, as the name suggests.

## functions
functions in lichen work as any other procedure in other languages, except for effect notations (address for in [effect system](#effect-system)) and by the return syntax, or rather, the map operator (`=>`).
```rust
// pure function
fn mul(x u32, y 32) u32 = {
    => x * y;
};

fn div(x u32, y 32) u32 = {
    => if y == 0 { // all statements are valid expressions
        => 0;
    } else {
        => x / y;
    };
};

io = use "io.lim"; // module import

fn meow() unit = io { // impure function that produces side effects from the "io" module
    io::println("meow")!;
};

pub fn main() void = do { // the do keyword denotes "any side effect"
    meow();
};
```
notes:
- the `void` type is terminal, i.e., it halts the program at the end of the function.
- the main function must be public in order to be visible to the linker. this is enforced at compile time, just like its return type (i.e. `void`).
- for the bang symbol at the end of functions, address for in [error handling](#error-handling).
- function scopes must end in a semicolon.


## variables
variables are always immutable, both its value as the namespace itself, i.e., once assigned, nothing about the variable can be changed. in contrast to most programming languages, variable names can start with numbers as long as they are not valid numeric literals (e.g., `0x1`, `0b01`, `007`, etc) and also has prime notation.
```rust
let x u32 = 4;
let y = x;                  // inferred type
let z u64 = (x * y) u64;    // subtype casting
let 1st = x + y;            // variable name starting with a number
let z' = z + 1st;           // prime notation is valid syntax
```
you may also declare multiple variables of the same type in the same line or different types with when they are inferred from the values.
```rust
let x, y, z u32 = (0, 1, 2); // tuple
let a, b = (x, "hi!"); // (u32, str)
```
notes:
- for more on tuples, address in [here](#value-tuples).

## literals
lichen supports hexadecimal, octal, binary and decimal literals, digit separators and trailing zeros for numeric values, escape sequences for strings and character literals. no decimal notation is allowed in favor of mathematical elegance, instead, it's used ratio notation (i.e. floating division operator).
```rust
let bin u32 = 0b1_00_00;
let dec u32 = 016;
let oct u32 = 0o1_00;
let hex u32 = 0x0001;

let single f32 = 1:5;
let double f64 = 3:4;

let txt str = "arg!";
let chr u8  = '\n';
```

# statements

## modules
lichen has a simple module system where files can be "wrapped" inside a variable, which only the public functions, global variables and types can be accessed. no module shall implement a main function, even if it's private. once lichen is lazily evaluated, only needed functions are dispatched as generated code.
```rust
// mod.lim file
pub fn foo() u32 = { // can be accessed
    => bar() + 1;
};

fn bar() u32 = { // cannot be accessed
    => 4;
};

fn egg() unit = { // not used by the module and cannot be accessed, then it won't be code-gen'ed
    // nothing
};
```
```rust
// main.lic

my_mod = use "mod.lim";

pub fn main() void = {
    let x = my_mod::foo();
};
```

## if-else blocks
if-else blocks in lichen can define limited-scope variables available only for the entire if-else block chain. the evaluation expression must be a numerical type, once there is no boolean type or "truthy" and "falsy" values.
```rust
    let x = foo();
    if y = bar(x); y > 4 {
        io::println("option a")!;
    } else if y < 4 {
        io::println("option b")!;
    } else {
        io::printfln("y = {}", y)!;
    };
```
notes:
- just like functions, the if-else chain must end in a semicolon.
- y is not visible outside the chain blocks.

if statements can also be assigned as values, as long they are exhaustive or unit is a valid variation of the type.
```rust
let x u32 = 4;
let y u32 = 5;
let z = if x > y {
        => x;
    } else {
        => y;
    };
```

## for iterator
lichen is a functional language, which means there is no mutable state. anyhow, something alike for-loops is available for iterating over strings and arrays.
```rust
let text str = "LoWeR cAsE";
let lower str = for c .. text; [10]u8 {
    => if 'A' <= c <= 'Z' { // chained comparisons
        => c + 32;
    } else {
        => c;
    };
};
```
see more about arrays address for in [here](#arrays).

## iterator accumulators
this iterator can also have accumulators, so you can evaluate to a mapped/reduced value of the given array. for instance:
```rust
let nums = [1, 2, 3, 4, 5, 6] u32;
let sum  =
    for c u32 = 0; i .. nums; c {
        => c + i;
    };

let odd, even =
    for o, e u32 = (0, 0); i .. nums {
        => if i % 2 == 0 {
            => (o, e + 1);
        } else {
            => (o + 1, e);
        };
    };
```
this way you can reproduce the effect of functions as foldl/foldr found in other functional languages.

## match statement
the match statement can be used to pattern-match against values (akin to a switch statement in other languages) and types for tagged unions.
```rust
let x u32 = 55;
match x {
0 =>
    io::println("x is zero")!;
1 .. 9 => // ranges are also valid
    io::println("x is between 0 and 10")!;
else => // match blocks must be exhaustive
    io::println("x is above or equal to 10")!;
};

let y u32 | str | unit = "hellope!";
match y {
unit =>
    io::println("y is empty")!;
text str =>
    io::println("y is \"{}\"", y)!;
num u32 =>
    io::println("y is a {}", y)!;
};
```
for tagged unions, address for in [here](#tagged-unions).

## test block
a test block may statically or dynamically assert for checks on the code. it can work in the same fashion of an assert statement or as a test unit in other languages.
```rust
fn sum(x u32, y u32) u32 = {
    => x + y;
};

fn div(x u32, y u32) u32 = {
    test y != 0;
    => x / y;
};

test "operations" {
    => sum(4, 5) == 9 && div(4, 2) == 2;
};
```
notes:
- when using the version with a scope and a name, the scope must return true (>= 1) in case of success or false (0) otherwise. this mode can be run with ``mmd test <file>`.
- the single line version, as shown within the `div` function, cannot be used at global scope. similarly, the `operations` test block shown at global scope cannot be used within a function.

# type system

## composite types
lichen allow primitive types be used to compose more complex types, such as arrays, value tuples, enumerated values, data records and tagged unions.

### arrays
arrays are immutable, bound-checked and of fixed size and type. they can be sliced and indexed and multi-dimensional as well.
```rust
let primes = [2, 3, 5, 7, 11, 13, 17] u32;
let slice []u32 = primes[0 .. 3];
let item = primes[0];
let len = #primes; // array length

let map [6, 6]u32 = [[ 0 .. 10 % 2 == 0 ]..]; // all even numbers from 0 to 10, repeated 6 times
let point = map[1, 3];
```
notes:
- all these operations can be performed on strings as well.

arrays and strings can be concatenated as well, resulting in a new allocation on the stack that copies the data from all members into a new set of data.
```rust
let hello = "hello ";
let world = "world!";
let greet = hello + world;

let odd = [1, 3, 5, 7, 9] u32;
let even = [0, 2, 4, 6, 8] u32;
let all = std::sort(odd + even);
```

### value tuples
tuples is a way to pack together multiple values of different or same type without the need for data records. the main difference is that you may not access its values without unpacking it.
```rust
fn swap(x u32, y str) (str, y) = {
    => (y, x);
};

pub fn main() void = {
    let a u32 = 4;
    let b str = "hi";
    let a', b' = swap(a, b);
    test a' == b && b' == a; // assert swap
};
```

### enumerators
enumerators, or enums for short, can make a set of finite and predefined values of any directly comparable type, for instance:
```rust
type stream = enum u32 {
    STDIN, STDOUT, STDERR,
};
type constant = enum f64 {
    PI = 355:113, SQRTTWO = 99:70,
}
type keyword = enum str {
    TYPE = "type",
    ENUM = "enum",
    STR = "str",
};
```

### records
records are, as the name suggests, records of data, akin to structures.
```rust
type dog = record {
    breed str,
    name str,
    age u8,
};

let sparky = dog {
    breed = "beagle",
    name = "sparky",
    age = 4,
};
```
as mentioned before, no record field can be changed after instantiation, but they might have default values and be operated on, when applicable. for instance:
```rust
type vec2 = record {
    x f64 = 0, y f64 = 0
};

let up = vec2 { y = 1 };
let left = vec 2 { x = -1 };
let upleft = up + left; // results in {x = -1, y = 1 }
let force = upleft * 33; // results in {x = -33, y = 33 }
```
once records are immutable and many times a copy with a single difference may be very useful, lichen also provides a quick syntax to make copies of records with single changes.
```rust
let v = vec2 { x = 1, y = 3 };
let v' = { v | y = 1 };
```

### tagged unions
tagged unions are a set of data that caries an instance of a limited set of types and a tag representing the current type. they shall not be used directly, but can be matched against its current type.
```rust
type result = u32 | unit;

fn div(x u32, y u32) result = {
    => if y != 0 {
        => x / y;
    } result; // casting the if block to the result type
};

pub fn main() void = {
    let r = div(4, y);
    let num = match r {
        n u32 => n;
        else => 0;
        };
};
```

### linear constructor/deconstructor
some functions can be wrapped around a deconstructor, yielding a linear type that has a life time on a automatic reference counting fashion. this way, when a variable is not needed anymore, it can be automatically assigned to a cleanup function. for instance:
```rust
// runtime wrapper for the open syscall
fn rt_open(filename str, flags: u32, mode u32) i32 = rt$rt_open;

// runtime wrapper for the close syscall
fn rt_close(f_handle u32) unit = rt$rt_close;

type handle = u32@rt_open;
type error = !i32;

pub type flags = enum u32 {
    READONLY  = 0o0000,
    WRITEONLY = 0o0001,
    READWRITE = 0o0002,
    CREATE    = 0o0100,
    EXEC      = 0o0200,
    TRUNCATE  = 0o1000,
    APPEND    = 0o2000,
};

fn wrap_file_error(filename str, flags: u32, mode u32) error!handle = rt {
    => if file = rt_open(filename, flags, mode); file < 0 {
        => file !i32;
    } else {
        => file handle;
    };
};

pub fn open(filename str, flags: u32) error!handle = rt {
    => wrap_file_error(filename, flags, 0o700);
};
```

```rust
fs = use "fs.lim";
io = use "io.lim";

pub fn main() void = fs & io {
    // instantiate a file handle. on error, io::fatal is called
    // `file` is created with refcount of 1
    let file = fs::open("foo.txt", fs::flags::CREATE |
        fs::flags::READWRITE) ! io::fatal("could not create \"foo.txt\" file");

    // write to the file handle
    io::fprint(file, "mornin' sailor!\n")!;

    // at the end of the scope, the `file` refcount falls to zero,
    // implicitly calling rt_close on it
};
```
if the same cleanup function is manually called on the variable, its refcount is also decreased and the implicit call is dropped. note that after this manual call, the linear object becomes unusable. those said early cleanups cannot happen on branching code i.e. if-else/match blocks.

## effect-system
at bottom level of the language runtime, there lies the OS syscalls implemented with assembly code. these low-level functions are impure by definition and should not be called directly, instead, the standard library provides abstractions for dealing with the file system, operating system, IO operations, etc. each standard module has pure and impure functions that the compiler will match against the type notations of each function. for instance, a function that uses an impure function of the io module should be tagged as `io` (or any given alias), and so on. functions may also be tagged with `do`, which can use any function but other `do` functions. e.g.
```rust
// io.lim

// runtime wrappers for the std handles
pub stdin  u32 = $rt_stdin;
pub stdout u32 = $rt_stdout;
pub stderr u32 = $rt_stderr;

// runtime wrappers for io functions
fn rt_gets(handle u32, buff str) i32 = rt$rt_gets;
fn rt_puts(handle u32, data str) i32 = rt$rt_puts;

// prints `data` to the stdout
pub fn print(data str) unit = rt {
    fprint(stdout, data);
};

// prints `data` followed by a new line to the stdout
pub fn println(data str) unit = rt {
    if #data {
        print(data);
    };
    print("\n"); // TODO: make it a single call with string concatenation
};
```
```rust
// main.lic

io = use "io.lim";

pub fn main() void = io { // main can only use io impure functions
    let name = io::scanln(256)!;
    io::println("mornin' {}!", name)!;
};
```
effect tags can also be chained in order to make multi-effect calls manageable instead of bunches of `do`'s.
```rust
fs = use "fs.lim";
io = use "io.lim";
os = use "os.lim";

pub fn main() void = fs & io & os {
    let _, args = os::args().pop()!; // pop the first cli argument and take only the copy of the iterator
    let name, _ = args.pop() ! // now, the second iterator copy is ignored
        io::fatal("no file name was given"); // try to pop the next argument from the new iterator and halt early on an error
    
    let file =
        match fs::open(name, fs::flags::WRITEONLY) { // try to open a file named after the second cli argument with write permissions
        e fs::error => io::fatal(fs::strerror(e)); // halt on error printing the said error message
        f fs::handle => f; // yield back the file handle on success
        };

    io::fprintln(file, "mornin' sailor!")!; // print to the file
};
```
notes:
- the `os::args()` function returns an iterator that represents the initial state of the cli argument list. the `pop()` function returns either an string with the argument value or an error in case a next argument is not available, and also a new copy of the said iterator that now moved forward on the argument list.
- the `_` syntax is used to ignore a return value.
- the said `pop()` function does not, in fact, return multiple values, instead, it returns a tuple of values.

## error-handling
errors in lichen are treated just like any other value, usually with tagged unions. theres two ways of using these and two ways of handling them.
```rust
fs = use "fs.lim";
io = use "io.lim";

type data = record {
    asset1 fs::handle,
    asset2 fs::handle,
};

fn load_file(name str) !fs::handle = fs { // returns an optional fs::handle
    => match fs::open(name) {
    a fs::handle => a; // valid value
    else => fail; // generic error value
    };
};

fn load_src() fs::error!data = fs { // returns either a "data" type or a fs::error
    => data {
        asset1 = load_file("image.png")?, // the interrogation operator "bubbles" up the error, 
        asset2 = load_file("sound.ogg")?, // short-circuiting an error value return
    };
};

pub fn main() void = do {
    // the bang operator halts the program in case of an error
    io::println("loading assets...")!;
    
    // the bang operator may also be used to run
    // some code in case of an error
    let assets = load_src() ! io::fatal("asset loading failed!");
    
    // the interrogation operator may also be used to
    // yield another given value in case of an error
    let icon = load_file("icon.ico") ? unit;
    match icon {
    fs::handle => unit;
    else => io::fatal("icon file not found!");
    };
};
```

### todo keyword
the `todo` keyword, similarly to how the `fail` keyword evaluates to a generic error, evaluates to a generic value. for instance, it always evaluates to the zeroed-value of any given type, even tagged unions.
```rust
type uni = u32 | str;
type val = (u32, uni);

type big_type = record {
    field_1 uni,
    field_2 val,
    field_3 unit | f64,
};

fn really_big_function() big_type = {
    => todo;
};

pub fn main() void = {
    let instance = really_big_function();
    let x = instance.field_1;
    let y = match x {
        n u32 => n + 1;
        t str => #t;
        };
    let instance' = {instance | field_3 = todo};
};
```

# syntax, operators and expressions
lichen has a stupidly simple operator precedence and expression parsing system. for instance, there's only four levels of precedence (from lowest to highest): boolean and/or, comparison operators, all other kinds of operations, parenthesis. of course, the evaluation of function arguments and unary operators is above all of these. and boolean expressions evaluate to numeric values (i.e. 0 and 1), for instance:
```rust
let y u32 = 1 + 1 * 2;                      // equivalent to (1 + 1) * 2
let z u32 = 4 * 5 + 2 / 5;                  // equivalent to ((4 * 5) + 2) / 5
let a u32 = 4 == 3 + 1 && 5 * 2 + 1 == 11;  // equivalent to (4 == (3 + 1)) && (( (5 * 2) + 1 ) == 11)
let b u32 = 6 > 1 == 1;                     // equivalent to (6 > 1) == 1
let c u32 = 8 < 4 == 0;                     // equivalent to (8 < 4) == 0
```
lichen consider plus and minus as valid unary operators and can be used as an prefix to any value, except for the plus on the middle of an expression. for instance:
```rust
let x = +1;
let y = -1;
let z = +x + -y;
```

# trivia
- the name lichen is an analogy of the nature of the hybrid colony and the language. both are composite of small units of isolated and self-sufficient units, on one side the algae and cyanobacteria, on the other, functions and types, but together compose complex structures that work exceptionally well together.

- previously, the language was called moss, due to similar analogies with the plant.

- the lichen language is the result of a series of sequential projects that attempted similar things on the language design field. this story can be found [here](https://mikumikudice.github.io/essays/mossyn-around).
