new features
- unions
- interactions with switch and for loop for enums

bugfixes
- fixed parser rejecting enums if variant list does not end in a comma
- fixed misplacing and misuse of error in error reporting regarding non-callable values
- fixed crash on functions returning enums and other type related issues
- fixed mutable string variables holding literals

correct behavior assert
- assert for attempt to assign to function call

others
- assert for given compilation source file being a directory

breaking changes
- none

standard library changes
- none
