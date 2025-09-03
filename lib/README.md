# about
this is the standard library for the lichen programming language provided by the lcc implementation. version 0.1.0
the stdlib versioning is independant from the compiler's.

# what is inside
## std::
provides standard, platform-dependant functions such as io, os, runtime and filesystem functions, as well as a handful set of platform-agnostic implementations of algorithms for common tasks, such as array maping, filtering, mapping, folding and sorting.

## str::
provides platform-agnostic functions for making, converting and parsing strings and string-related data, such as integer to ascii and ascii to integer functions, buffered string creation and string formatting.

## rt::
a series of platform-dependant implementations of runtime functions for each of the platforms the compiler targets in assembly. not meant for direct use. please use std::rt instead.
