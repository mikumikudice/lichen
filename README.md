# a small, simple and concise language for delightful desktop applications development
moss is a strongly typed, imperatively functional, AOT compiled programming language for GUI/CLI programs.
## code example
this is a demo code for printing a hello world (in a mossy way):
```rust
use io;

pub main = fn() void & io {
    io::put("mornin' sailor!");
};
```
## special features
- effect system semantics.
- simple, small and extremely concise syntax. if it does the same thing, you write it in the same way.
- no dependencies on (gnu) lib-c and rich (yet simple) core libraries, producing statically linked, stand-alone binary files.
- imperatively functional paradigm. your code does things imperatively in a functional approach.
- rich standard library for CLI and GUI applications.

## uncommon but already known features
- tagged unions and error as values.
- lazy evaluation.
- no undefined behavior.
- limited scope. moss is not meant to be general purpose, but for domain specific issues.
- no global state i.e. no global mutable variables.

## inspirations
moss is directly inspired by [hare](https://harelang.org), [Flix](https://flix.dev/), [Odin](https://odin-lang.org), jai, [elm](https://elm-lang.org) and [Rust](https://rust-lang.org).

# disclaimer
moss is still heavily in development. not only the compiler, but everything related to the project. despite it being not very likely to change a lot during the _implementation_, it still can change. currently we're at:

## roadmap
these are the current goals of this project:
- [x] lexer
- [ ] parser and code gen
    - [ ] floats
    - [ ] expressions
        - [x] global variables
        - [x] operators on primitives
        - [x] global reference to functions at any position
        - [x] expressions on function call arguments
        - [ ] operators on records
        - [x] expressions within parenthesis
        - [ ] allow functions as first class objects
            - [ ] type notation and function as arguments
            - [ ] aliases
                - [x] create aliases
                - [ ] use aliases
        - [ ] parallel assignment
        - [ ] range comparisons
    - [x] hex, oct and bin literals
    - [x] prime notation
    - [x] multi-line, nestable comments
    - [ ] `for` constructor
        - [ ] basic iteration system
        - [ ] reduce/fold behaviour
            - [ ] multiple accumulators
    - [ ] type system
        - [ ] type checking
            - [x] on expressions
            - [x] on function calls
            - [ ] on record assignments
            - [x] casting for function arguments
        - [ ] arrays
            - [ ] arrays of primitives
            - [ ] auto-fill syntax
            - [ ] arrays of objects
        - [ ] tuples
        - [ ] records
            - [ ] default values for record fields
            - [ ] field access of function returns
            - [ ] allow records to be returned by functions
        - [ ] tagged unions
        - [ ] errors
            - [ ] `fail` statement
            - [ ] error type
        - [ ] error assertion and short-circuit
        - [x] `todo` statement
        - [ ] dynamic types
    - [ ] control flow
        - [x] if/else
        - [ ] match
        - [ ] defer
    - [ ] local functions
    - [ ] default values for function arguments
    - [x] effect system
- [ ] improve helpfulness of error messages
- [ ] code optimizations.
    - [ ] compile-time constant values are optimized-out in the final code
    - [ ] runtime constant values evaluated at compile time
    - [ ] tail-call elimination
- [ ] runtime module
- [ ] standard library
    - [] stdlib
        - [ ] fs
        - [ ] io
        - [ ] cli
        - [ ] gui
        - [ ] time
        - [ ] math

## supported platforms
we plan to fully support these OSes/environments:

- GNU/linux (lime library)
- openBSD/freeBSD (capri library)
- redox OS (parasect library)
- haiku (mu library)
- freestanding environments + protected mode/real mode (muddy)

support include standard library port to the available syscalls/APIs and binary specifics.
moss has and will never have native support for closed source/proprietary OSes such as windows and macOS.

### runtime roadmap
- [ ] lime
    - [x] x86_64
    - [ ] x86
    - [ ] 64-bit risc-v
    - [ ] 32-bit risc-v
- [ ] capri
- [ ] parasect
- [ ] mu
- [ ] muddy

# building moss
moss is written in the [hare programming language](https://hare-lang.org), uses the [QBE](https://c9x.me/compile/) IR as a backend to generate the binaries, [nasm](https://nasm.us) as assembler for the language runtime and [mold](https://github.com/rui314/mold) as a linker. once all dependencies are installed, you're ready to both build the compiler and use it with no other dependencies. note that each of moss' dependencies have theirs own dependencies. once everything is set, simply run the `build.sh`. it will generate the compiler binary by the name `mossy`.

optionally, if you have lua 5.3, you can run an automated test unit for all milestones with `ms_test.lua`.

## installation
moss can be installed locally in your home directory by running `install.sh`. it will copy the built binary and the runtime and standard library to `~/.local/bin` and `~/.local/lib/lime`, respectively, and will be available only for your current user. you also can specify which directory the compiler should look for the runtime and standard library using the `-l` flag.

# learning moss
you can learn moss in a course of one to three days. [this](doc/tut.md) is the tutorial.
