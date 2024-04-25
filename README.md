# a small, simple and consice language for delightful tiny jobs
moss is a strongly typed, imperatively functional, AOT compiled programming language designed specifically to do things in a reliable and simple way.
## code example
this is a demo code for printing a hello world (in a mossy way):
```rust
use lime;
fmt = lime::fmt;

pub main = fn() : lime => nil {
    fmt::putl("mornin' sailor!")!;
};
```
## special features
- memory safe through linear types. no GC, no borrow checker.
- effect system and encapsulated state within semantically-controlled function purity.
- modern and clever casting system for convenient (smart) conversions.
- simple, small and concise syntax semantics. new and yet familiar.
- no dependence on libc and rich (yet simple) core libraries.
- no command line setting for the compiler. flags are in-code.
- no floats, but ratio types.
- extremely concise syntax. if it does the same thing, you write the same way.

## uncommon but already known features
- union types for error handling (no exceptions).
- lazy evaluation.
- no undefined behavior.
- memory and type safety.
- limited scope. moss is not meant to be general purpose, but for domain specific issues.
- no global state i.e. no global mutable variables.

## inspirations
moss is directly inspired by [hare](https://harelang.org), [Flix](https://flix.dev/), [Odin](https://odin-lang.org), jai, [elm](https://elm-lang.org) and [Rust](https://rust-lang.org).

# disclaimer
moss is still heavily in development. not only the compiler, but everything related to the project. despite it being not very likely to change during _implementation_, it still can change. currently we're at:
- [x] brainstorming.
- [x] language specification && compiler implementation.
- [ ] language peripherals/dev environment.
- [ ] self-hosting.

# roadmap
these are the current goals of this project.
- [x] lexer.
- [ ] parser and code gen.
- [ ] improve helpfulness of error messages.
- [ ] code optimizations.
- [ ] core lib.
- [ ] FFI specification.

# building moss
moss is written in the [hare programming language](https://hare-lang.org), uses the [mio](https://git.sr.ht/~mikaela-md/miolo) IR as a backend to generate the binaries and [mold](https://github.com/rui314/mold) as a linker. once both are installed, you're ready to both build the compiler and use it with no other dependencies. note that each of moss' dependencies have theirs own dependencies.

once you installed both, simply run the `build.sh`. it will generate the compiler binary by the name `mossy`. by running it, you'll get the help needed to get started on compiling your code.

# learning moss
you can learn moss in a course of one to three days. [this](doc/tut.md) is the tutorial.
