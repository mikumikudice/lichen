new features
- user-defined named effects

bugfixes
- make break and next work within while loops

correct behavior assert
- asserts for underliving data within aggregated types

others
- make tailcalls only evaluate as terminals when not in branches
- improve array IR emitting to avoid long compilation times on large arrays

breaking changes
- now all effect tags must be declared beforehand
- update on syntax for polymorphic effects using named local declarations (aplies only to function declaration)
- now you cannot assign allocated data to records or arrays that are not lifetimed as well

standard library changes
- none
