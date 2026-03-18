new features
- none

bugfixes
- fixed bug with switch case scopes not being emitted
- fixed module types not being parsed correctly when marked as partial
- fixed issue with terminal statlement determination with else cases
- fixed issue with code emitting for some edge cases on arena free list on error bubbling
- fixed funcall codegen shadowing bug
- fixed typechecking on do effects

correct behavior assert
- added more safety checks regarding lifetimes of records and its fields when assigning to other variables
- fixed record type alignment and field type emitting issues

others
- improved union mismatch error reporting
- implemented data wrap for arrays of unions that are literals

breaking changes
- none

standard library changes
- added printf family
