# hello world!
a simple demonstration hello world code in moss.
```rust
use fmt;

pub main = fn() : unit \ fmt {
    fmt::putl("mornin' sailor!")!;
};
```

# lexical elements and literals
## comments
moss supports single and multiple commented lines of code, including nested blocks.
```rust
// this is a comment
/*
    and this is a multi-lined
    comment and the fallowing
    /*
        is a nested-commented
        block of text in moss
    */
*/
```

## reserved names
this is a list of the 32 tokens used as keywords for the language and as such cannot be used as variable names:
| encapsulation | types                 | control flow       | miscellany    |
| ------------- | --------------------- | ------------------ | ------------- |
| `use`         | `u8, u16, u32, u64`   | `if, else, match`  | `mut`         |
| `pub`         | `i8, i16, i32, i64`   | `for, next, break` | `test`        |
|               | `rat, str, any, raw`  | `yield, return`    | `is, and, or` |
|               | `unit, fn, uni, rec`  | `defer`            |               |

# types and variables
these are all primitive and composite types in moss.
```rust
u8, u16, u32, u64       // unsigned integers
i8, i16, i32, i64       // signed integers
rat                     // ratios
rec                     // records
uni                     // tagged unions
str                     // string types
any                     // generic tagged unions for any type
raw                     // untyped 64-bit raw data
unit                    // "nothing" type
```

## numbers and ratios
numbers can be represented in decimal or hexadecimal, ocatal and binary using the prefix `0x`, `0o` and `0b`, respectively. numbers also can use digit separators (`_`) at any place. moss also doesn't support floats by default, but instead ratios. that means your divisions results in an integer part and a ratio. you can see more about ratios in [its section](#ratios). these all are valid numerical values:
```rust
123_456 : u64;      // 123456
99 * 99 : i64;      // 9801
0o77777 : u16;      // 32767
0x0ff80 : i16;      // -128
0b11010 : u8;       // 26
81 / 27 : i8;       // 3
-1 / 12 : rat;      // -(1/12)
```
* note that in the first example, it's shown how moss allows digit separators.

numerical literals have no concrete type and always must be casted to some type. casting uneven divisions to interger types results in rounding down the number (i.e. resulting only in the integer part of the division) and signed values to unsigned results in the absolute type. casting a bigger literal e.g. 2048 to an u8 results in a compilation error.

## strings
strings in moss are an immutable array of bytes, not null terminated, in contrast with C-like `char*` strings, and are UTF-8 encoded. as immutable data, you can't change their bytesm but you can access them individually.
```rust
foo = "mornin'";            // immutable value and namespace
mut bar = " sailor!\n";     // immutable value, but mutable namespace

chr = bar[bar.len - 1];     // chr == 10
```

and these are the only supported escape-characters in moss.
- `\t` for tab
- `\b` for backspace
- `\a` for bell
- `\r` for carriage return
- `\n` for line feed
- `\f` for form feed
- `\\` backslash
- `\'` single quote
- `\"` double quote
* note that there are no backwards compatibility with legacy stuff like vertical tab. formated printing have its own special set of escape chars (that also includes these listed above).

## unit type
in constrast with the already known type `void` from other languages, which caries no value and usually is found as a return type for functions that return nothing, the unit type actually has one and only one value, `_`, which is implicitly returned by all functions without a return statement or named return.
```rust
nothing = fn() : unit { };

test nothing() == _; // succeeds
```

## any type
TODO

## raw type
TODO

# declaration, definition assignment and type casting
```rust
mut foo : u32;      // declaration of a mutable value
mut bar = 42: u64;  // declaration and definition

foo = 6742;         // assignment

bar = foo;          // u32 is a subset of u64, no need for explicit casting
foo = bar: u32;     // explicit casting because an u64 value can overflow an u32

egg = -55: i64;     // immutable value
foo = egg: u32;     // casting from bigger to lower size means modulo dividing the value, casting signed to unsigned means absolute value
```
* note that all variables are immutable by default and can be set to mutable ONLY when defined within functions. all arguments passed to other functions are also immutable references by default.

# expressions and operators
```rust
a = 42 + 7 - 1 : u32;   // the whole expression is casted to u32
c = 5 * (42 + 3): u16;  // no operator precedence, use parenthesis to enclose an expression
```
* note the casting affects the whole expression. if you need to cast only one value, do `(foo : type)`

# records
also called "structs" by other languages, these are collections of data whithin fields of a single data structure.
```rust
dog : rec {
    age   : u8,
    name  : str,
    owner : str,
};
```

