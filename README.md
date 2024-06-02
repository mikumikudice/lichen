# a small, simple and concise language for delightful tiny jobs
moss is a strongly typed, imperatively functional, AOT compiled programming language designed specifically to do things in a reliable and simple way.
## code example
this is a demo code for printing a hello world (in a mossy way):
```rust
use fmt;

pub main = fn() : unit \ fmt {
    fmt::putl("mornin' sailor!")!;
};
```
## special features
- memory safe through linear types. no GC, no lifetime tags.
- effect system and encapsulated state within in-practice pure functions.
- modern and clever casting system for convenient (smart) type conversions.
- simple, small and concise syntax semantics. new and yet familiar.
- no dependencies on libc and rich (yet simple) core libraries, producing statically linked, stand-alone binary files.
- no command line settings for the compiler; compilation flags are set in-code.
- no floats, but instead ratio types.
- extremely concise syntax. if it does the same thing, you write it in the same way.

## uncommon but already known features
- tagged unions for error handling (no runtime exceptions).
- lazy evaluation.
- no undefined behavior.
- memory and type safety.
- limited scope. moss is not meant to be general purpose, but for domain specific issues.
- no global state i.e. no global mutable variables.

## inspirations
moss is directly inspired by [hare](https://harelang.org), [Flix](https://flix.dev/), [Odin](https://odin-lang.org), jai, [elm](https://elm-lang.org) and [Rust](https://rust-lang.org).

# disclaimer
moss is still heavily in development. not only the compiler, but everything related to the project. despite it being not very likely to change during _implementation_, it still can change. currently we're at:

## roadmap
these are the current goals of this project:
- [x] lexer
- [ ] parser and code gen
    - [ ] expressions
        - [x] operators on primitives
        - [x] global reference to functions at any position
        - [x] expressions on function call arguments
        - [ ] operators on records
        - [ ] expressions within parenthesis
        - [ ] destructive read
        - [ ] defer
        - [ ] yield and statements as expressions
        - [ ] allow functions as first class objects
        - [ ] parallel assignment
        - [ ] range comparisons
    - [x] mutability checking
    - [x] hex, oct and bin literals
    - [x] prime notation
    - [x] multi-line, nestable comments
    - [ ] type system
        - [ ] type checking
            - [x] on expressions
            - [x] on function calls
            - [ ] on record assignments
            - [x] casting for function arguments
        - [ ] arrays
            - [ ] sugar syntax
            - [ ] multidimensional arrays
            - [ ] indexing of function returns
        - [ ] lists
        - [ ] ratios
        - [ ] records
            - [ ] default values for record fields
            - [ ] field access of function returns
        - [ ] unions
        - [ ] error tags
        - [ ] error assertion and bubble operator
        - [ ] linear types
        - [ ] test statement
    - [ ] control flow
        - [x] if/else
        - [ ] for loop
            - [ ] for each
            - [ ] for range
        - [ ] match
        - [ ] defer
    - [ ] local functions
    - [ ] default values for function arguments
    - [x] modules
    - [ ] FFI
    - [x] effect system
- [ ] compile-time tests
- [ ] improve helpfulness of error messages
- [ ] code optimizations.
    - [ ] compile-time constant values are optimized-out in the final code
    - [ ] runtime constant values evaluated at compile time
- [ ] core lib and kernels
    - [ ] os
    - [ ] rt
    - [ ] fmt
    - [ ] mem
    - [ ] str
    - [ ] fun
    - [ ] time
    - [ ] math

# building moss
moss is written in the [hare programming language](https://hare-lang.org), uses the [QBE](https://c9x.me/compile/) IR as a backend to generate the binaries, [nasm](https://nasm.us) as assembler for the language kernels and [mold](https://github.com/rui314/mold) as a linker. once all dependencies are installed, you're ready to both build the compiler and use it with no other dependencies. note that each of moss' dependencies have theirs own dependencies. once everything is set, simply run the `build.sh`. it will generate the compiler binary by the name `mossy`.

optionally, you can run `test.sh` to run the moss compiler tests. also, if you have lua 5.3, you can run an automated test unit for all milestones with `test.ms.lua`.

## IMPORTANT
moss is not being installed globally in your machine, which means it can't look up for its files in a fixed directory; when running the compiler, make sure to run it on the root path of the repository or specify the lib path with the flag `-l`.

# learning moss
you can learn moss in a course of one to three days. [this](doc/tut.md) is the tutorial.
