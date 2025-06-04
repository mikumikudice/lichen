# a small, simple and concise language for delightful desktop applications development
lichen is a simple, small, functional, AOT compiled programming language for small programs.

## code example
this is a demo code for printing a hello world (in a lichenous way):
```rust
io = use "io.lim";

pub fn main() void = io {
    io::println("mornin' sailor!")!;
};
```
## special features
- effect system semantics.
- small and simple syntax.
- no dependencies on (gnu) lib-c.
- lazy code gen.

## uncommon but already known features
- tagged unions and error as values.
- lazy evaluation.
- no undefined behavior.
- limited scope. lichen is not meant to be general purpose, but for domain specific issues.
- no global state i.e. no global mutable variables.

## inspirations
lichen is directly inspired by [hare](https://harelang.org), [Flix](https://flix.dev/), [Odin](https://odin-lang.org), jai, [elm](https://elm-lang.org) and [Rust](https://rust-lang.org).

# disclaimer
lichen, previously called moss, is still heavily in development. not only the compiler, but everything related to the project. everything, including syntax, semantics and general framework are subject to change at any time:

## supported platforms
we plan to fully support these OSes/environments:

- GNU/linux
- openBSD/freeBSD
- redox OS
- haiku
- freestanding environments + protected mode/real mode

support include standard library port to the available syscalls/APIs and binary specifics.
lichen has and will never have native support for closed source/proprietary OSes such as windows and macOS.

# building and installation
lichen is written in the [hare programming language](https://hare-lang.org) and uses the [QBE](https://c9x.me/compile/) IR as a backend to generate the binaries. once all dependencies are installed, you're ready to both build the compiler and use it with no other dependencies. note that each of lichen' dependencies have theirs own dependencies. once everything is set, simply run the `install.sh`. it will copy the a binary called `lcc` and the runtime and standard library to `~/.local/bin` and `~/.local/lib/lcclib`, respectively, and will be available only for your current user. you also can specify which directory the compiler should look for the runtime and standard library using the `-std` flag.

optionally, if you have lua 5.3, you can run an automated test unit for all milestones with `run_tests.lua`.

# learning lichen
you can learn lichen in a course of one to three days. [this](doc/tut.md) is the tutorial.

# coding tools

## LSP
lichen has not and probably will never have an official LSP, but you're free do develop one yourself. feel free to hit me about that.

## highlighting
there's a vs code/codium extension for a simple syntax highlighting in [here](https://github.com/mikumikudice/lichen-syntax-highlight).
