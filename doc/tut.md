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
this is a list of the 30 tokens used as keywords for the language and as such cannot be used as variable names:
| encapsulation | types                | control flow       | miscellany    |
| ------------- | -------------------- | ------------------ | ------------- |
| `use`         | `u8, u16, u32, u64`  | `if, else, match`  | `mut`         |
| `pub`         | `i8, i16, i32, i64`  | `for, next, break` | `test`        |
|               | `rat, unit`          | `yield, return`    | `is, and, or` |
|               | `fn, uni, rec, type` | `defer`            |               |

# types and variables
these are all primitive and composite types in moss.
```rust
u8, u16, u32, u64       // unsigned integers
i8, i16, i32, i64       // signed integers
rat                     // ratios
rec                     // records
uni                     // tagged unions
unit                    // "nothing" type
```

## numbers and ratios
moss doesn't support floats by default, but instead ratios. that means your divisions results in an integer part and a ratio. these all are valid numerical values:
```rust
123_456 : u64;      // 123456
99 * 99 : i64;      // 9801
0o77777 : u16;      // 32767
0x0ff80 : i16;      // -128
0b11010 : u8;       // 26
81 / 27 : i8;       // 3
-1 / 12 : rat;      // -(1/12)
```

## strings
moss has no special type for strings. they are represented as `[]u8`, once they are an array of bytes. string literals, ion the other hand, are quite unique. they are not null terminated and are UTF-8 encoded. they can't be operated on, but are mutable values.
```rust
foo = "mornin'";            // immutable value and namespace
mut bar = " sailor!!";      // mutable value and namespace

bar[bar.len - 1] = '\n';    // all arrays have a `len` field indicating their length
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

## declaration, definition assignment and type casting
```rust
mut foo : u32;      // delcaration of a mutable value
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
a = 42 + 7 - 1;                 // the type was inferred (u32)
c = 5 * (42 + 3): u16;          // no operator precedence, use parenthesis to enclose an expression
```
* note the casting affects the whole expression. if you need to cast only one value, do `(foo : type)`

# records
also called "structs" by other languages, these are collections of data whithin fields of a single data structure.
```rust
type dog = rec {
    age   : u8,
    name  : []u8,
    owner : []u8,
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
type my_uni = uni u32 | []u8;
...
x = 55: my_uni;
match x {
    u32 => fmt::putl("x is an integer!")!;
    str => fmt::putl("x is a string!")!;
};
```
a match block can also be use ranges when matching values.
```rust
x = 4;
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
for i = 2 .. 20 {
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

num = [ 2, 3, 5, 7, 11, 13, 17, 23 ];
for n .. num {
    fmt::putfl("{}", n)!;
};
```
* note that, contextually, `next` is more logical than `continue`, once you want skip to the next interaction, not continue on the current one.

you even can use parallel assignment for a shorthand for nested loops.
```rust
for c = 0 .. 127; r = 0 .. 127 {
    z = c + r;
};
```
the previous example is tha same as:
```rust
for c = 0 .. 127 {
    for r = 0 .. 127 {
        z = c + r;
    };
};
```

# unions, error handling and pattern matching
moss has no exception handling. everything that can go wrong is dealt simply as another kind of return value. these types are a special kind called error types. these can be defined defining unions with an error option using a bang. when a function can return an union tagged as an option, it must be handled with a match block, the propagation operator `?` or by the assertion operator `!`.
```rust
use fmt;

type int = uni i32 ! u8;

pub main = fn() u32 \ fmt {
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

# named returns
functions, just as can have named parammeters, can a named return value.
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

type person = rec {
    name = "bob",   // these will be the default values of these fields when instantiating the `person` record
    age  = 18: u32
};
```

# zero values
all unassigned variables will start with its zero corresponding value depending on its type:
- u8, u16, u32, u64, i8, i16, i32, i64, rat: 0
- str: ""
records fields are set to their respective zero values as well or the default value if set. unions are the only objects that must be initialized, once there is no objectively correct type to inherit the zeroed value.

# lists and ranges
## syntax
lists need a size, a type and a body. a size can be given or deduced by context. a body may or may not be initialized explicitly (being set to the default zero of tye type if not).
```rust
foo = [1, 2, 3, 4]: [4]u32;                 // explicit size
bar = ["mia", "chloe", "liam", "finn"];     // context-deduced ([4]str)
egg : [8]i64;                               // all 8 items set to 0
```

you can also define ranges when assigning to lists or even set default values to all members.
```rust
all_ones = [1...]: [32]u32;                 // fill all 32
mytenths = [10...; 5]: [10]u32;             // every 5th number, starting from 10
all_even = [0 .. 10; %2 == 0];              // all numbers from 0 up to 10 that are even
```
* note that in `all_even`, the `%2 == 0` is a rule for the filling. only n % 2 == 0 will be assigned (up to 10).

# effect system and modules
TODO

# linear types
TODO

# undefined behavior and compilation settings
TODO

# ratios
TODO

# trivia
- the `putf` function from the `fmt` submodule of the lime library, when called with no arguments, prints "fox!" for both quick debugging and because of a joke I saw once on internet and I can't find again (probably on twitter or social.linux.pizza).