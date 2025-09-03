.data
.section ".rodata"
.balign 16
.globl rt.zero
// generic zeroed value to strings and arrays
rt.zero:
	.quad 0
    .quad 0
    .quad 0

.data
.section ".rodata"
.balign 16
.globl rt.stdin
// internal runtime definition of standard input file handle
rt.stdin:
	.int 0

.data
.section ".rodata"
.balign 16
.globl rt.stdout
// internal runtime definition of standard output file handle
rt.stdout:
	.int 1

.data
.section ".rodata"
.balign 16
.globl rt.stderr
// internal runtime definition of standard error file handle
rt.stderr:
	.int 2

.data
.balign 16
.globl rt.errmsg
// internal runtime handle for the last error message
rt.errmsg:
    .quad 0
    .quad 0

.data
.balign 16
.globl rt.errmsgset
rt.errmsgset:
    .int 0

.data
.balign 16
.globl rt.errno
// internal runtime handle for the last errno code
rt.errno:
    .int 0

.data
.balign 16
.globl rt.args
// internal runtime handle for the argv
rt.args:
    .quad 0
    .quad 0

// only receives arguments and returns nothing
.section ".text.rt.debug", "ax"
.balign 16
.globl rt.debug
rt.debug:
    ret

.type rt.debug, @function
.size rt.debug, .-rt.debug

// reads a string from an given file descriptor
// returns an errno in case of error as a negative value
// prototype: fn(handle u32, mut buff []u8) i32
.section ".text.rt.read", "ax"
.balign 16
.globl rt.read
rt.read:
    push   %rdx
    push   %rsi
    mov    (%rsi),%rdx
    mov    0x8(%rsi),%rsi
    mov    $0x0,%eax
    syscall
    pop    %rsi
    pop    %rdx
    mov    %eax,(rt.errno)
    ret

.type rt.read, @function
.size rt.read, .-rt.read

// prints a string to a given file descriptor
// returns an errno in case of error as a negative value
// prototype: fn(handle u32, data str) i32
.section ".text.rt.write", "ax"
.balign 16
.globl rt.write
rt.write:
    push   %rsi
    push   %rdx
    mov    (%rsi),%rdx
    mov    0x8(%rsi),%rsi
    mov    $0x1,%eax
    syscall
    cmp    $0,%eax
    jl     rt.write.err
    pop    %rdx
    pop    %rsi
    ret
rt.write.err:
    mov    %eax,(rt.errno)
    pop    %rdx
    pop    %rsi
    ret

.type rt.write, @function
.size rt.write, .-rt.write

// opens a given file and returns its file descriptor as a positive value
// returns an errno in case of error as a negative value
// prototype: fn(filepath cstr, flags u32, mode u32) i32
.section ".text.rt.open", "ax"
.balign 16
.globl rt.open
rt.open:
    mov    $0x2,%eax
    syscall
    mov    %eax,(rt.errno)
    ret

.type rt.open, @function
.size rt.open, .-rt.open

// closes a given file descriptor
// returns an errno in case of error as a negative value
// prototype: fn(handle u32) i32
.section ".text.rt.close", "ax"
.balign 16
.globl rt.close
rt.close:
    mov    $0x3,%eax
    syscall
    mov    %eax,(rt.errno)
    ret

.type rt.close, @function
.size rt.close, .-rt.close

// allocates memory on the heap and returns a pointer to it as a positive value
// returns an errno in case of error as a negative value
// prototype: fn(size u64) uintptr
.section ".text.rt.alloc", "ax"
.balign 16
.globl rt.alloc
rt.alloc:
    push   %rdi
    push   %rsi
    push   %rdx
    push   %r10
    push   %r9
    push   %r8
    xor    %r9,%r9
    mov    $-1,%r8
    mov    %rdi,%rsi
    xor    %rdi,%rdi
    mov    $0x3,%edx
    mov    $0x02,%r10d
    or     $0x20,%r10d
    mov    $0x9,%eax
    syscall
    mov    %eax,(rt.errno)
    pop    %r8
    pop    %r9
    pop    %r10
    pop    %rdx
    pop    %rsi
    pop    %rdi
    cmp    $0x0,%rax
    jl     rt.alloc.err
    ret
    rt.alloc.err:
    xor    %rax,%rax
    ret

