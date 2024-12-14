# disclaimer
until the compiler is at 1.0, some of these features might be unavailable, be considered invalid syntax, .

# syntax
moss uses c-like (multi-lined) comment blocks with support for nested blocks.
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

## functions, variables and types
moss is a functional programming language with focus on concise syntax and grammar, so defining functions, types and variables look the same:
```rust
pi = 355:113 f64;       // global floating point variable

pub main = fn() void {  // public function of return type void
    x = 124 u32;        // local variable of type u32
};

dog = rec {             // a record definition
    name str,
    owner str,
    breed = "just a silly boi"
};
```
global variables are evaluated at compile time and can even use function calls on its expressions as long as these functions are pure. see more on [effects section](#effects).

## first-class functions
moss also support first-class functions, for instance:
```rust
int_map = fn(l []u32, p fn(u32) u32) []u32 {
    for i .. l {
        p(i)
    }
};

mul_by_two = fn(i u32) u32 { i * 2 };

predicate = mul_by_two;

pub main = fn() void {
    arr = [ 1, 2, 3, 4, 5 ] u32;
    arr' = int_map(arr, predicate);
};
```
* see more about the `for` constructor in the [iterators section](#iterators).

## numerical literals
moss allows digit separators at any place, decimal, hexadecimal, octal and binary literals, and has no concept of decimal number notation (see more on [floating points section](#floating-points)).
```rust
x = 1_000_000_000 u64;
y = 0x_77_f3_63 u32;
z = 0o1117315 u16;
w = 0b1_1000 u8;

a = 3:4 f64;
b = 91:31 f32;
```

## modules
every file in moss is a standalone module which can be required by other modules. when a said file is required, is imperative it has no main function defined, even if it's private.
```rust
// foo.ms
pub div = fn(x i64, y i64) i64 {
    x / y                           // no semicolon makes it a return statement
};
```
```rust
// main.ms
use foo;

pub main = fn() void {
    x = foo::div(4, 5);
};
```
note that you cannot use a "import all" syntax; all extern fields must be prefixed with its origin module.

# type system
moss is strongly typed but also does a little of type inferring to avoid repetition. that means all numerical literals must be casted to some type when defining a variable (no default `int` type), but you don't have to cast every single untyped value when dealing with something already typed.
```rust
x = 6742 u32;   // untyped literal casted to u32
y = x;          // y is also an u32
z = y + 1;      // 1 is implicitly casted to u32 as well
```
moss have the following primitive types:
```rust
u8, u16, u32, u64   // unsigned integers
i8, i16, i32, i64   // signed integers
f32, f64            // floating points
str                 // string type
void                // void "never" type
unit                // unit "empty" type
```
moss have no boolean types. address for boolean evaluation in [this section](#ifelse-blocks-and-truthy-and-falsy-values).

the `void` type means that this function does not return anything. in fact, it's a termination function. all void functions halt the program at the end of the scope. that's why the main function is a void function.
```rust
foo = fn() void { };
bar = fn(x u32) u32 {
    if x == 4 {
        foo();
        // no code can be used from this point
    } else {
        x + 4
    };
};
```

the `unit` type is an "empty" type in the sense it is a type with a single, non operable type which serves only as a no-return value for impure functions or even as an invalid case for [unions](#union-type-and-match-block).
```rust
egg = fn() unit { };
buz = fn() u32 {
    x = egg();
    if x == _ {    // the unit literal is `_`
        4
    } else {
        8
    }
};
```

## floating points
moss supports floating point numbers, but favors mathematical elegancy over arbitrary values, that's why floating literals use a ratio signature instead of a decimal place approach. this also comes in favor of keeping alway implicit rounding commonly found in floating point arithmetics with decimal place literals. this also makes clearer the distinction between integer division and floating point division. moss uses IEEE 754 standard for floating point numbers.
```rust
pi = 355:113 f64;   // approximately 3.1415
third = 1:3 f32;    // approximately 0.3...
```

## if/else blocks and truthy and falsy values
if/else blocks are branching statements that can both just run code and be an assignable expression.
```rust
x = 6 u64;
y = 7 u64;

if x * y == 42 and x > y {
    io::putl("true!")!;
} else {
    io::putl("false!")!;
};

z = if x + y > 12 {
    x + 1
} else {
    y + 1
} u32;
```
for these blocks, everything but unit values, zero and empty strings/arrays are considered truthy, otherwise considered falsy.
```rust
x = "";
y = "hiii";

if x {
    io::putl("won't run")!;
} else if y {
    io::putl("runs")!;
};

if _ or 0 {
    io::putl("also won't run")!;
} else if 4 {
    io::putl("also runs")!;
};

if not 0 {
    io::putl("runs too!")!;
};
```
also, all boolean expressions are lazily evaluated.

## union type and tag matching
a tagged union is a unit of data than hold a tag indicating its type and its actual value. it cannot be operated nor casted directly, but can be matched against all its variants.
```rust
iora = union i64 | str;
...
x = "hi" iora;

num = match x {
    n i64 => n
    _ => 0
};

txt = match x {
    t str => t
    _ => ""
};
```

## effects
the root of all effects in moss -- i.e. impure code -- is implemented behind the built-in module `rt` (written in assembly). all functions that use this module must include its name as a tag. similarly, all modules that implement impure functions require the caller to add the module name as an effect tag. for instance, the `io` module:
```rust
// io.ms
use rt;

pub put = fn(data str) unit & rt {
    rt::puts(rt::stdout, data);
};
```
```rust
// main.ms
use io;

pub main = fn() void & io {
    io::put("mornin' sailor!");
};
```
effects can also be chained:
```rust
use fs;
use io;

pub main = fn() void & io & fs {
    io::put("what's your name?\n> ");
    name = io::get(128);

    if not name {
        io::put("please say your name!\n");
    } else {
        file = fs::open("out.txt", fs::RWONLY)!;
        fs::putl(file, "hello, " + name + "!");
        fs::close(file);
    };
};
```

## iterators
iterators are constructors able to iterate over arrays of items and building new objects from them. they work pretty much like an in-line recursive function. the most basic usage is the same of a normal "for each loop".
```rust
items = [ 2, 3, 5, 7, 11, 13 ] u32;
for i .. items {
    io::putfl("%d", i)!;
};
```
this code iterates over all items in the `items` list and will print them. you can also map or filter lists in the same fashion:
```rust
list = [ 1, 2, 3, 4, 5, 6, 7, 8 ] u32;
even = for i .. list {
    if i % 2 == 0 {
        i
    }
};
twice = for i .. list {
    i * 2
};
```
you can also fold/reduce lists using accumulators:
```rust
list = [ 1, 2, 3, 4, 5 ] u32;
sum = for a = 0; i .. list {
    a + i
};
```
in this case, the returned value must be the new value of the accumulator. you can even use multiple accumulators by returning tuples of values:
```rust
list = [ 1, 2, 3, 4, 5 ] u32;
odd_sum, even_sum =
    for o, e = 0, 0; i .. list {
        if i % 2 == 0 {
            (o, e + i)
        } else {
            (o + i, e)
        }
    };
```
* note that there's no way of doing `while true` loops with this constructor, therefore they always terminate.