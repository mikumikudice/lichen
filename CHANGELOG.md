new features
- local variables for switch blocks
- complex chaining for record fields assignment
- array item arbitrary assignment

bugfixes
- a few issues with record fields involving partial types

correct behavior assert
- require no digit separator on numeric base prefixes
- deep-assert for halts within defers
- null-terminates all string literals to avoid any error when casting to c-strings

others
- now `unreachable` is allowed to be used in defer contexts

breaking changes
- none
