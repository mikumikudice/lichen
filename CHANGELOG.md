new features
- none

bugfixes
- added missing bang operator on some emitting paths
- fixed FFI call with aggregated parameters

correct behavior assert
- none

others
- now aggregated types of known size are not required to be mutable on FFI functions
- now, only mutable parameters are passed by reference, all others are passed by value

breaking changes
- none

standard library changes
- none
