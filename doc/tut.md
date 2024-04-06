# hello world!
a simple demonstration hello world code in moss.
```rust
    mod demo;
    io := use lime.io;

    pub main := fn() io::cli => nil {
        io::putl("mornin' sailor!")!;
    };
```

# lexical elements and literals
## comments
moss supports single and multiple commented lines of code, including nested blocks.
```
    ## this is a comment
    #--
        this is a multiple line comment
        and the fallowing
        #--
            is a nested commented block
            of text in moss
        --#
    --#
```

## numbers and ratios
moss doesn't support floats by default, but instead ratios. that means your divisions results in an integer part and a ratio. these all are valid numerical values:
```rust
1
-1431414
0x245235
0o773127
0b100010
1/3
-1/12
```

## strings
strings in moss caries its length within its bites, in contrast with c-like ones, which are null terminated. strings are also immutable by default and 8-bit/ASCII encoded.

### scape chars
these are the only supported scaped-characters in moss.
- `\t` for tab
- `\b` for backspace
- `\a` for bell
- `\r` for carriage return
- `\n` for line feed
- `\\` backslash
- `\'` single quote
- `\"` double quote
* note that there are no backwards compatibility with legacy stuff like vertical tab. formated printing have its own special set of scape chars (that also includes these listed above).

## reserved names
this is a list of the 28 tokens used as keywords for the language and as such cannot be used as variable names:
| encapsulation | primitive types     | control flow    | miscellany   |
| ------------- | ------------------- | --------------- | ------------ |
| `mod`         | `u8, u16, u32, u64` | `if, else`      | `test`       |
| `use`         | `i8, i16, i32, i64` | `for, in`       | `and, or`    |
| `pub`         | `rat`               | `match, defer`  | `nil, is`    |
|               | `str`               | `eval, ret`     | `fn, rec`    |

# types and variables
these are all built-in types in moss.
```rust
    u8, u16, u32, u64, i8, i16, i32, i64    ## integers
    rat                                     ## ratios
    str                                     ## strings

    rec                                     ## records
    fn                                      ## functions
```

## declaration, definition assignment and type casting
```rust
    foo: u32;           ## delcaration
    bar: u64 = 42;       ## declaration and definition

    foo = 6742;         ## assignment

    bar = foo;          ## u32 is a subset of u64, no need to explicit casting
    foo += bar: u32;    ## explicit casting and addition operator, because an u64 value can overflow an u32

    egg: i64 = -55;
    foo = egg: u32;     ## casting from bigger to lower size means modulo dividing the value, casting signed to unsigned means absolute value
```

# expressions and operators
```rust
    a: u32 = 42 + 7 - 1;        ## addition and subtraction
    b: u32 = 8 * 3 / 2 % 3;     ## multiplication, division and modulo
    c: u32 = { 42 + 3 } * 5;    ## no operator precedence, use curly brackets to enclose an expression
```

# records
also called "structs" by other languages, these are collections of data whithin fields of a single data structure.
```rust
    dog :: rec {
        age: u8,
        name: str,
        breed: str,
        owner: str,
    };
```

# control flow
these are the control flow blocks that can be used in moss.
## if-else blocks
```rust
    if x: u32 = 5 * 5; x > 64 {
        io::putl("5^2 is bigger than 8^2")!;
    } else if x > 16 {
        io::putfl("5 squared is greater than 4 squared by a factor of {} units", x - 16)!;
    } else {
        io::putfl("5 squared is {}", x)!;
    };
```
* note that all blocks must have a body with brackets, but there's no parenthesis enclosing the evaluated portion.

## match blocks
match blocks works both as a switch block and a pattern matching block. it can check the value or the type of a given variable. the distinction is done by checking if the argument is a tagged union and if the match cases are values or types.
```rust
    my_uni :: u32 | str | nil;
    x: my_uni = 55;
    match x {
        u32 => io::putl("x is an integer!")!;
        str => io::putl("x is a string!")!;
        nil => io::putl("x is nothing!")!;
    };
```
a match block can also be use ranges when matching values.
```rust
    x := 4;
    match x {
        0    => io::putl("x is zero")!;
        1..9 => io::putl("x is under 10")!;
        nil  => io::putl("x is bigger or equal to 10")!;    ## nil means any case
    };
```
* note that there's no need to use break in either of these uses.

or even, match can be used as a long sequence of if-else blocks:
```rust
    x := 'v';                                                           ## literal chars are u8 values
    match {                                                             ## empty match stands for `match true`
        x == 'a' .. 'z' => io::putl("x is a lowercase rune")!;          ## comparison can be used with ranges
        x == 'A' .. 'Z' => io::putl("x is a uppercase rune")!;
        x == '0' .. '9' => io::putl("x is a numeral")!;
        nil => {
            if x == '.' {
                io::putl("x is a dot!")!;
            } else if x == ',' {
                io::putl("x is a colon!")!;
            };
        };
    };
```