.type rt.alloc, @function
.size rt.alloc, .-rt.alloc

// frees a given heap-allocated memory pointer
// returns an errno in case of error as a negative value
// prototype: fn(pointer u64, length u64) unit
.section ".text.rt.free", "ax"
.balign 16
.globl rt.free
rt.free:
    mov    $0xb,%eax
    syscall
    ret

.type rt.free, @function
.size rt.free, .-rt.free

.section ".text.rt.copy", "ax"
.balign 16
.globl rt.copy
rt.copy:
    push   %rdi
    push   %rsi
    push   %rdx
    rt.copy.rep:
    cmp    $0,%rdx
    je     rt.copy.done
    mov    (%rsi),%al
    mov    %al,(%rdi)
    dec    %rdx
    inc    %rdi
    inc    %rsi
    jmp    rt.copy.rep
    rt.copy.done:
    pop    %rdx
    pop    %rsi
    pop    %rdi
    ret

.type rt.copy, @function
.size rt.copy, .-rt.copy

.section ".text.rt.copyh", "ax"
.balign 16
.globl rt.copyh
rt.copyh:
    push   %rdi
    push   %rsi
    push   %rdx
    rt.copyh.rep:
    cmp    $0,%rdx
    je     rt.copyh.done
    mov    (%rsi),%ax
    mov    %ax,(%rdi)
    dec    %rdx
    add    $2,%rdi
    add    $2,%rsi
    jmp    rt.copyh.rep
    rt.copyh.done:
    pop    %rdx
    pop    %rsi
    pop    %rdi
    ret

.type rt.copyh, @function
.size rt.copyh, .-rt.copyh

.section ".text.rt.copyw", "ax"
.balign 16
.globl rt.copyw
rt.copyw:
    push   %rdi
    push   %rsi
    push   %rdx
    rt.copyw.rep:
    cmp    $0,%rdx
    je     rt.copyw.done
    mov    (%rsi),%eax
    mov    %eax,(%rdi)
    dec    %rdx
    add    $4,%rdi
    add    $4,%rsi
    jmp    rt.copyw.rep
    rt.copyw.done:
    pop    %rdx
    pop    %rsi
    pop    %rdi
    ret

.type rt.copyw, @function
.size rt.copyw, .-rt.copyw

.section ".text.rt.copyl", "ax"
.balign 16
.globl rt.copyl
rt.copyl:
    push   %rdi
    push   %rsi
    push   %rdx
    rt.copyl.rep:
    cmp    $0,%rdx
    je     rt.copyl.done
    mov    (%rsi),%rax
    mov    %rax,(%rdi)
    dec    %rdx
    add    $8,%rdi
    add    $8,%rsi
    jmp    rt.copyl.rep
    rt.copyl.done:
    pop    %rdx
    pop    %rsi
    pop    %rdi
    ret

.type rt.copyl, @function
.size rt.copyl, .-rt.copyl

.section ".text.rt.idx_argv", "ax"
.balign 16
.globl rt.idx_argv
rt.idx_argv:
    endbr64
    pushq %rbp
    movq %rsp, %rbp
    movq rt.args(%rip), %rax
    cmpq %rax, %rdi
    jb rt.idx_argv.ok
    subq $16, %rsp
    movq %rsp, %rcx
    movq $-1, (%rcx)
    movq (%rcx), %rax
    movq 8(%rcx), %rdx
    jmp rt.idx_argv.fail
rt.idx_argv.ok:
    movq rt.args+8(%rip), %rax
    movq (%rax, %rdi, 8), %rax
    subq $16, %rsp
    movq %rsp, %rcx
    movq $1, (%rcx)
    movq %rax, 8(%rcx)
    movq (%rcx), %rax
    movq 8(%rcx), %rdx
rt.idx_argv.fail:
    movq %rbp, %rsp
    subq $0, %rsp
    leave
    ret

.type rt.idx_argv, @function
.size rt.idx_argv, .-rt.idx_argv