# control flow
these are the control flow blocks that can be used in moss.
## if-else blocks
```rust
if x = 5 * 5; x > 64 {
    fmt::putl("5^2 is bigger than 8^2")!;
} else if x > 16 {
    fmt::putfl("5 squared is greater than 4 squared by a factor of {} units", x - 16)!;
} else {
    fmt::putfl("5 squared is {}", x)!;
};
```
* note that all blocks must have a body with brackets, but there's no parenthesis enclosing the evaluated portion.

## match blocks
match blocks works both as a switch block and a pattern matching block. it can check the value or the type of a given variable. the distinction is done by checking if the argument is a tagged union and if the match cases are values or types.
```rust
my_uni : uni u32 | str;
...
x = 55: my_uni;
match x {
    u32 => fmt::putl("x is an integer!")!;
    str => fmt::putl("x is a string!")!;
};
```
a match block can also be use ranges when matching values.
```rust
x = 4 : u32;
match x {
    0     => fmt::putl("x is zero")!;
    1..10 => fmt::putl("x is under 10")!;
    _    => fmt::putl("x is bigger or equal to 10")!; // `_` means any case
};
```
* note that there's no need to use break in either of these uses.

or even, match can be used as a long sequence of if-else blocks:
```rust
x = 'v';                                                        // literal chars are u8 values
match {                                                         // empty match stands for "match true"
    x == 'a'..'z' => fmt::putl("x is a lowercase rune")!;       // comparison can be used with ranges
    x == 'A'..'Z' => fmt::putl("x is a uppercase rune")!;
    x == '0'..'9' => fmt::putl("x is a numeral")!;
    _ => {
        if x == '.' {
            fmt::putl("x is a dot!")!;
        } else if x == ',' {
            fmt::putl("x is a comma!")!;
        };
    };
};
```

## for loops
for loops are the only available kind of loop in moss. they work as a normal for loop, a while loop and a foreach loop in other languages. here's all its uses:
```rust
// no incrementing or decrementing, we use ranges
for i = 2 .. 20 : u32 {
    fmt::putfl("{}", i)!;
};

mut r = 0;
for r < 100 {
    r = some_funky_fn(r);
    if r == 55 {
        next; // equivalent to `continue` in other languages
    } else if r == 67 {
        break;
    };
};

num = [ 2, 3, 5, 7, 11, 13, 17, 23 ] : []u32;
for n .. num {
    fmt::putfl("{}", n)!;
};
```
* note that, contextually, `next` is more logical than `continue`, once you want skip to the next interaction, not continue on the current one.

