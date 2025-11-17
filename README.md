# lichen: correct by construction
lichen is a simple, small, procedural programming language with functional features focusing on writing code that is safe at compile time and yet simple to read, understand and follow, producing a program that is safe and predictable at runtime.

## special features
- mutable semantics
- array indexing safety through partial types
- effect system
- memory arena allocators with lifetime checking
- no dependencies on (gnu) lib-c
- no implicit control flow
- lazy evaluation and function code emission
- C-like unions with type tagging assertion
- singletons for logic failure (`error`) and invalid memory (`nil`)

## inspirations
lichen is directly inspired by [hare](https://harelang.org), [zig](https://ziglang.org/), [Flix](https://flix.dev/), [Odin](https://odin-lang.org), [go](https://go.dev/), jai, [elm](https://elm-lang.org) and [Rust](https://rust-lang.org).

## code examples
a hello world
```rust
io mod = use "std/io.lim";

pub fn main() void = io {
    io::println("mornin' sailor!")!;
};
```

how to gather user input in lichen
```rust
io mod = use "std/io.lim";

pub fn main() void = io {
    let length = 128 u64;
    new arena | length + 16 {
        // allocate input buffer
        let mut name = new ! [length; 0...] u8 @ arena;
        // gather input
        io::print("type your name > ")!;
        let len = io::read_to(name)!
            or io::panic("failed to read from user");
        // greetings
        io::print("hello, ")!;
        io::print(name[0..len]! str)!;
        io::println("!")!;
    }!;
};
```

usage of the string maker module
```rust
io  mod = use "std/io.lim";
mkr mod = use "str/mkr.lim";

pub fn main() void = io & mkr {
    // create a static buffer
    let mut static = [128; 0...] u8;
    // initialize a string maker from it
    let mut static' = mkr::static(static);
    // write to it
    mkr::write(static', "mornin'")!;
    new here | 256 {
        // initialize a dynamic string maker using an arena
        let mut dynamic = mkr::dynamic(128, here)!;
        // write to it as well
        mkr::write(dynamic, " sailor!")!;
        // dump the content of both makers
        io::print(mkr::dump(static'))!;
        io::println(mkr::dump(dynamic))!;
    }!;
};
```

# disclaimer
lichen, previously called moss, is still heavily in development. not only the compiler, but everything related to the project. everything, including syntax, semantics and general framework are subject to change at any time.

roadmap:
- [partial] tutorial
- [partial] specification
    - [partial] BNF syntax
    - [undone] grammar spec
- [partial] parser
    - [partial] type system
        - [done] mutable parameters / arguments matching
        - [done] expression types and operator expression validation
        - [done] function call effect validation
        - [done] unhandled error assertion
        - [done] unused pure function call result assertion
        - [partial] partial type assertion and bubbling
            - [done] error assertion piping to statement
            - [done] error bubbling piping to default value fallback
            - [undone] error piping variation tagging
        - [done] array indexing partials
        - [undone] default values
            - [undone] for functions
            - [undone] for record fields
        - [done] record field assignment exhaustiveness
    - [partial] literals
        - [done] strings and runes
        - [done] integer numbers
            - [done] hex
            - [done] oct
            - [done] bin
        - [done] boolean
        - [done] `error` and `nil`
        - [partial] decimal numbers
            - [done] decimal point
            - [undone] scientific notation
        - [done] array literals
            - [done] spreading
        - [partial] record literals
            - [undone] autofill
    - [partial] declarations
        - [partial] functions
            - [done] declaration
            - [done] effect tags
            - [done] effect tag matching assertion
            - [done] FFI
            - [done] first-class type declaration
        - [done] variables
            - [done] declaration
            - [done] reassignment
            - [done] mutable notation
            - [done] mutability assertion
        - [partial] records
            - [done] declaration
            - [done] literal
            - [undone] priming
            - [done] duplication
            - [done] field assignment
        - [done] arrays
            - [done] declaration
            - [done] indexing
                - [done] partial result
        - [partial] tuples
            - [partial] declaration
            - [undone] creation
            - [undone] unpacking
    - [done] expressions
        - [done] arithmetic operators
        - [done] boolean operators
            - [done] base functionality
            - [done] lazy
        - [done] ternary expression
            - [done] base functionality
            - [done] lazy
        - [done] function call
        - [done] value assertion
        - [undone] fail state checking
    - [partial] statements
        - [partial] if-else blocks
            - [done] branching
            - [done] local variables
            - [undone] conditional unwrap
        - [done] return
            - [done] expression return
            - [done] empty return
        - [done] unreachable
        - [partial] switch
            - [done] base functionality
            - [partial] duplicated case assertion
            - [done] local variables
            - [done] multiple constants
            - [done] constant range
            - [done] else case
            - [done] exhaustiveness
        - [done] for-loop
            - [done] base functionality
            - [done] local variables
            - [done] optional index
        - [done] while-loop
            - [done] base functionality
            - [done] local variables
        - [partial] memory arenas
            - [done] creation
            - [done] allocation
            - [partial] concatenation
                - [done] base functionality
                - [undone] in-place optimizations
            - [done] nil error
            - [done] first class object
        - [partial] test block
            - [undone] static/global
            - [done] dynamic/local
        - [partial] defer block
            - [done] base functionality
            - [undone] defer on fail
    - [done] partial types
        - [done] assertion
            - [done] basing assert and bubble
            - [done] assertion with statement
            - [done] bubbling with default
        - [done] runtime halt
    - [partial] modules
        - [done] base functionality
        - [done] publicity assertion
        - [partial] submodules
- [partial] standard library
    - [partial] fs
    - [partial] io
    - [partial] os
        - [undone] exec
    - [partial] vect
    - [partial] str
        - [done] mkr
        - [partial] conv
- [undone] os library
    - bios syscalls FFI
    - bsd
    - haiku
    - linux
    - redoxOS
- [partial] compiler
    - [partial] compilation flags
        - [done] external object
        - [done] set libpath
        - [done] add linking library
        - [done] dispatch as shared library
        - [done] dispatch as static archive
        - [undone] emit error messages with only message + error position offset
    - [done] error reporting with hints

## supported platforms
we plan to fully support these OSes/environments:

- GNU/linux
- openBSD/freeBSD
- redox OS
- haiku
- freestanding environments + protected mode/real mode

support include standard library port to the available syscalls/APIs and binary specifics.
lichen has not and will never have native support for closed source/proprietary OSes such as windows and macOS.

# building and installation
lichen is written in the [hare programming language](https://hare-lang.org) and uses the [QBE](https://c9x.me/compile/) IR as a backend to generate the binaries. once all dependencies are installed, you're ready to both build the compiler and use it with no other dependencies. note that each of lichen' dependencies have theirs own dependencies. once everything is set, simply run the `install.sh`. it will copy a binary called `lcc` and the runtime and standard library to `~/.local/bin` and `~/.local/lib/lcc`, respectively, and will be available only for your current user. you also can specify which directory the compiler should look for the runtime and standard library using the `-std` flag.

optionally, if you have lua 5.3, you can run an automated test unit for with `run_tests.lua`, found in scrips/.

# learning lichen
you can learn lichen in a course of one to three days. [this](doc/tut.md) is the tutorial.

# coding tools

## LSP
lichen has not and probably will never have an official LSP, but you're free do develop one yourself. feel free to hit me about that.

## highlighting
there's a vs code/codium extension for a simple syntax highlighting in [here](https://github.com/mikumikudice/lichen-syntax-highlight).
