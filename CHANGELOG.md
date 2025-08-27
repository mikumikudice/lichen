new features
- implemented switch cases
- implemented while loop
- implemented defer statement
- implemented dynamic arrays and slicing
- implemented os::args
- implemented `break` and `next`
- implemented propagation error messages
- implemented polymorphic effects and first-class functions
- implemented per-field mutability marking for record fields
- extended valid iteration members for for-loops

bugfixes
- fixed some major memory leaks
- fixed issue with stack-allocated data loss
- fixed module variables emitting
- fixed lots of issues regarding array types
- fixed codegen for some expressions
- fixed bug where all module functions were marked as impure
- fixed array and record alignment emitting
- fixed some error hints formatting
- fixed type IR emitting issues
- fixed unary operators emitting
- fixed bug with ternary operator
- fixed allocation type hint
- fixed integer subtyping
- fixed void/return semantics
- fixed issue where the compiler would crash on an invalid for-loop iterator 
- fixed module functions emitting bugs
- fixed compiler not asserting for too few function arguments
- fixed issue where empty returns on !unit functions would produce incorrect IR
- fixed issue where compiler woudn't complain when comparing unasserted partial types with literals
- fixed tuple syntax parsing
- fixed bugs with unordered record fields assignment
- fixed assertion behavior
- fixed void/unit type variable definition assert
- fixed issues with assignment temporary's hardcoded name
- fixed parsing order for error assertion and type casting
- fixed for-loops incorrectly updating values of arrays of aggregated types
- fixed bang (boolean not) operator being invalid for boolean types
- fixed aggregated types' array unsafe indexing unwrap and loop iterations
- fixed array literal length override by the type hint
- fixed issue with global floats
- fixed dynamic allocation of records
- fixed allocations not moving arena pointer foward
- fixed array type comparison
- correctly implemented zeroed values for records, strings and arrays
- fixed some unwrapping bugs in the code emitting
- fixed missing implicit cast of array literals to slices
- fixed if blocks not emitting checking value on literals as conditions
- fixed return of unit values (on void functions)

correct behavior assert
- prohibited void & unit types for record fields and function parameters
- add type checking asserting effect tagging on FFI functions
- optimized arenas that return to append frees before returning
- improved expression parsing for indexing and field access
- implemented assertion for functions allocations being returned without a lifetime tag
- made all types to be emitted with their module name prefix
- implemented deep copy of strings on allocations
- moved all runtime constants to rodata section
- assertion for recursive module importing
- assertion for unsafe record copy on mutability mismatch
- arenas are required to be mutable in order to be used on allocations and concatenations
- cannot allocate arenas using `new ... @ arena` expression
- fixed array literal final item casting
- fixed index variable of for loops not being asserted for shadowing
- prohibited to reassign to current for-loop iterator

others
- updated BNF description for tuple unpacking
- now once error logging from asserts and tests propagate, custom logging is allowed on propagated tests
- implemented primitive tailcall optimization

breaking changes
- renamed error sentinels to `error` and `nil` instead of `fail` and `nomem`
- renamed io functions `fatal` => `panic` and `error`/`errorln` to `report`/`reportln`
- destructive-read pre-semantics deprecated
