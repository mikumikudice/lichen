.section ".text._start", "ax"
.balign 16
.globl _start
_start:
   // store argc
   xor    %rdi,%rdi
   mov    (%rsp),%edi
   // store argv
   mov    %rsp,%rsi
   add    $0x8,%rsi
   mov    %rsi,%rdx
// find env
_start.loop:
   cmpq   $0x0,(%rdx)
   je     _start.end
   add    $0x8,%rdx
   jmp    _start.loop
// env found
_start.end:
   add    $0x8,%rdx
   // store argc and argv for later use
   mov    %edi,rt.args
   movq   %rsi,rt.args+8
   // call entry point
   callq  main
   hlt

.type _start, @function
.size _start, .-_start