## for loops
for loops are the only available kind of loop in moss. they work as a normal for loop, a while loop and a foreach loop in other languages. here's all its uses:
```rust
    ## no incrementing or decrementing, we use ranges
    for i := 2..=20 {
        io::putfl("{}", i)!;
    };

    for r < 100 {
        r = some_funky_fn(r);
        if r == 55 {
            next; ## equivalent to `continue` in other languages
        } else if r == 67 {
            break;
        };
    };

    num := [ 2, 3, 5, 7, 11, 13, 17, 23 ];
    for n in num {
        io::putfl("{}", n)!;
    };
```
* note that, contextually, `next` is more logical than `continue`, once you want skip to the next interaction, not continue on the current one.

you even can use parallel assignment for a shorthand for nested loops.
```rust
    for c = 0..<128; r = 0..<128 {
        nil; ## empty statement
    };
```
the previous example is tha same as:
```rust
    for c = 0..<128 {
        for r = 0..<128 {
            nil;
        };
    };
```

# unions, error handling and pattern matching
moss has no exception handling. everything that can go wrong is dealt simply as another kind of return value. these types are a special kind called error types. these can be defined by marking an type with a bang. when a function can return an error or a value, it must be handled by a union type (usually `return_val | err`) or handled by the propagation operator `?`.
```rust
    mod demo;
    io := use lime.io;

    nan :: !nil;
    int :: i32 | nan;

    pub main := fn() io::cli => nil {
        res := myfn(7, 2); ## returns an instance of int

        match res {
            int => io::putfl("7 divided by 2 is {}", r: i32)!;
            nan => io::panic("error! division by zero");
        };
        res = myfn(6, 2)!; ## the exclamation operator guarantees that the result will be not an error. if it happens, the program crashes
    };

    myfn := fn(n, d: i32) => int {
        if d == 0 {
            ret nan;
        } else {
            ret n / d;
        };
    };
```
you can also use the bang as an assertion operator on `nil` values. i.e. `nil!` will make the program crash. if the function can return nil, you can aswell use the `?` operator to short-circuit and return `nil` on one of these assertions, e.g. `foo?` becomes a `ret nil` if `foo == nil`.

# named returns
functions, just as can receive multiple parammeters, can return multiple values. this is achieved with named returns.
```rust
    myfn := fn(x, y: i64) p, q: i64 {
        p = x * x + y;
        q = y * y - x;
        ret;            ## the empty return statement makes the function halt and return p and q with the current values
    };
```
when receiving these multiple return values, just assign them.
```rust
    foo, bar := myfn(6, 2);
```
you can have more return values than receivers, but not the opposite. declaring two variables with one return value is consired a syntax error.

# default values
you can set default attributions for your parameters when creating functions.
```rust
    div := fn(n, d: i64 = 1, 1) i64 { ## both parameters will be set to 1 if no argument is given
        return n / d;
    };

    person :: rec {
        name := "bob", ## these will be the default values of these fields when instantiating the `person` record
        age  := 18
    };
```

# zero values
all unassigned variables will start with its zero corresponding value depending on its type
- u8, u32, u64, i8, i32, i64, rat: 0
- str: ""

# lists and ranges
## syntax
lists need a size, a type and a body. a size can be given or deduced by context. a body may or may not be initialized explicitly (being set to the default zero of tye type if not).
```rust
    foo: [4]u32 = [1, 2, 3, 4];                     ## explicit size
    bar: [*]str = ["mia", "chloe", "liam", "finn"]; ## context-deduced
    egg: [8]i64;                                    ## all 8 items set to 0
```

you can also define ranges when assigning to lists or even set default values to all members.
```rust
    all_ones: [32]u32 = [1...];                     ## fill all 32
    mytenths: [10]u32 = [10..; 5];                  ## every 5th number, starting from 10
    all_even: [*]u64[0..=10; %2 == 0];              ## all numbers from 0 up to 10 that are even
```
* note that in `all_even`, the `%2 == 0` is a rule for the filling. only n % 2 == 0 will be assigned (up to 10).

# effect system
TODO

# undefined behavior and compilation arguments
TODO

# ratios
TODO

# trivia
the `putf` function from the io submodule of the lime library, when called with no arguments, prints "fox!" for both quick debugging and because of a joke I saw once on internet and I can't find again (probably on twitter or social.linux.pizza).