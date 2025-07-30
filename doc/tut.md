# index of topics
## syntax
- [declarations](#declarations)
- [functions](#functions)
- [variables](#variables)
- [types](#types)
- [expressions](#expressions)
- [statements](#statements)
- [modules](#modules)

## type system
- [types](#types)
- [mutability](#mutability)
- [partial types](#partial-types)
- [error assertion](#error-assertion)
- [error and propagation](#error-and-propagation)
- [memory arenas](#memory-arenas-and-memory-allocation)

## effects and FFI
- [modules](#modules)
- [effects](#effects)
- [FFI declarations](#FFI-declarations)

# cheatsheet
## declarations
- `[pub] fn <function_name>([ [mut] <parameter_name> <parameter_type> ]* [<optional_variadic> <variadic_type> ...] ) <return_type> = [optional_tag] <scope_or_FFI>`
- `let [mut] <variable_name> [optional_type] = <expression>`

## allocation
- `mem <arena_name> | <size_of_arena> { ... } [optional_error_assertion]`
- `= new [optional_assertion_operator] <value> @ <arena_name>`
- `= <value> .. <optional assertion_operator] <value> @ <arena_name>`

## modules
- `<module_binding> mod = use <string_of_path_to_file>`
- `<module_name>::<module_field>`

# declarations
lichen makes a distinction between global and local variables, mutable namespaces and values, constant (compile-time known) and dynamic (runtime known) values.

global variables must have: a constant namespace (identifier), an explicit type, and a value known at compile-time:
```rust
foo = 4; // invalid
pi f64 = 355 / 113; // invalid. the expression cannot be executed at compile-time
stdout u32 = 1; // valid
```
all global declarations, such as constant variables, functions and types may be marked as public in order to be accessed from other files:
```rust
pub foo u64 = 64;

pub type person = record {
    name str;
    age u8;
};

pub fn empty() unit = {};
```

local variables, on the other hand, can have an expression as a value and even be reassigned when tagged as mutable:
```rust
let x = 4 u32;
let y = x;
let mut z = x + y;
z = z * 2;
```
see more about mutability in [this section](#mutability).

functions are a bit similar but not quite. as expected, all global declarations are immutable, and this includes functions. but they may mark an argument as mutable in order to change it during execution.
```rust
fn foo() u32 = {
    return 4;
};

fn bar(x u32) u32 = {
    return x + y;
};
```
a function may perform observable effects: opening files, writing to terminal, or mutating taken arguments. all of this are considered effects, and any function that produces effects must be given a tag that indicates this effect:
```rust
type foo = {
    bar u32;
};

// x is marked as mutable, then the
// function is marked with a given tag
// of `a` to indicate it may or may not
// change x's value. the name is purely
// for documenting purposes
fn change(mut x foo, y u32) unit = a {
    x.bar = y;
};

fn take_and_change(mut x foo, y u32) u32 = b {
    let old = foo.bar;
    foo.bar = y;
    return old;
};

// calling an impure function requires
// the function that calls it to also
// declare the same effect tags
pub fn main() void = a & b {
    let mut z = foo { bar = 4 };
    change(z, 5);
    let old = take_and_change(z, 4);
    test z.bar == old + 1;
};
```
you can use any given valid namespace as a tag and it has no semantical meaning other than tagging it with a named effect.

see more about the effect system in [this section](#effects).

all identifiers (variables, functions, types) may use prime notation (ending with one or more single quotes). in mathematics, a prime of something means "another one of these, but not the same". these are useful for related values but not the same type. in lichen, variables cannot be shadowed; each identifier must be unique within its scope. this is to avoid accidental context overwrite or confusion when reading the source code:
```rust
let number = "42";
let number' = 42 u32;
let number'' = 40 + 2 i32;
```
number of primes has no semantic meaning: foo' and foo'' are simply separate identifiers.

# functions
functions may or may not take arguments, but always return something (except for the `void` type). even if it's nothing i.e. the `unit` type. they can be called or passed by value. lichen doesn't have currying.
```rust
fn foo(x u32, y u32) u32 = { return x + y; };

fn bar(egg fn(u32, u32) u32, baz) u32 = {
    return egg(baz, baz * 2);
};

fn empty() unit = {};

// calling this halts the execution
fn terminal() void = {};
```
functions returning `unit` can be called and their result stored, but since unit has no value, that variable cannot be meaningfully used. a function that returns a `void` type actually halts the program, and therefore cannot be assigned to any value, once they do not return.

see more about types in [this section](#types).

functions are also required to end their scope in a semicolon, as most code paths in lichen. you may also assign a function with a FFI symbol or a function alias:
```rust
fn x(a u32, b u32) u32 = { return a * b; };
fn x'(a u32) u32 = x(a, 2);
```
on these alias, only constant values are allowed to be used, just like global variables' values.

functions may also give optional values for its parameters, that will be overwritten if a new value is provided:
```rust
fn div(x u32, y u32 = 2) u32 = { return x * y; };

pub fn main() void = {
    let a = div(10, 5);
    let b = div(4);
};
```

# variables
local variables have a special behaviour, especially considering mutability. for instance, scope declarations, function parameters and statement declarations are considered local variables, which means they can be mutable and have considerably more complex expressions assigned to:
```rust
let constant = 4 u32;
let mut nonconstant = constant + 4;
nonconstant = nonconstant * 2;
```
as shown, variables marked with `mut` can be reassigned. in the case of non-primitive types, i.e. aggregated types such as records, strings and arrays, mutability also implies in changing the value itself, as assigning to a member of a record.
```rust
type foo = record {
    bar u32;
    egg str;
};

pub fn main() void = {
    let mut buzz = foo { bar = 4, egg = "yellow" };
    buzz.bar = 6;
};
```
see more about mutability in [this section](#mutability).

variables may omit their type at declaration when the type of the assignment can be deduced. numeric literals have no intrinsic type, but can be casted freely to any numeric (and even boolean) types. they also decay to other numeric types when used on a typed expression i.e. they assume the type of the expression.
```rust
let unknown = 4; // invalid
let known = 5 u32;
let deduced = known + 1; // 1 decays to u32
```
see more about type and type casting in [this section](#type-system).

you cannot assign a void type to a variable, even if it's partial:
```rust
fn fn_void() void = {};
fn fn_err_void() !void = {};

pub fn main() void = {
    let foo = fn_void(); // not valid
    let bar = fn_err_void()!; // also not valid
};
```
see more of this in [this section](#types).

# types
lichen has a somewhat small set of primitives and derivative types. these are:
## numeric
integers and floats of varying lengths.
```rust
// unsigned types
u8, u16, u32, u64;
// signed types
i8, i16, i32, i64;
// floating point
f32, f64;
```
lichen has no default `int` or `size` types. all expressions must have explicit type and type length.

numeric literals may have digit separators and can be encoded as decimal, octal, hexadecimal and binary:
```rust
let ten = 10 u32;
let eight_two = 0o12 u32;
let alpha = 0x_00_0a u32;
let one_double_o_one = 0b10_01 u32;
```
floating points can be expressed as decimal numbers or in scientific notation:
```rust
let pi f64 = 3.1413;
let avogadro = 6.022e23;
```

## strings
lichen supports total C ffi at primitive levels, which means we support strings with fat pointers (`str`) and null-terminated strings (`cstr`), nicknamed C-strings. you can freely cast a string to a C-string, but not the other way around. a string with a fat pointer is a pointer with a length and a pointer to the actual data, casting it to a C-string means assigning only the data. strings are also the only primitive value that doesn't require a explicit casting.
```rust
let text = "something in here";
let other = text cstr; // casting
```
these are the available ascii escape sequences in lichen:
- `"\t"` for tabulation
- `"\b"` for backspace
- `"\a"` for audible bell
- `"\r"` for carriage return
- `"\n"` for line feed
- `"\f"` for section break
- `"\0"` for null character
- `"\'"`, `"\""` for escaping single/double quotes

strings can be compared by value (unlike C that compares by data pointers) using normal "equals to" operator (`==`):
```rust
let foo = "hi";
let bar = "hi";

test foo == bar; // test succeeds
```

## boolean
lichen implements booleans as purely a type enforcement, but all bool values can be casted to an integer value and vice-versa. the variants for the type are `true` and `false`, as expected.
```rust
let x = true;
let y = x u32;
test y == 1; // evaluates to true and succeeds the test

let z = 1;
let w = z bool;

test w; // also evaluates to true and succeeds
```

## partial types
all types can be optionally marked as partial, stating that this value can either be the base type or an error state (`fail` or `nomem`), as such:
```rust
let x u32 = 4; // concrete type
let y !u32 = 5; // partial type with valid data
let z !u32 = fail; // partial type as error

let x' = y!; // assert it is a valid value
let y' = z ? 0; // default to zero if z is an error
```
`fail` and `nomem` are singletons, like `true` and `false`. they have a different semantical meaning, but internally are just numbers (-1 to indicate failure and 0 to indicate a null pointer/failed allocation).

these types cannot be compared nor used on expressions, but can be asserted on their error state at any point.
```rust
fn div(x u32, y u32) !u32 = {
    if y == 0 {
        return fail;
    } else {
        return x / y;
    };
};

pub fn main() void = {
    let partial = div(4, 5);
    let unwrapped = div(2, 1)!;
    let from_var = partial!;
};
```
both bubble and assertion operators can be applied to any value of a partial type. see more about error types in [this section](#error-and-propagation).

## empty types
some types are merely semantic and do not represent actual data. these are called empty types, such as `unit` and `void`. usually, these are found in function declarations as return types.

`unit` is like "nothing, but successfully finished". it can be assigned to any variable and marked as a partial type (`!unit`), but cannot be compared nor operated on.
```rust
fn foo() unit = {}; // all scopes default to returning unit type without an explicit return

fn bar() unit = { return; }; // empty return

fn egg() unit = {
    foo();
    let x = bar();
};

fn fizz(x u32) !unit = {
    if x == 0 {
        return fail; // error type singleton
    };
};

fn buzz() !unit = {
    fizz(4)?; // error bubbling
};
```

the `void` type means "no return" in the sense a function marked as void cannot be assigned to a variable because it never returns i.e. its a terminal function, halting the code execution, as ‘never returns at all’ (like exit, panic, or fatal error). once nothing can return, marking the type as partial makes the program halt in an error exit code. the main function is marked as void once it's the entry point i.e. it never returns anything.
```rust
pub fn main() void = {
    exit_on_error();
};

fn exit_on_error() !void = {};
```
as you may also notice, no bubbling or assertion is needed or allowed on a void type, once it _never_ returns any value, even if the value is an error state. similarly, you cannot bubble from within an void function.

## arrays
arrays are a contiguous list of same-type data on memory that may be indexed. the indexing may be unsafe once we not always know if the array is big enough to accommodate given index, so lichen solves this my making all array indexing that is not constant (i.e. its index and length are known at compile-time) a partial type expression, as follows:
```rust
let constant_array []u32 = [1, 2, 3, 4, 5, 6];
let value u32 = constant_array[4]; // both array length and index are known at compile-time, resulting in a concrete type (u32)
let partial !u32 = constant_array[value]; // “the indexing is now not known at compile-time, so the result is a partial type (!u32)

mem buffer | 128 * 4 {
    let dynamic_array = new ! [128; 0, 2, 3, 7, 0...] u32 @ buffer; // array of 128 items of 4 bytes each
    let value' u32 = dynamic_array[4]!; // now the array length is not known at compile-time, resulting in a partial type again
    let partial' != dynamic_array[value]; // result is !u32 because neither index nor length are compile-time known
}!;
```
asserting or bubbling an invalid indexing casts it down to the base type instead of resulting in a partial type. you can see more about partial types in [this section](#partial-types).

as shown in the previous example, arrays may be statically defined and allocated or dynamically allocated using [arenas](#memory-arenas):
```rust
mem arena | size_in_bytes {
    let optional_array = new [1, 2, 3, 4] u32 @ arena; // results in ![]u32 because allocation may fail
    let concrete_array = new ! [2, 4, 6, 8] u32 @ arena; // allocation failure is asserted

    let size_in_items = 20 u64;
    let array_with_rule = new ! [size_in_items; 0...] @ arena; // sets all 20 items to zero
}!; // assertion for nomem failure
```
unlike strings, static arrays are contiguous segments of data, where the first 8 bytes are it's length and all subcequent bytes the array data. dynamically allocated arrays, on the other hand, are fat pointers as well. you can cast a static array into a dynamic array through _slicing_, but not the other way around:
```rust
let static_arr [8]u32 = [0...];
let dynamic_arr []u32 = static_arr[..];
let slice = static_arr[0 .. 4];
```

## records
records, as the name suggests, are records of data of varying types:
```rust
type my_record = record {
    field_1 bool;
    field_2 u32;
};

let instance = my_record { field_1 = false, field_2 = 0 }; // directly assign to all fields
let mut other instance = { ... }; // default all unassigned values to zero
other.field_1 = true;
```
mutable records can have fields reassigned, but constants can't, as a [mutability mechanism](#mutability). for a quick update on some value to help make this more ergonomic, lichen offers a _priming_ syntax, as in prime notation: "another of these things, but not the same":
```rust
let immutable = my_record { field_1 = true, field_2 = 4 };
let mut mutable = { immutable | field_1 = false, field_2 = 5 };
```
field assignment in record literals require exhaustiveness i.e. all fields must be explicitly assigned or explicitly set to be zeroed or defaulted:
```rust
type foo = record {
    bar u32,
    egg u32,
    baz u32 = 4,
};

x foo = foo { bar = 4 }; // invalid. `egg` and `baz` are left unassigned
y foo = foo { bar = 4, egg = 3, ... }; // valid. baz defaults to 4
z foo = foo { ... }; // also valid. baz is set to 4 and all other fields are set to zero
```

records can also implement subtyping as a manner of implementing some generic behaviour, often found in types like tagged unions in hare or enums in rust. except it carries all its variants in memory at all time. when using `use` in record fields, these field names become variants - assignable by type:
```rust
type person = record {
    use name str;
    use age u8;
};

pub fn main() void = {
    let mut bob person = "bob"; // implicitly assigns to `bob.name`
    bob = 42; // implicitly assigns to `bob.age`

    let name = bob.name;
    let age u8 = bob; // can be assigned as implicitly `bob.age`, deuced by the type
};
```

once assigning to and reading from requires the type matching, a record can't more than once a type as a variant, but it is safe to implement the same type as _not_ a variant. using the same example:
```rust
type person = record {
    use name str;
    use age u8;
    id str;
};

pub fn main() void = {
    let mut bob person = "bob"; // only name is a variant
    bob = 42;
    bob.id = "111.444.32";
};
```
marking id with `use` as well would result a compilation error.

records are passed by value by default, which means you are duplicating all data on assignment:
```rust
let mut foo some_rec = { field_1 = 4, ... };
let mut bar = foo;
foo.field_1 = 5; // bar.field_1 is still 4
```
you can also dynamically duplicate if needed:
```rust
let mut buz = new ! foo @ arena;
```
see more about mutability in [this section](#mutability) and about memory allocation and arenas in [this section](#memory-arenas-and-memory-allocation).

record fields are always set to its zero value if not assigned on initialization, i.e. numeric values are assigned to 0, booleans to false, strings to `""`, etc, but they can also implement default values for these fields:
```rust
type car = record {
    door_cound u32 = 4,
    manufacturer str,
    model str,
};

pub fn main() void = {
    let golf = car { manufacturer = "volkswagen", model = "sportline" };
    let beetle = car { manufacturer = "volkswagen", door_cound = 2 };
};
```

## enumerators
enumerators are a way of defining a finite set of values behind a single type. you can use any primitive type as a enum type, as follows:
```rust
// enumarator of numeric values (unsigned 8-bit integer)
type stream = enum u8 {
    stdin = 0,
    stdout, // no assignment results in a incremental assignment on numeric values
    stderr,
};

// enumerator of strings
type weekday = enum str {
    monday = "monday",
    tuesday = "tuesday",
    wednesday = "wednesday",
    thursday = "thursday",
    friday = "friday",
    saturday = "saturday",
    sunday = "sunday",
};

// enumerator of floats
type math_constant = enum f64 {
    PI = 355 / 113,
    PHI = 89 / 55,
    SQRTOF2 = 99 / 70,
};
```
these variants can be accessed as a field of the type:
```rust
let today = weekday.monday;
let tomorrow = weekday.tuesday;
```
unlike C and some other languages, you can't cast a value _to_ an enumerator, and if a given variable is of said type, can only be assigned by its type variants. nevertheless, these fields can be compared and casted _from_:
```rust
let day_name = weekday.thursday str;
test day_name == weekday.thursday;
```
see more of the `test` statement on [this section](#test).

# expressions
lichen has a very simple and common expression parsing system aside from untyped value decaying and lazy evaluation. most of its quirks are from the [type system](#type-system), but overall, easy to follow:

## operators
as expected, lichen has operator precedence for arithmetic, comparison and boolean operators:
```rust 
let x = 4 + 2 * 3;
test x == 10;
```
the precedence order is `||`, `&&` < `==`, `!=`, `<`, `<=`, `>`, `>=` < `+`, `-` < `*`, `/`, `%`, `<<`, `>>`, `|`, `&`.

the boolean operators AND (`&&`) and OR (`||`) are quite special because they are lazily evaluated, which means their members are _only_ evaluated when the value may change the result. for instance:
```rust
if x || may_fail()! {
    ...
};
```
only calls `may_fail` if x is _not_ `true`. otherwise, the call never happens.

similarly:
```rust
if safety_flag && function_that_depends_on_flag() {
    ...
};
```
won't call `function_that_depends_on_flag` unless `safety_flag` is `true`.

see more about if blocks in [this section](#if-else).

lichen also has a builtin length operator that can be used on strings and arrays:
```rust
let text = "some text in here";
let length = #text;
```
a concatenation operator:
```rust
let new_array = old_array_a ..! new_array_b @ arena; // concatenate and assert for `nomem`, resulting in a concrete type
let new_array' = old_array_a ..? new_array_b @ arena; // concatenate and bubble `nomem` up on failure, also results in a concrete type
let new_array'' = old_array_a .. new_array_b @ arena; // concatenate but do not assert for errors, resulting in a partial type
```
all of these concatenations are dynamically allocated on a memory arena, you can see more about these in [this section](#memory-arenas-and-memory-allocation).

the same symbol is used for the range operator:
```rust
switch a
| 1 .. 3 { io::println("inclusive range in both ends")!; };
| 4 .. 9 { io::println("this includes all numbers from 4 to 9, including 4 and 9")!; };
```
see more about switch cases in [this section](#switch).

## assignments
you may assign directly to variables and record fields, but not to arrays. this is because lichen ensures type safety for buffer overflow/underflow on arrays by making each element a partial type, so an assignment would be unsafe and not reliable. to index an item from an array, you must assert on it to ensure the item exists:
```rust
let mut x = u32;
x = 5 * 3 + 9;

let mut y some_record;
y.some_field = 4;
y.some_other_field = x;

let arr = [1, 2, 3, 4, 5, 6] u32;

let z = arr[0]!;
let z' !u32 = arr[0];
```
lichen doesn't have short assignment operators such as `+=`, `-=`, etc.

## ternary expression
once if-else blocks in lichen cannot yield a value, as the ones in languages like hare and rust can, it turns out necessary to provide another way to shortly assign conditional values. this is what the ternary expression is used:
```rust
let x u32 = 4;
let y = x if x > 4 else 10; 
```
any value can be assigned using ternary expressions as long the true and false case match types. the condition, in this case, `x > 4`, must be boolean.

similarly to the lazy evaluation of `&&` and `||` operators, the ternary expression does not process the else expression unless its needed, and the true value is never processed if the condition is false:
```rust
let is_safe_to_call_foo bool = check_safety();
let value u32 = foo() if is_safe_to_call_foo else 0;
```

## error assertion
on an error, you may not want to return the error up or halt execution, but do something instead. you may extend an assertion operator giving it more functionality, for instance:
```rust
let x u32 = may_fail(4)?;
```
returns any error to the upper stack, but this:
```rust
let x u32 = may_fail(4)? or 1;
```
defaults x to `1` on an error.

similarly, this:
```rust
let file = fs::open("file.text", fs::flags.READONLY)!;
```
crashes the program on an error, but this:
```rust
let file = fs::open("file.text", fs::flags.READONLY)! or io::println("could not open file. want to try another one?")!;
```
executes the subsequent code on a fail, assigning the zeroed value to the variable instead of the valid result.

you may also chain handlers depending on the error variant:
```rust
let foo str = may_also_fail("hi")?
    or nomem | "allocation failed";
    or fail | "something went wrong";
```
these chains are not required to be exhaustive i.e. cover all errors. on this case, the resulting type is still partial.
```rust
mem buffer | 128 << 8 {
    let number !u64 = strconv::to_u64("128", buffer)!
        or nomem | io::fail("buffer not large enough");
}!;
```
this `buffer` is a memory arena. see more about it in [this section](#memory-arenas).

even after chaining, if not all possible errors are handled, type remains partial and caller must still bubble up or assert.

# statements
lichen has a very limited number of statements. unlike many functional programming languages, lichen does not support statements as expressions, for both a simpler parsing and syntax, but also for a closer similarity to procedural languages.

## if-else
the basic code branching mechanism available in lichen. a if-else chain of blocks are capable of executing conditional code based on a boolean expression.
```rust
let x = 42 u32;
let y = 16 u32;

if x > y || x + 1 == y {
    io::println("x is either bigger than y or 1 less than y")!;
} else {
    io::println("x is either equal to y or less than y")!;
};
```
if statements are required to end in a semicolon, as any other code path.

if-else-if chains are also allowed:
```rust
let x = u32;
if x > 4 {
    io::println("x is greater than 4")!;
} else if x == 4 {
    io::println("x is equal to 4")!;
} else if x > 1 {
    io::println("x is non zero")!;
} else {
    io::println("x is is zero")!;
};
```

you may also arbitrarily define local variables at any point of the chain and it will be visible only to the following code blocks.
```rust
if x = factorial(4); x > 128 {
    io::println("some checking on x")!;
} else if x > 64 {
    io::println("another checking on x")!;
} else y = x * 2; y > 0 {
    io::println("a checking on y")!;
};
```

## switch
switch blocks allow you to compare any value to a limited set of constants. it is required to be exhaustive i.e. all possible values of the given value must be covered. this is useful when dealing with enumerators:
```rust
// standard input & output module
io mod = use "std/io.lim";

// enumerator of strings
type weekday = enum str {
    monday = "monday",
    tuesday = "tuesday",
    wednesday = "wednesday",
    thursday = "thursday",
    friday = "friday",
    saturday = "saturday",
    sunday = "sunday",
};

pub fn main() void = io {
    let today = weekday.tuesday;
    switch today
    | monday, tuesday {
        io::printfln("today is %s. we're on the early week", today)!
    };
    | wednesday, thursday {
        io::printfln("today is %s. we're on mid week", today)!
    };
    | friday {
        io::printfln("today is %s!", today)!
    };
    | saturday, sunday {
        io::printfln("today is %s. were on the weekend", today)!
    };
};
```
similarly to the if-else blocks, switch also allows you to define local variables:
```rust
    switch let r = some_fun(); r
    | 0 { io::println("single constant")!; };
    | 2, 3, 4 { io::println("set of constants")!; };
    | 5 .. 10 { io::println("ranges of constants")!; };
    | else { io::println("default case")!; };
```
as seen in this example, when it's not possible or required to cover _all_ cases, you may add an `else` case to address anything that doesn't match the other cases. the else case may be placed at any point of the switch block.

switches can only compare against constant values and can only switch for concrete types.

## for-loop
a for loop is simply a way to safely iterate over an array. if an array is empty, no execution happens:
```rust
let primes = [2, 3, 5, 7, 11, 13, 17, 19] u32;

for prime .. primes {
    io::printfln("%u", prime)!;
};
```
optionally, the index may also be iterated over:
```rust
let people = ["mary", "peter", "sus", "john", "luke"];

for person, index .. people {
    let before = people[indexing - 1]? or "no one";
    let after = people[indexing + 1]? or "no one";

    io::println("%s is before %s and %s is after them",
        before, person after)!;
};
```
see more about the `or` keyword in [this](#error-assertion) and [this](#error-and-propagation) sections.

the index is optional, but must be placed after the iteration variable. it can be named anything nevertheless. the type of the indexing variable is always `u64`.

once it's safe to assume the for loop will never go out of bounds with an array, when the iteration item is marked as mutable, it can be used to assign to a particular index of the array, as follows:
```rust
let mut list = [1, 2, 3, 4, 5] u32;

for mut item, index .. list {
    item = list[index + 1]? or 0;
};
```
this code left-shifts the array by one, appending a zero at the end with the use of `or`. for an array item reassignment, it is mandatory for the iteration array also be mutable.

## test
the test statement asserts for a boolean expression to be true, optionally prompting an error message, and then halting the program execution on fail.
```rust 
let x = "foo";
let y = "bar";

test x == y, "x and y are not equal";
```
this statement works more or less like an assert in other languages.

the only difference between a test and an assert statements is that a test block may be bubbled up on failure:
```rust
fn div(x u32, y u32) !u32 = {
    test ? y > 0;
    return x / y;
};
```

# memory arenas
arenas are the only way to dynamically allocate memory in lichen. an arena is a "null garbage collector" or a "runtime stack", in the sense it allocates data contiguously on a pre-defined size chunk of memory and then deallocates everything at once at the end of its lifetime, unlike actual garbage collectors, arenas never individually free objects, but the entire chunk is freed at once at end of scope. and unlike actual stack frames, the arena can be arbitrarily large and allocate the actual memory reserved by the operating system on demand:
```rust
// reserves 1 billion bytes (one GB)
mem arena | 1_000_000_000 {
    // allocates a buffer of 128 bytes on the arena
    let mut buffer = new ! [128; 0...] u8 @ arena;
    // reads from stdin and places at this buffer
    io::read_to(buffer)!;
    // casts it to a string and prints it back
    io::printfln("you typed: %s", buffer str)!;
}!; // deallocates all required memory
```
at the end of the scope, all allocations and the arena itself are guaranteed to be deallocated, except on a halt within the arena scope.

arenas may also be nested and passed to other functions for more specific allocation lifetimes:
```rust
mem input | 512 {
    let file_name = new ! [512; 0...] @ input;
    io::read_to(file_name)!;
    mem file_buffer | 128 << 16 {
        let file = fs::open(file_name str, fs::flags.READONLY)!
            or io::fatalf("could not open file \"%s\"", file_name str);

        let data = fs::read_lines(file, file_buffer)!;
        for line .. data {
            io::println(line)!;
        };
    }!;
}!;
```
as a sub-product of lifetimes, no value allocated within an arena can be assigned to outer scope variables or returned, once this would exceed the limits of whe arena scope and life longer than its lifetime:
```rust
fn some_function() str = {
    let mut buffer = "";
    mem arena | 512 {
        let new buffer' = new ! [512; 0...] u8 @ arena;
        buffer = buffer' str; // invalid. `buffer` lives longer than the arena
        buffer' = new ! buffer @ arena; // valid. copying of data into the arena
        return buffer'; // invalid. upper stack-frame lives longer than the arena
    }!;
};
```

# effects
effect is anything that can be observed by the user as a sub-product of the program execution. opening a file and writing to it, printing to the terminal, showing something at the screen, updating a memory address by reference, etc. all of these are considered either fallible or error prone. a file may not exist and hence not be able to be open, a memory address changed by another function may hide a bug because it was not supposed to change a given value, a terminal may be piped to a file and the disk have not enough space to store the output. that's why any impure functions, i.e. the ones that may produce side-effects, must be tagged with an effect. by this, it's semantically enforced that all code paths that may fail or cause a failure state are known to do so. for instance, the following code:
```rust
io mod = use "io.lim";

pub fn main() void = io { // tagged as something capable of doing io effects
    io::println("mornin' sailor!")!; // printing to the stdout by default
};
```
on a GNU/linux system, it's possible to redirect any writes to the terminal to a file, as such:
```sh
main > output.txt
```
if the said `output.txt` file was actually, for example, `/usr/lib/`, it would require super user privilege, and if the command was not executed with such privileges, the printing would fail. that's another reason for why printing is considered impure.

effects can be chained for a larger set of possible effects, as such:
```rust
fs mod = use "std/fs.lim";
io mod = use "std/io.lim";

pub fn main() void = fs & io {
    mem arena | 256 << 16 {
        let buffer = new ! [256; 0...] @ arena;
        io::read(buffer)!;
        let buffer' = buffer str;

        if fs::exists(buffer', fs::flags.RW) {
            let file = fs::open(buffer', fs::flags.RW)!;
            let lines = fs::read_lines(file, arena)!;

            let mut file' = new ! [512; 0...] @ arena;
            for line .. lines {
                file' = file' ..! line @ arena;
            };
        } else {
            io::fatalf("the file %s does not exist or cannot be opened", buffer');
        };
    }!;
};
```
if we forgot to tag main with `fs` or `io`, this wouldn't compile because all `io::println`, `fs::exists` and `fs::open` interact with the outside world, produncing, side-effects.

as these chains can become uncomfortably large, you may reduce all effects and abstract them behind a single `do` tag, a keyword that means "any effect may occur". once tagging all functions as such would destroy all the meaning of this system, a function tagged with `do` cannot call another function also tagged with `do`.
```rust
io mod = use "std/io.lim";

fn untagged() unit = do {
    io::println("anything!")!;
};

fn tagged() unit = io {
    io::println("io'ing around")!;
};

pub fn main() void = do {
    untagged(); // invalid call
    tagged(); // valid
};
```
once a function with no tags cannot produce any side-effect, it is considered pure, once its result is solely dependant on its arguments:
```rust
fn mul(x u32, y u32) u32 = { return x * y; };

pub fn main() void = {
    let x = mul(4, 5); // always return 20
};
```
since pure functions produce no observable effect other than their return value, they must be assigned, compared, or otherwise used:
```rust
pub fn main() void = {
    let x = mul(4, 5); // ok
    mul(3, 3); // invalid. value is never used

    let mut y = 0;
    if mul(2, 2) == 4 { // also ok. value is compared against
        y = 5;
    };
};
```
this does not apply to void functions, once they never return i.e. no value exists to be used.

# modules
modules are a simple and practical way to both encapsulate reusable code and effects behind a single tag. for instance, any module that implements an impure function (i.e. one that produce effects) requires that the caller function only declare the module binding as an effect tag:
```rust
// loads all functions, types and global variables declared in the `io.lim` file.
io mod = use "std/io.lim";

pub fn main() void = io { // mark main as producer of io effects
    io::println("mornin' sailor")!; // prints to the stdout, interacting with the world, producing an effect
};
```
see more about effects on [this section](#effects).

in this case, the `io` namespace used in the first line is a module binding, which means it can be any name and is only needed to _name_ a file and consequently its required effect tag. the actual module file `io.lim` is part of the lichen standard library (`std/`).

in order to another file access anything from a module, it may declare it as a public identifier:
```rust
// foo.lic
pub a_public_variable u32 = 4;
a_private_variable u32 = 2;

pub fn a_public_function(x u32) u32 = {
    return x + a_private_function(private);
};

fn a_private_function(x u32) u32 = {
    return x * 2;
};

// main.lic
foo mod = use "foo.lic";

pub fn main() void = {
    let x = foo::a_public_function(12);
    let y = x + foo::a_public_variable;

    let x' = foo::a_private_function(4); // invalid. private field
    let y' = foo::a_private_variable; // also invalid
};
```
declaring a field as public also tells the linker to export this symbol, making it accessible to other files from other languages to access it.

modules may also have submodules that when declared as public can be accessed through them:

in the module source file `std/os.lim`:
```rust
// this exports the module binding to the module when imported
pub exec mod = use "os/linux/exec.lim";

// some code
```
the said sub module source of `os/linux/exec.lim`;
```rust
rt mod = use "os/linux/runtime.lim":

// os/linux/exec.lim
pub type cmd = record {
    name str;
    args []str;
    env: linux::env;
    run: fn() !unit rt;
};

pub fn command(name str, args str...) !cmd = os & rt {
    // some more code
};
```
finally, the main file:
```rust
io mod = use "std/io.lim";
os mod = use "std/os.lim";

pub fn main() void = io & os {
    let cmd = os::exec::command("cat", "main.lic")!;
    cmd.run()! or fail | io::fatal("could not execute command");
};
```
see more about the `or fail | ...` syntax in [this section](#error-assertion).

even if, semantically, there is no actual difference, once a module is first looked at the standard library at the lib path and, if not found, then looked at the source root folder, it is a convention to use the `.lim` (lichen module) for files you write to provide some resource as an isolated code unit, and the `.lic` (lichen code) extension for main source files, the ones you write to give the program functionality.

# memory arenas and memory allocation
memory arenas are an abstraction for dealing with dynamically memory with a well defined lifetime i.e. you know exactly where it was allocated and where it will be released:
```rust
let arbitrary_runtime_size u64 = 100_000 * (64 << 8);

mem dynamic_memory_chunk | arbitrary_runtime_size { // request to the OS to reserve this much memory 

    let some_array = new ! [256; 1, 2, 3, 4, 5, 0...] u32 @ dynamic_memory_chunk; // allocates `some_array` within the arena
    let x = some_array[4]!;

}!; // give back to the OS this requested memory chunk
```
you can place data on these arenas using two main operations: allocation and concatenation. first, the allocation:
```rust
let arr = new [number_of_items; 0...] u32 @ arena;
```
this results in an optional type because the arena may not be able to place this data at the available memory. in an allocation failure, the error state is `nomem`. that's why we assert if we want to halt execution on a failure or bubble up if the failure should be recoverable:
```rust
let required_for_further_execution = new ! [1, 2, 3, 4] u32 @ arena;
let recoverable_from_failure = new ? [8; ""...] @ arena;
```
similarly, the arena itself may not be able to be allocated, and this is why in previous examples, the arena scope ends in an `!`, but as any other error, it could also be bubbled up:
```rust
fn reduce_array(size u64) !u64 = {
    mem arena | size {
        let arr = new ? [1, 2, 3, 4] u32;
        let mut acc = 0 u64;
        for item .. arr {
            acc = acc + item;
        };
        return acc;
    // if `size` is too large, the arena won't be allocated and bubble `nomem` up
    }?;
};

pub fn main() void = io {
    let total = reduce_array(1_000_000_000)? or 0; // on a failure, default `total` to zero
};
```
see more about error assertion syntax in [this section](#error-assertion).

the concatenation happens using the concatenation operator `..` (the same operator used as a range operator when using case intervals in [switch cases](#switch)), can be used to concatenate two different arrays or strings into a new, single data unit:
```rust
let one_to_five = [1, 2, 3, 4, 5] u32;
let six_to_nine = [6, 7, 8, 9] u32;

mem arena | (#one_to_five + #six_to_nine) * 4 {
    let one_to_nine = one_to_five ..! six_to_nine @ arena;
};
```
just like any other allocation, the concatenation requires an explicit arena to be placed using `@ your_arena`.

similarly, the concatenation operator also results in a partial type, but can be asserted for failures.
```rust
let partial ![]u32 = [1, 2, 3] .. [5, 6, 7] @ arena;
let bubble []u32 = [1, 2, 3] ..? [5, 6, 7] @ arena;
let assert []u32 = [1, 2, 3] ..! [5, 6, 7] @ arena;
```

# mutability
lichen addresses for mutability. unlike rust, this system is not associated with a lifetime or borrowing system. memory is still passed by value and not by reference, but, similarly to rust, mutability in lichen addresses for namespace _and_ value.
```rust
let x = 4; // can't reassign to `x`, will always be 4
let mut y = x;
y = 5; // can reassign

let rec some_record = { field_1 = 4, field_2 = true }; // can't reassign to rec or its fields
let mut other_rec some_record;
other_rec.field_1 = x; // can reassign to field
other_rec = { rec | field_2 = 5 }; // can reassign to `other_rec`
```
see more about this `{ rec | field_2 = 5 }` syntax in [this section](#records).

passing a mutable variable to another function, in the other hand, is different and always passed by reference. that means that if a function updates a field of a record or writes to an array, the original variable also changes, once they carry the same value:
```rust
type person = record {
    age u8,
    name str,
}

// x is marked as mutable, then the
// function is marked with a given tag
fn age(mut p person, years u8 = 1) unit = chn {
    p.age = p.age + years;
};

pub fn main() void = chn {
    let mut mary = person { age = 12, name = "mary" };
    age(mary);
    test mary.age == 13;

    age(mary, 13);
    test mary.age == 26;
};
```
both tests succeeds when the code is run.

# error and propagation
errors are the other side of partial types, as an invalid state with `fail` or a memory allocation failure with `nomem`. these singletons can't be operated by any means and not compared to anything, but can be returned, assigned and asserted on:
```rust
io mod = use "std/io.lim";

fn state_error() !unit = { return fail; };
fn memory_fail() !unit = {
    mem empty | 0 {
        let arr = new ? [128; 0...] u32 @ empty; // cannot fit 128 items of 32 bits in a 0-sized memory arena
    }!;
};

pub fn main() void = io {
    let error = state_error();
    let error' !u32 = fail;
    memory_fail()! or io::fatal("allocation failed");
};
```
when you bubble the error up, the function returning the error shall return a partial type as well:
```rust
fn failure() !unit = { return fail; };
fn propagates(x u32) !u32 {
    if x == 0 {
        failure()?;
    } else {
        return x * 4;
    };
};

fn invalid() u32 {
    failure()?; // compilation error: cannot propagate partial unit type from concrete u32 type
    return 4;
};
```
but when an error is asserted with `!`, it halts the program execution on a error exit code, making it clear something went wrong:
```rust
fn no_partials_needed() u32 = {
    failure()!;
};
```

# FFI declarations
sometimes it's useful to use functions and values from programs written in another language, such as C, so lichens provide a simple FFI (foreign function interface) for interacting with external symbols. obviously, once the language used by other programs cannot guarantee their functions are pure, it's mandatory to always tag these FFI symbols:
```rust
let external_variable u32 = use "my_external_variable";
// `does_something` is an arbitrary effect tag, so the caller must also tag itself to call this FFI symbol
fn external_function(x i32, y i32) i32 = does_something use "my_external_function";
```
as mentioned by [this section](#mutability), some values cannot be guaranteed to not change when passed by reference unless made immutable. again, the external symbol can't prove it wont mutate the value of the taken variable, so it's mandatory for FFI functions to define any string, record and other aggregated types as mutable parameters:
```rust
fn takes_a_buffer(mut buff []u8) unit = may_change_buff use "another_external_function"; 
```
you can see more about effects in [this section](#effects).
