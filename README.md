# lichen: a small plant for big jobs
lichen is a simple, small, procedural, programming language with functional features.

## special features
- mutable semantics
- array indexing safety through partial types
- effect system
- memory arena allocators
- no dependencies on (gnu) lib-c
- small runtime and no implicit control flow
- lazy evaluation and function code emission
- record sub-typing for generic programming
- singletons for generic error (`fail`) and memory allocation failure (`nomem`)

## inspirations
lichen is directly inspired by [hare](https://harelang.org), [Flix](https://flix.dev/), [Odin](https://odin-lang.org), jai, [elm](https://elm-lang.org) and [Rust](https://rust-lang.org).

## code examples
a hello world
```rust
io mod = use "std/io.lim";

pub fn main() void = io {
    io::println("mornin' sailor!")!;
};
```
a hello user
```rust
io mod = use "std/io.lim";

pub fn main() void = io {
    // set buffer size
    let size u64 = 128 << 16;
    // create memory arena for buffer
    mem buffer | size {
        // allocate string buffer
        let name mut = new [size; 0] @ buffer;
        // read from user
        io::read(size, name!)!
            or io::fatal("failed to read from user");
        // greetings!
        io::printfln("hello %s!", name str)!;
    }!;
};
```
read a file and print asked line
```rust
conv mod = use "str/conv.lim";
fs mod = use "std/fs.lim";
io mod = use "std/io.lim";
os mod = use "std/os.lim";

pub fn main() void = fs & io {
    // fetch CLI argument list
    let args = os::args();

    // assert for arguments
    let file_name = args[1]?
        or io::fatal("line number not given");
    let line_number = args[2]?
        or io::fatal("line number not given");

    // allocate buffer for file lines array
    mem line_buffer | count << 16 {
        // convert given argument as string to number
        let line_number' = conv::to_u64(line_number, line_buffer)!
            or fail | io::fatalf("invalid line number %s", line_number);
            or nomem | io::fatal("buffer for line number not big enough");
        // set max size for file buffer
        let max = 128 << 16;
        // allocate buffer for file
        mem file_buffer | max {
            // try to open given file
            let file = fs::open(file_name, fs::flags.READONLY)!
                or io::fatalf("file %s could not be opened", file_name);
            // read entire file by lines
            let lines = fs::read_lines(file, file_buffer)!;
            // check if line number is valid
            if #lines < line_number' {
                io::fatal("file %s doesn't have line %u", line_number');
            };
            // assert value from array
            let line = lines[line_number']!;
            // print it
            io::println(line)!;
        // assert for memory allocation failure
        }! or io::fatal("failed to create file buffer");
    }!;
};
```

# disclaimer
lichen, previously called moss, is still heavily in development. not only the compiler, but everything related to the project. everything, including syntax, semantics and general framework are subject to change at any time:
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
        - [done] fail and nomem
        - [partial] decimal numbers
            - [done] decimal point
            - [undone] scientific notation
        - [done] array literals
            - [done] spreading
        - [undone] record literals
            - [undone] autofill
    - [partial] declarations
        - [partial] functions
            - [done] declaration
            - [partial] variadic
            - [done] effect tags
            - [done] effect tag matching assertion
            - [done] FFI
            - [undone] first-class type declaration
        - [done] variables
            - [done] declaration
            - [done] reassignment
            - [done] mutable notation
            - [done] mutability assertion
        - [partial] records
            - [done] declaration
            - [done] literal
            - [undone] change-copying
            - [done] duplication
            - [partial] field assignment
        - [partial] arrays
            - [partial] declaration
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
    - [partial] statements
        - [done] if-else blocks
            - [done] branching
            - [done] local variables
        - [done] return
            - [done] expression return
            - [done] empty return
        - [undone] switch
            - [undone] base functionality
            - [undone] local variables
            - [undone] multiple constants
            - [undone] constant range
            - [undone] else case
            - [undone] exhaustiveness
        - [done] for-loop
            - [done] base functionality
            - [done] local variables
            - [done] optional index
        - [partial] memory arenas
            - [done] creation
            - [done] allocation
            - [undone] concatenation
            - [done] nomem error
            - [done] first class object
        - [partial] test block
            - [undone] static/global
            - [done] dynamic/local
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
    - [undone] buff
    - [partial] fs
    - [partial] io
    - [partial] os
        - [undone] exec
    - [undone] vect
    - [partial] str
        - [undone] encode
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
lichen is written in the [hare programming language](https://hare-lang.org) and uses the [QBE](https://c9x.me/compile/) IR as a backend to generate the binaries. once all dependencies are installed, you're ready to both build the compiler and use it with no other dependencies. note that each of lichen' dependencies have theirs own dependencies. once everything is set, simply run the `install.sh`. it will copy a binary called `lcc` and the runtime and standard library to `~/.local/bin` and `~/.local/lib/lcclib`, respectively, and will be available only for your current user. you also can specify which directory the compiler should look for the runtime and standard library using the `-std` flag.

optionally, if you have lua 5.3, you can run an automated test unit for all milestones with `run_tests.lua`.

# learning lichen
you can learn lichen in a course of one to three days. [this](doc/tut.md) is the tutorial.

# coding tools

## LSP
lichen has not and probably will never have an official LSP, but you're free do develop one yourself. feel free to hit me about that.

## highlighting
there's a vs code/codium extension for a simple syntax highlighting in [here](https://github.com/mikumikudice/lichen-syntax-highlight).
