# hello world!
a simple demonstration hello world code in moss.
```rust
use lime;
fmt = lime::fmt;

pub main = fn() : lime => nil {
    fmt::putl("mornin' sailor!")!;
};
```

# lexical elements and literals
## comments
moss supports single and multiple commented lines of code, including nested blocks.
```rust
// this is a comment
/*
    this is a multiple line comment
    and the fallowing
    /*
        is a nested commented block
        of text in moss
    */
*/
```

## reserved names
this is a list of the 32 tokens used as keywords for the language and as such cannot be used as variable names:
| encapsulation | primitive types     | control flow       | miscellany    |
| ------------- | ------------------- | ------------------ | ------------- |
| `use`         | `u8, u16, u32, u64` | `if, else, match`  | `def, mut`    |
| `pub`         | `i8, i16, i32, i64` | `for, next, break` | `test`        |
|               | `rat, str, nil`     | `eval, ret`        | `is, and, or` |
|               | `fn, rec, uni, err` | `defer`            |               |

# types and variables
these are all primitive and composite types in moss.
```rust
u8, u16, u32, u64       // unsigned integers
i8, i16, i32, i64       // signed integers
rat                     // ratios
str                     // strings
nil                     // void, null, empty, you choose
rec                     // records
uni                     // tagged unions
err                     // error types
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
strings in moss caries its length within its bites and are not null terminated. strings are also immutable by default and UTF-8 encoded.
```rust
use core;

foo = "mornin'";            // immutable value and namespace
mut bar = " sailor!";       // immutable value but mutable namespace

len = core::len(foo);       // returns 7: u64
all = foo + bar;            // results in "mornin' sailor!" (length of 15)
```

and these are the only supported escape-characters in moss.
- `\t` for tab
- `\b` for backspace
- `\a` for bell
- `\r` for carriage return
- `\n` for line feed
- `\\` backslash
- `\'` single quote
- `\"` double quote
* note that there are no backwards compatibility with legacy stuff like vertical tab. formated printing have its own special set of escape chars (that also includes these listed above).

## declaration, definition assignment and type casting
```rust
mut foo : u32;      // delcaration of a mutable value
mut bar = 42: u64;  // declaration and definition

foo = 6742;         // assignment

bar = foo;          // u32 is a subset of u64, no need to explicit casting
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
def dog = rec {
    age   : u8,
    name  : str,
    breed : str,
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
def my_uni = uni u32 | str | nil;
...
x = 55: my_uni;
match x {
    u32 => fmt::putl("x is an integer!")!;
    str => fmt::putl("x is a string!")!;
    nil => fmt::putl("x is nothing!")!;
};
```
a match block can also be use ranges when matching values.
```rust
x = 4;
match x {
    0       => fmt::putl("x is zero")!;
    1 ..= 9 => fmt::putl("x is under 10")!;
    _       => fmt::putl("x is bigger or equal to 10")!;   // nil means any case
};
```
* note that there's no need to use break in either of these uses.

or even, match can be used as a long sequence of if-else blocks:
```rust
x = 'v';                                                            // literal chars are u8 values
match {                                                             // empty match stands for "match true"
    x == 'a' ..= 'z' => fmt::putl("x is a lowercase rune")!;          // comparison can be used with ranges
    x == 'A' ..= 'Z' => fmt::putl("x is a uppercase rune")!;
    x == '0' ..= '9' => fmt::putl("x is a numeral")!;
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
for i = 2 ..= 20 {
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
for n ..= num {
    fmt::putfl("{}", n)!;
};
```
* note that, contextually, `next` is more logical than `continue`, once you want skip to the next interaction, not continue on the current one.

you even can use parallel assignment for a shorthand for nested loops.
```rust
for c = 0 ..< 128; r = 0 ..< 128 {
    nil; // empty statement
};
```
the previous example is tha same as:
```rust
for c = 0 ..< 128 {
    for r = 0 ..< 128 {
        nil;
    };
};
```

# unions, error handling and pattern matching
moss has no exception handling. everything that can go wrong is dealt simply as another kind of return value. these types are a special kind called error types. these can be defined using the `err` keyword. when a function can return an error or a value, it must be handled by a union type (usually `return_val | err`) or handled by the propagation operator `?`.
```rust
use lime;
fmt = lime::fmt;

def nan = err nil;
def int = uni i32 | nan;

pub main = fn() lime => nil {
    mut res = myfn(7, 2);

    match res {
        int => fmt::putfl("7 divided by 2 is {}", r: i32)!;
        nan => fmt::panic("error! division by zero");
    };
    res = myfn(6, 2)!; // the exclamation operator guarantees that the result will be not an error. if it happens, the program crashes
};

myfn = fn(n, d: i32) int {
    if d == 0 {
        ret nan;
    } else {
        ret n / d;
    };
};
```
you can also use a bang for an assertion  on `nil` or `err` values. i.e. `nil!` will make the program crash. if the function can return nil, you can as well use the `?` operator to short-circuit and return `nil` on one of these assertions, e.g. `foo?` becomes a `ret nil` if `foo == nil`.

# named returns
functions, just as can receive multiple parammeters, can return multiple values. this is achieved with named returns.
```rust
myfn = fn(x, y: i64) p, q: i64 {
    p = x * x + y;
    q = y * y - x;
    ret;            // the empty return statement makes the function halt and return p and q with the current values
};
```
when receiving these multiple return values, just assign them.
```rust
foo, bar = myfn(6, 2);
```
you can have more return values than receivers, but not the opposite. declaring two variables with one return value is consired a syntax error.

# default values
you can set default attributions for your parameters when creating functions.
```rust
div = fn(n, d = 1, 1: i64) i64 { // both parameters will be set to 1 if no argument is given
    ret n / d;
};

def person = {
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
all_even = [0..=10; %2 == 0];               // all numbers from 0 up to 10 that are even
```
* note that in `all_even`, the `%2 == 0` is a rule for the filling. only n % 2 == 0 will be assigned (up to 10).

# effect system
TODO

# linear types
TODO

# undefined behavior and compilation settings
TODO

# ratios
TODO

# trivia
- the `putf` function from the `fmt` submodule of the lime library, when called with no arguments, prints "fox!" for both quick debugging and because of a joke I saw once on internet and I can't find again (probably on twitter or social.linux.pizza).