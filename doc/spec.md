# design, semantics and paradigms study sources
## reasons to create moss:
- moss exists to try new approaches to old problems
    """
    the world doesn't need new languages [...]
    it's likely that afer 10 years, [your language] to have one user (you),
    and I wanna say that's ok. do it anyway. it's worth doing anyway.
    """
[Peter Alvaro, 2019][1]
["thy firmness makes my circle just"][1] in the sense that moss picks a specific domain of problems and delimitates it area of action.
["language are tools"][1] in the sense that moss is barely a tool that may or may not to be used in some cases, but its designed to solve a sort of problems that most people want to solve, but perhaps overcomplocate it.

moss exists to addres 3 main problems:
- memory safety
- code and language complexity
- dependency on legacy and outdated technology

people have tried solving them with:
- [rust](https://rust-lang.org) and its borrow checker, [go](https://go.dev/) and concurrent garbage collecting, and more.
- minimalism and oversimplification, like [redox-os](https://www.redox-os.org/) and its approach to microkernel architecture and intimate integration with the rust programming language.
- revolutionary breaking with existing tools and environments, with, for example, [chimera linux](https://chimera-linux.org/) and its attempt to get rid of GNU stuff.

problems with these:
- borrow checking is complex and hard to use and implement, from both compiler and programmer sides. GC is sometimes slow and not suitable for most cases.
- reinventing the wheel, when done correctly, most of the times takes time to go well and addoption is hard once its always niched. it's good, but sometimes, we need to fix things from inside, and not by creating completely new alternatives.
- linux, GNU, C and all historical dependencies we still use are hard to get rid off because, even if they are obsolete in some senses or even disastrous in others, are hard to replace once they are widely used and strongely maintained by lots of people. the way to fix them is replacing tiny bits over time (as they are already doing with linux by rewriting it in rust).

how moss, arguably, tries to solve:
- simple, concise and small type & effect systems using linear types and smart type casting.
- simple, concise and small syntax, semantics and explicit implementation and operation and minimal, customizable and clear runtime.
- no use of libc, no backwards compatibility with outdated and basically unused things such as vertical tab, interopeability with C, C ABI compatibility and so on.


why:
- enforce memory safety: because data is critical and valuable. you account passphrase could leak. your credit card code could leak. also, reading out bounds, reading invalid addresses, storing unused data and freeing still-in-use data are all real-life and common problems that no one was able to truly fix in a easy and accessible way yet.
- keep code and language less complex: real life is complex. real life problems are complex. try to fix them using complex tools is add more layers of unnecessary complexity. [if you start from a solid, basic ground, building on top of that may be way simpler][2]. simplicity makes things easier to understand and follow.
- dependency on legacy and outdated technology: the old things have their value. in the past. as programmers and, in a wider sense, as a society, should learn from the past and go _past_ it. depending on legacy code for the 60's computers were necessary in the 80's, not in the two thousands. we don't use punch cards anymore. we don't program in terminals logged in mainframes anymore. let the past be in the past as a guide, not as a jailer.

moss is a fresh new look to old stuff. to see what we did right, what we did wrong and what we haven't tried yet.

["everything else, arguably, is a distraction."][1]

[1]: <https://www.youtube.com/watch?v=oa0qq75i9oc> "three things I wish I knew when I started designing languages"
[2]: <https://www.youtube.com/watch?v=f3rP3JRq7Mw> "Robert Virding - On Language Design (Lambda Days 2016)"

## simple
moss have a tiny set of rules, keywords and functionalities. 36 keywords, 5 for built-in functions, 12 for primitive type names, 3 for user-defined types, 4 for control flow blocks, and the other 12 are for namespacing/module control, effect system and compiler-defined constants. if anything is added to this, it should make writing code in moss easier, clearer or shorter. if it doesn't address any of these, it may not be added.
## concise
there are very few things you can do in more than one way in moss. the main rule is, "if it does something similar, it should look similar." that's why all functions are assigned like any other variables i.e. they type and body are assigned as anonymous functions, namespace definition and assignment are semantically the same thing, once if x is u64 and x is 8, then x is a u64 8. all statements are valid assignable values i.e. everything returns a value.
## small
moss have a tiny set of keywords, a tiny set of built-in functionalities and a very tiny runtime overload. all code in moss should do one and argueably only one thing, use the least amount of data and CPU usage and weight the smallest space in disk possible.
## moss
moss is a type of plant that is very simple and tiny, that operates by simple and unusual rules and that, together with others like them, make big structures that can operate together and isolated at the same time, in an asynchronous, co-dependent way. and also, interact with other kinds of creatures, linking with them, like lichen.

# inspirations
moss is heavily inspirated by:
- [Flix](https://flix.dev/)
- [elm](https://elm-lang.org/)
- [hare](https://harelang.org/)

and takes some ideas from:
- [odin](https://odin-lang.org)
- [zig](https://ziglang.org/)
- [pony][3]

[3]: <https://www.ponylang.io/> "the pony programming language"

# semantics
- all primitive types should be able to be casted in each other in a useful way.
- all variables must receive explicitly casted values to their definition type.
- functions may or may not generate side-effects, but all possible effects must be explicitly noted. even if it comes from other functions within it.
- mutability can only exist in a self-contained box of isolated data alteration, i.e. functions. that means functions cannot alter outer scopes and, as such,
there's no global state. [imperatively functional](#imperative-functionalism).
- no try-catch, no invisible bugs, no exceptions, no unavoidable panics, no random crashes, no undefined behavior. ["You make your mess; you clean it"][3]. doing things hiddenly and not let the programmer chose if they want to change it or not is a great source to unpredictable bugs. moss allows to define the behavior of invalid reads/writes, stack overflow, failed allocations, define how much memory should the heap arena use, how much memory every function receives for its stack frame, what the program should do when stuck in a dead state/endless loop, and above all, be able to make a program that never unexpectedly crashes.

[4]: <https://www.gingerbill.org/article/2018/09/05/exceptions-and-why-odin-will-never-have-them/> "exceptions - and why odin will never have them"

## imperative functionalism
idea borrowed from Flix, demonstrated on [this](https://www.youtube.com/watch?v=2LSOqikNqxM&t=1237s) talk. it means all side effects are bounded in the type system in such a way that is predictable and enforced by the compiler where and by what a specific kind of side effect may occur. this also means that outside a function, no side effect can occur. no global state, no runtime-evaluated data. only constant, immutable data.

## linear types
linear types are a underused concept from linear logic. in this case, the linear/lollipop arrow operator that, in simpler terms, says that things can be used once, at least once and only once. all heap-allocated data is a linear type. that means once you return a record or a list from a function, it is read from the original stack frame of the source function and then copied to the current stack frame. it only lives in that stack, unless its returned and, consequentially copied in a new frame. it also applies slightly differently to scopes. inner scopes must explicitly require external namespaces to be able to read them. the only exception are if/else blocks that their defined, local variables only exist to them.

## EBNF language description
```
program = 'named', namespace, ';', { 'using', namespace, ';'}, { constant definition } ;

definition = { encapsulated keyword }, namespace, operator, keyword, { expression }, ';' ;
parameter definition = namespace, operator, keyword, { expression } ;

expression = { namespace }, operator, expression | namespace | literal, ';'
           | peimitive type keyword, literal | namespace, ';'
           | statement keyword, { expresison }, scope
           | user-defined keyword, scope
           | namespace, '(', { expression }, ')'
           | 'fn', { '{', namespace, '=', type notation , '}' }, '(', { parameter definition }, ')', { effect notation }, type notation, scope
           | definition
           | expression ;

type notation = '{', 'nil' | definition | primitive type keyword, '}' ;

effect notation = effect type keyword, { '>' effect type keyword } ;

scope = '{', { expression } , '}', ';'

literal = number | string | built-in constant ;

operator =  '?'  |  '!'  |  '~'  | '&' | '|'  | '<<' | '>>'
         | '=='  | '/='  |  '>'  | '<' | '>=' | '<='
         | '+='  | '-='  |  '='  | '+' | '-'  | '*'  | '/'  | '%'
         | 'and' | 'or'  | 'not' |
         | '..'  | '...' | 'in'  ;

encapsulated keyword = 'extrn' | 'immut' ;

primitive type keyword = 'bool'
                       | 'str'  | 'cstr'
                       | 'int'  | 'u16' | 'u32' | 'u64'
                       | 'i16'  | 'i32' | 'i64'
                       | 'rat'  | 'r64' ;

user-defined keyword =  'fn' | 'rec' | 'enu' ;

statement keyword = 'if' | 'else' | 'for' | 'match' ;

effect type keyword = 'IO' | 'FS' | 'BM' ;

built-in constant = 'T' | 'F' | 'nil' ;
```

## destructive read
when assigning something to something else, the expression itself returns the old value of the assigned variable. this is called _destructive read_ and is borrowed from [pony][3].

# further reading/watching
- [Failure is Always an Option - Dylan Beattie - NDC Copenhagen 2022](https://www.youtube.com/watch?v=Vk2fi7NZ3OQ)
- [Computer Science - Brian Kernighan on successful language design](https://www.youtube.com/watch?v=Sg4U4r_AgJU)
- [Unison: A Friendly Programming Language from the Future Part 1 • Runar Bjarnason • YOW! 2021](https://www.youtube.com/watch?v=Adu75GJ0w1o)
- [Linear types make performance more predictable](https://www.tweag.io/blog/2017-03-13-linear-types/)
- [The Art of Code - Dylan Beattie](https://www.youtube.com/watch?v=6avJHaC3C2U)
- [The Perfect Language • Bodil Stokke • YOW! 2017](https://www.youtube.com/watch?v=vnv8MGIN7A8)
- [Mathematical model and implementation of rational processing](https://www.sciencedirect.com/science/article/pii/S0377042716302187)
- [Extended Backus–Naur form - Wikipedia](https://en.wikipedia.org/wiki/Extended_Backus%E2%80%93Naur_form)