.section ".text.rt.idx_argv_unsafe", "ax"
.balign 16
.globl rt.idx_argv_unsafe
rt.idx_argv_unsafe:
    endbr64
    movq rt.args+8(%rip), %rax
    movq (%rax, %rdi, 8), %rax
    ret

.type rt.idx_argv_unsafe, @function
.size rt.idx_argv_unsafe, .-rt.idx_argv_unsafe
/* end function idx_argv_unsafe */

// removes a given file by unlinking its filesytem node
// returns an errno in case of error as a negative value
// prototype: fn(filepath) i32
.section ".text.rt.unlink", "ax"
.balign 16
.globl rt.unlink
rt.unlink:
    mov    $0x57,%eax
    syscall
    mov    %eax,(rt.errno)
    ret

.type rt.unlink, @function
.size rt.unlink, .-rt.unlink

// renames a given file to a new filename, moving it from directories if needed.
// returns an errno in case of error as a negative value
// prototype: fn(oldnamepath cstr, newnamepath cstr) i32
.section ".text.rt.rename", "ax"
.balign 16
.globl rt.rename
rt.rename:
    mov    $0x52,%eax
    syscall
    mov    %eax,(rt.errno)
    ret

.type rt.rename, @function
.size rt.rename, .-rt.rename

// halts execution and sets exit code to the given value
// prototype: fn(code u32) never
.section ".text.rt.exit", "ax"
.balign 16
.globl rt.exit
rt.exit:
    mov    $0x3c,%eax
    syscall
    ud2

.type rt.exit, @function
.size rt.exit, .-rt.exit

// compares to strings and returns a non-zero value if equal, zero otherwise
// prototype: fn(a str, b str) u8
.section ".text.rt.strcmp", "ax"
.balign 16
.globl rt.strcmp
rt.strcmp:
    push   %rdi
    push   %rsi
    push   %rbx
    push   %rcx
    push   %rdx
    // same string
    cmp    %rdi,%rsi
    je     rt.strcmp.t
    // load length
    mov    (%rdi),%rbx
    mov    (%rsi),%rcx
    // not the same length
    cmp    %rcx,%rbx
    jne    rt.strcmp.f
    mov    %rbx,%rdx
    mov    0x8(%rdi),%rdi
    mov    0x8(%rsi),%rsi
    // compare each byte until the end of mismatch
    rt.strcmp.rpt:
    cmp    $0x0,%rdx
    je     rt.strcmp.t
    mov    (%rdi),%bl
    mov    (%rsi),%cl
    cmp    %cl,%bl
    jne    rt.strcmp.f
    inc    %rdi
    inc    %rsi
    dec    %rdx
    jmp    rt.strcmp.rpt
    rt.strcmp.f:
    mov    $0x0,%eax
    pop    %rdx
    pop    %rcx
    pop    %rbx
    pop    %rsi
    pop    %rdi
    ret
    rt.strcmp.t:
    mov    $0x1,%eax
    pop    %rdx
    pop    %rcx
    pop    %rbx
    pop    %rsi
    pop    %rdi
    ret

.type rt.strcmp, @function
.size rt.strcmp, .-rt.strcmp

// creates a string from a byte array
// prototype: fn(mut bytes []u8) str
.section ".text.rt.btoa", "ax"
.balign 16
.globl rt.btoa
rt.btoa:
    endbr64
    subq   $16,%rsp
    movq   (%rdi),%rdx
    movq   %rdi,%rax
    addq   $8,%rax
    movq   %rax,8(%rsp)
    movl   $0,%eax
    movl   $0,%ecx
rt.btoa.rep:
    cmpq   %rdx, %rcx
    jae    rt.btoa.end
    movq   8(%rdi),%rsi
    cmpl   $0,%esi
    jz     rt.btoa.end
    addq   $1,%rax
    addq   $1,%rcx
    jmp    rt.btoa.rep
rt.btoa.end:
    movq   %rax,0(%rsp)
    movq   0(%rsp),%rax
    movq   8(%rsp),%rdx
    addq   $16,%rsp
    ret

.type rt.btoa, @function
.size rt.btoa, .-rt.btoa
