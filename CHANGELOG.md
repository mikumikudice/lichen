new features
- none

bugfixes
- fixed bug with segfault on io::printf/str::format using too short formatting strings
- fixed compilation failure with void functions' scopes ending in `unreachable`
- fixed conv::from_i64 and conv::from_u64

correct behavior assert
- prohibit modulo operator on floating point types
- lots of fixes regarding edge cases with polymorphic effects
- added assertion for symbol collision/overwrite during linking
- added simple borrow checker to prohibit reassignment of arrays with currently active slices

others
- small improvements on the compiler code
- added error reporting on union tag mismatches
- removed debug IR leftovers

breaking changes
- numeric literals are no longer considered a subtype of floating point types in the matter of union variants
- removed %u variant from fmt::format

standard library changes
- implemented floating point printing to io::printf family