you even can use parallel assignment for a shorthand for nested loops.
```rust
for c, r = 0 .. 127 : u32 {
    z = c + r;
};
```
the previous example is the same as:
```rust
for c = 0 .. 127 : u32 {
    for r = 0 .. 127 : u32 {
        z = c + r;
    };
};
```
# truthy values and comparisons
if moss, there are no first-class boolean types (althogh there's a bool type in the `types` module from the standard library), but the truthness of values on if/for blocks are not like C languages. for instance, empty strings and arrays, unit type and 0 are considered falsey, anything else is considered true. you can put any type on a if/for block for truth-checking, execpt for structures, once these are not semantically meaninful to be considered checkable.

when doing comparisons, you can check equality and inequality with any two types, but greater/lesser comparisons are only allowed between subtypes i.e. numerical types between numerical types, strings with strings, arrays with arrays. these last two are compared only using their length. in this case, lists, unions and structures are prohibited to be compared for the same reason of equality. in the specific case of lists, these have no size to be compared. see more on [their own topic](#lists).

comparison between functions is prohibited.

comparison of union values cannot be done without casting, but you also can check their tag using the `is` operator. for example:
```rust
num_or_str : uni i64 | rat | str;

foo = 32 : i64 : num_or_str;
bar = 1 / 64 : rat : num_or_str;
egg = "hi!!!" : num_or_str;

foo_t = foo is i64; // true (1)
bar_t = bar is str; // false (0)
egg_t = egg is rat or egg is i64; // false
```
* note that moss uses `and` and `or` instead of `&&` and `||` for boolean operations.

# unions, error handling and pattern matching
moss has no exception handling. everything that can go wrong is dealt simply as another kind of return value. these types are a special kind called error types. these can be defined defining unions with an error option using a bang. when a function can return an union tagged as an option, it must be handled with a match block, the propagation operator `?` or by the assertion operator `!`.
```rust
use fmt;

int : uni i32 ! u8;

pub main = fn() : u32 \ fmt {
    mut res = myfn(7, 2);

    match res {
        int => fmt::putfl("7 divided by 2 is {}", r: i32)!;
        nan => fmt::panic("error! division by zero");
    };
    res = myfn(6, 2)!;
    return 0;
};

myfn = fn(n, d: i32) : int {
    if d == 0 {
        return !0;
    } else {
        return n / d;
    };
};
```
* note that only one type can be the error case for an union.

# named returns
functions, just as it can have named parammeters, can have a named return value.
```rust
myfn = fn(x, y: i64) r: i64 {
    r = x * x + y;
    if r < 0 {
        r = y * y - x;
    };
    return;
};
```

# default values
you can set default attributions for your parameters when creating functions.
```rust
div = fn(n, d = 1, 1: i64) : i64 { // both parameters will be set to 1 if no argument is given
    return n / d;
};

person : rec {
    name = "bob",   // these will be the default values of these fields when instantiating the `person` record
    age  = 18: u32
};
```

# zero values
all unassigned variables will start with its zero corresponding value depending on its type:

- u8, u16, u32, u64, i8, i16, i32, i64, rat: 0
- str: ""

record fields are set to their respective zero values as well or the default value if set. unions are the only objects that must be initialized, once there is no objectively correct type to inherit the zeroed value.

# arrays and ranges
## syntax
arrays need a size, a type and a value. a size can be given or deduced by context. a value may or may not be initialized explicitly (being set to the default zero of tye type if not).
```rust
foo = [1, 2, 3, 4]: [4]u32;                 // explicit size
bar = ["mia", "chloe", "liam", "finn"];     // context-deduced ([4]str)
egg : [8]i64;                               // all 8 items set to 0
```

you can also define ranges when assigning to arrays or even set default values to all members.
```rust
all_ones = [1...]: [32]u32;                 // fill all 32
mytenths = [10...; 5]: [10]u32;             // every 5th number, starting from 10
all_even = [0 .. 10; %2 == 0];              // all numbers from 0 up to 10 that are even
```
* note that in `all_even`, the `%2 == 0` is a rule for the filling. only n % 2 == 0 will be assigned (up to 10).

# lists
TODO

# modules
whenever you create a file, it becomes a module. all the namespaces, i.e. functions, variables and types, can either be private or public. to make a namespace public, simply add `pub` at the beginning. if a public function returns or accepts a local-defined type, this type also has to be public. so, for instance:
```rust
pub hashmap : rec {
    vals : []raw,
    keys : []raw,
};

pub new_map = fn(ptr : @raw, vals : []raw, keys : []raw) : @hashmap ! u32 {
    if vals.len != keys.len {
        return !1;
    };
    mut out = ptr: @hashmap;
    out.vals = vals;
    out.keys = keys;
};

pub get = fn(self : hashmap, key : raw) : raw | unit {
    match find_key(self, key) {
    k : u32 => return self.val[k];
    _ => return _;
    }
};

pub set = fn(self : @hashmap, key : raw, val : raw) : @hashmap ! u32 {
    match find_key(self, key) {
    k : u32 =>
        mut copy = self;
        key.vals[ik] = val;
        return copy;
    _ => return !1;
    };
};

find_key = fn(self : hashmap, key : raw) : u64 ! unit {
    for i .. self.keys.len {
        k = self.keys[i];
        if k == key : t {
            return i;
        };
    };
};
```
* note that `find_key` is used by public functions, but it doesn't have to be public as well.
* also note that the return type is a linear instance of a hashmap. see more on [linear types](#linear-types).

# effect system
at the bottom level, all IO operations, such as CLI and memory allocation, are done by the language kernels. these are bindings to runtime functions implemented in low-level code and should not be used directly unless you're doing something that cannot be done with pre-existing modules. when a function uses a kernel, it must be tagged with its name, indicating its side-effects, making it impure. all functions in the same module that uses this impure function must be tagged as such and hence becoming impure as well. all modules with impure functions become impure, so all code that uses impure functions from this module should be tagged with the module name as well. example:
```rust
// code from io.ms i.e. the module io
use IO; // IO in uppercase is the kernel, io in lowercase is the module

pub stdout = 1 : u32;

pub write = fn(handle : u32, data : str) unit ! u32 \ IO { // impure function
    res = IO::write(handle, data);
    if res < 0 {
        return !res;
    };
};

pub etos = fn(err : !u32) : str { // pure function
    match err {
    01 => return "operation not permitted";
    09 => return "bad file descriptor";
    13 => return "permission denied";
    17 => return "file exists";
    _  => return "generic error exit code";
    };
};

// code from main.ms
use io;

pub main = fn() : unit \ io {
    res = io::write(io::stdout, "mornin' sailor!\n");
    match wrap(res) {
    e : str => fmt::panl(e);
    _ => _;
    };
};

pub wrap = fn(status : unit ! u32) : unit | str {
    match status {
    err : !u32 => return io::etos(err); // etos is pure, no need for effect tags
    _ => return _;
    };
};
```
this code would not compile if any function that calls an impure function was not tagged as impure with the coresponding effect.

effects can be grouped together in-line using the `&` operator or hidden behind a local effect tag. for example, you can combine two module effects, `io` and `mem` doing `my_eff = io & mem`.

# linear types
a linear type is needed whenever you allocate memory or if you have to follow the pattern create-use-dispose. once created, a linear type must be used once, only once and at least once. "using" it is either copying it when assigning to another variable (and creating a new linear type), passing it to another function that accepts a linear objcet or returning it to the higher stack frame. once used, a linear object is consumed and cannot be used anymore.

when you pass it to a function that accepts a linear object, it cannot be returned, but it still must be either copied or passed to another function, so then it may be consumed. the following example explains it:
```rust
use mem;

append = fn(obj : []u32, val : u32) : []u32 {
    mut copy = obj; // obj is immutable, so in order to change it, we copy its borrowed value
    copy[copy.len - 1] = val;
    return copy; // this is allowed only because `copy` is a borrowed value
};

consume = fn(obj : @[]u32) : @[]u32 {
    copy = obj; // `obj` is consumed and `copy` is a new linear object

    // from now on, you can't use `obj` anymore

    return copy; // returning is allowed once `copy` is a new, not-yet-consumed linear object
};

pub main = fn() : unit \ mem {
    mut arr = mem::alloc([ 1, 2, 3, 5, 7 ], [6]u32)!; // alloc returns a new linear object
    arr[5] = append(arr, 11); // not consuming it once append doen't accept a linear object
    new_arr = consume(arr); // despite being the same allocated memory chunk, new_arr is a new instance of a linear object

    // from now on, you can't use `arr` anymore

    mem::free(new_arr); // consumes the array and frees the memory chunk
    
    // from now on, you can't use `new_arr` anymore
};
```

# undefined behavior and compilation settings
TODO

# ratios
ratios are a built-in data structure that is 64-bit wide and caries 4 values, 1 bit for its signal, and 3 values of 21 bytes each. these 3 last values are the integer value, the numerator and the denominator, respectively. the integer and numerator values can be any value from 0 to 2^21 -1, i.e. from 0 up to 2097151 or `0o7777777`. the denominator, in the other hand, can't be 0, so the value in memory is always incremented by 1, making it range from 1 to 2097152. these numbers are not twos's complement encoded to increase numerical length, just like floating point codification does.

- the biggest positive number possible to be represented is 2097151, and the "biggest" negative number is -2097151.
- the smallest positive number possible to be represented is 1 / 2097151 or 0.000000477, and the smallest negative number is -1 / 2097151 or -0.000000477.

note that there's no syntax for representing ratios as decimal numbers, only by fractions (hence the name ratios).

# trivia
- the official mascot of the moss programming language is the vietnamese mossy frog.

    ![image credit: Matthijs Kuijpers/Alamy](https://i0.wp.com/www.australiangeographic.com.au/wp-content/uploads/2020/05/moss-frog.jpg?resize=300%2C176&ssl=1)
    
    a picture of the said frog. we still lack an official stylized icon. image credit: Matthijs Kuijpers/Alamy

- the name moss is due to the fact that moss are a simple kind of plant that operate by simple rules and is mostly isolated from their neighbors (execpt when reproducing), but together they make long covers of a beautiful moist green. moss can also integrate with algae and produce lichens. the programming language moss is a small language that operates by simple rules and builds code from small isolated units of functions that can be composed together (sometimes with external, low-level code) and build beautiful mossy code.

- the `putf`/`putfl` functions from the `fmt` submodule of the lime library, when called with no arguments, prints "fox!" for both quick debugging and because of a joke I saw once on internet and I can't find again (probably on twitter or social.linux.pizza).