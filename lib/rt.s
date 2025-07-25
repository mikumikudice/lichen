.data
.balign 16
.globl rt.zero
// generic zeroed value to strings and arrays
rt.zero:
	.quad 0
    .quad 0

.data
.balign 16
.globl rt.stdin
// internal runtime definition of standard input file handle
rt.stdin:
	.int 0

.data
.balign 16
.globl rt.stdout
// internal runtime definition of standard output file handle
rt.stdout:
	.int 1

.data
.balign 16
.globl rt.stderr
// internal runtime definition of standard error file handle
rt.stderr:
	.int 2

.data
.balign 16
.globl rt.args
// internal runtime handle for the argv
rt.args:
    .quad 0
    .quad 0
    .quad 0

// reads a string from an given file descriptor
// returns an errno in case of error as a negative value
// prototype: fn(handle u32, buff mut str) i32
.section ".text.rt.read", "ax"
.balign 16
.globl rt.read
rt.read:
    push   %rdx
    push   %rsi
    mov    (%rsi),%rdx
    add    $0x10,%rsi
    mov    $0x0,%eax
    syscall
    pop    %rsi
    pop    %rdx
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
    ret

.type rt.close, @function
.size rt.close, .-rt.close

// allocates memory on the heap and returns a pointer to it as a positive value
// returns an errno in case of error as a negative value
// prototype: fn(size u64) i64
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
    xor    %r8,%r8
    mov    %rdi,%rsi
    add    $0x8,%rsi
    xor    %rdi,%rdi
    mov    $0x7,%edx
    mov    $0x22,%r10d
    mov    $0x9,%eax
    syscall
    cmp    $0x0,%rax
    jl     rt.alloc.err
    pop    %r8
    pop    %r9
    pop    %r10
    pop    %rdx
    pop    %rsi
    pop    %rdi
    mov    %rdi,(%rax)
    ret
    rt.alloc.err:
    mov    %rax,%rdi
    sub    $0x7e,%rdi
    callq  rt.exit

.type rt.alloc, @function
.size rt.alloc, .-rt.alloc

// frees a given heap-allocated memory pointer
// returns an errno in case of error as a negative value
// prototype: fn(pointer u64) i32
.section ".text.rt.free", "ax"
.balign 16
.globl rt.free
rt.free:
    push   %rsi
    mov    (%rdi),%rsi
    mov    $0xb,%eax
    syscall
    cmp    $0x0,%rax
    jl     rt.free.err
    pop    %rsi
    ret
    rt.free.err:
    mov    %rax,%rdi
    sub    $0x7e,%rdi
    callq  rt.exit

.type rt.free, @function
.size rt.free, .-rt.free

.section ".text.rt.lea", "ax"
.balign 16
.globl rt.lea
rt.lea:
    mov    (%rdi),%rax
    ret

.type rt.lea, @function
.size rt.lea, .-rt.lea

// removes a given file by unlinking its filesytem node
// returns an errno in case of error as a negative value
// prototype: fn(filepath) i32
.section ".text.rt.unlink", "ax"
.balign 16
.globl rt.unlink
rt.unlink:
    mov    $0x57,%eax
    syscall
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
    mov    (%rdi),%rbx
    mov    (%rsi),%rcx
    cmp    %rcx,%rbx
    jne    rt.strcmp.f
    mov    %rbx,%rdx
    mov    0x8(%rdi),%rdi
    mov    0x8(%rsi),%rsi
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
