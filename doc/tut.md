# disclaimer
until this branch is merged, some of these features must be unavailable or be considered invalid syntax.

# syntax
## comments
```rust
// single lined
/*
    multi-lined
    // nested single lined
    /*
        nested multi-lined
    */
*/
```
## variables
except for strings, all literals must be explicitly casted to some type. on expressions, the casting can be omitted of literals if at least one of the members are typed.
```rust
x = 128 : u32;
y = "mornin' sailor!\n";
z = [ 1, 2, 3, 4 ] : [*]u32;
w = [ 5... ] : [12]u64;
```
all variables are immutable and can have computed values at global scope. 

## operators and expressions
moss has no operator precedence. everything is parsed concatenatedly from left to right.
```rust
x = 6 : u32;
y = 7 : u32;
z = x * y;

if z == (x * y) {
    fmt::putl("runs")!;
};

if z == x * y {
    fmt::putl("doesn't run")!;
};
```


## literals
moss allows digit separators, hex, octal and binary literals. there are also character literals
```rust
x = 0xff5e32 : u64;
y = 1_000_555_789 : u64;
z = 0b101101 + 0o77115 : u32;
w = 'a' + 1 : u8;
```
for floating points, we use ratio literals:
```rust
x = 1:2 : f32; // 1.5f
y = 355:113 : f64; // 3.1415f
```

## string escape chars
`\t` - horizontal tab
`\b` - backspace
`\a` - bell
`\r` - carriage return
`\n` - line feed
`\f` - form feed
`\0` - null character
`\\` - escape character
`\'` - single quote
`\"` - double quote

## functions
```rust
pub main = fn() unit {
    x = sum(4, 5);
    t = div_pls_one(x, 3);
};

sum = fn(x : u32, y : u32) u32 {
    x + y
};

div_pls_one = fn(x : u32, y : u32) u32 {
    if y != 0 {
        div = x / y;
        div + 1
    } else {
        1
    }
};
```
note that:
- public functions are visible for FFI.
- removing the semicolon makes the statement as a return value. the function returns the if block, which in turn returns either `div + 1` or `1`

## if-else blocks
```rust
if x = 9 : u32; x == y or x > 4 {
    ...
} else if x == 3 and y >= 2 {
    ...
} else {
    ...
};
```
boolean operators are lazily evaluated.

## lists
TODO

## records
```rust
dog : rec {
    age : u8,
    name : str,
    breed = "golden retriever",
    owner : str,
};

woofy = dog {
    age = 2,
    name = "woofy",
    owner = "bob",
    ...
};

vect : {
    x : f64,
    y : f64,
    z : f64,
};

up = vect { y = 1, ... };
lt = vect { x = -1, ... };
velocity = up * lt * 1:2;
```

## tagged unions
```rust
some : u64 | unit;
token : str | u64 | i64 | unit;
```

## error values
```rust
use fmt;

pub main = fn() void {
    ok = div(5, 7)!; // crashes on error
    err = div(2, 0) ? fmt::fail("division by zero"); // runs on error
};

div = fn(x : i64, y : i64) !i64 {
    r = if y != 0 {
        x / y
    } else {
        fail
    };
    r
};
```
errors cannot be ignored, but can be returned:
```rust
div2 = fn(x : i64) !i64 {
    div(x, 2)
};
```

## match block
```rust
use fmt;

iora : u64 | str;

pub main = fn() void & fmt {
    x = "hi!" : iora;
    match x {
    u64 : fmt::putl("x is an integer")!;
    txt : str : fmt::putfl("x is %s", txt)!;
    };

    match x as txt {
    "hello" : fmt::putl("heya!")!;
    "hi!" : fmt::putl("hello!")!;
    _ : fmt::putl("hoy!")!;
    };
};
```

# type system
## primitive types
- numerical types: `u8, i8, u16, i16, u32, i32, u64, i64, f32, f64`
- strings: `str`
- `unit` and `void` types
there are no boolean types.

## unit and void types
the unit type has only one valid value, `[]` and is implicitly returned by all unit functions. on the other hand, void functions does not return anything. actually, they terminate the program with an exit code of 0.
```rust
pub main = fn() void {
    x = 4 : u32;
    if x == 5 {
        exit();
        // cannot run any code after that
    };
    y = nothing();
};

exit = fn() void { };
nothing = fn() unit { [] };
```

## lists and strings
lists have built-in functions for iterating on their items. all functions are pure:
```rust
text = "hello!";
lower = text.map(fn(c : u8) u8 {
    if 'A' <= c <= "Z" {
        c ^ 0x40
    } else {
        c
    }
});

alpha = txt.filter(fn(c : u8) u8 {
    'A' <= c <= 'z'
});

list = [ 1, 2, 3, 4, 5, 6, 7, 8 ] : [*]u32;
sum = list.foldl(fn(ac : u32, itm : u32) u32 {
    ac + itm
});
```
all the available functions:
- map
- fmap
- foldl/foldr
- reduce
- filter
- index
- inter
- head? (only for lists)
- tail? (only for lists)

## division and decimal numbers
moss uses IEEE 754 standard for floating point numbers and allows only rational representations for floating point literals. in the case of integer division by zero, the result is also zero to avoid undefined behavior.
```rust
x = 1:4 : f32;  // 0.25f
y = x + 4 / 3;  // 1.25f (0.25 + 1)
z = y + 1:2;    // 1.75f
```
note that `1:4` itself carries no typing and must be explicitly casted to either `f32` or `f64`. in the remaining expressions, the type for the literals is deduced by the typed value (`x`);

## modules and effects
impure functions are those who produce effects. these must be tagged with the source of their impure code, often modules:
```rust
use os;
use fmt;

pub main = fn() void & fmt & os {
    file = os::open("data.txt", os::RW) ? fmt::fail("file not found");
    data = os::read(file)!;
    dump(data);
};

dump = fn(data : os::stream) unit & fmt {
    data' = os::lines(data);
    data'.map(fn(line : str) unit & fmt {
        fmt::putl(line)!;
    });
};
```
* note that `os::open` and `os::read` as well as `fmt::fail` and `fmt::putl` are all impure functions, which make `main`, `dump` and the lambda passed to the `map` function impure functions, on the other hand, `os::lines` is pure and `map` itself ony becomes impure if the given predicate is also impure.