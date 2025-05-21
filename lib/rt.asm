.data
.balign 16
.globl rt_zero
rt_zero:
	.quad 0

.data
.balign 16
.globl rt_stdin
rt_stdin:
	.int 0

.data
.balign 16
.globl rt_stdout
rt_stdout:
	.int 1

.data
.balign 16
.globl rt_stderr
rt_stderr:
	.int 2

.section ".text.rt_gets", "ax"
.balign 16
.globl rt_gets
rt_gets:
    push   %rdx
    push   %rsi
    mov    (%rsi),%rdx
    add    $0x10,%rsi
    mov    $0x0,%eax
    syscall
    cmp    $0x0,%rax
    jl     rt_gets.err
    pop    %rsi
    pop    %rdx
    mov    %rax,0x8(%rsi)
    ret
    rt_gets.err:
    mov    %rax,%rdi
    sub    $0x7e,%rdi
    callq  rt_exit

.type rt_gets, @function
.size rt_gets, .-rt_gets

.section ".text.rt_puts", "ax"
.balign 16
.globl rt_puts
rt_puts:
    push   %rdi
    push   %rsi
    push   %rcx
    push   %rdx
    mov    %edi,%ecx
    xor    %rdi,%rdi
    mov    %ecx,%edi
    mov    0x8(%rsi),%rdx
    add    $0x10,%rsi
    mov    $0x1,%eax
    syscall
    cmp    $0x0,%rax
    jl     rt_puts.err
    pop    %rdx
    pop    %rcx
    pop    %rsi
    pop    %rdi
    ret
    rt_puts.err:
    mov    %rax,%rdi
    sub    $0x7e,%rdi
    callq  rt_exit

.type rt_puts, @function
.size rt_puts, .-rt_puts

.section ".text.rt_open", "ax"
.balign 16
.globl rt_open
rt_open:
    mov    $0x2,%eax
    syscall
    ret

.type rt_open, @function
.size rt_open, .-rt_open

.section ".text.rt_close", "ax"
.balign 16
.globl rt_close
rt_close:
    mov    $0x3,%eax
    syscall
    ret

.type rt_close, @function
.size rt_close, .-rt_close

.section ".text.rt_alloc", "ax"
.balign 16
.globl rt_alloc
rt_alloc:
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
    jl     rt_alloc.err
    pop    %r8
    pop    %r9
    pop    %r10
    pop    %rdx
    pop    %rsi
    pop    %rdi
    mov    %rdi,(%rax)
    ret
    rt_alloc.err:
    mov    %rax,%rdi
    sub    $0x7e,%rdi
    callq  rt_exit

.type rt_alloc, @function
.size rt_alloc, .-rt_alloc

.section ".text.rt_free", "ax"
.balign 16
.globl rt_free
rt_free:
    push   %rsi
    mov    (%rdi),%rsi
    mov    $0xb,%eax
    syscall
    cmp    $0x0,%rax
    jl     rt_free.err
    pop    %rsi
    ret
    rt_free.err:
    mov    %rax,%rdi
    sub    $0x7e,%rdi
    callq  rt_exit

.type rt_free, @function
.size rt_free, .-rt_free

.section ".text.rt_unlink", "ax"
.balign 16
.globl rt_unlink
rt_unlink:
    mov    $0x57,%eax
    syscall
    ret

.type rt_unlink, @function
.size rt_unlink, .-rt_unlink

.section ".text.rt_rename", "ax"
.balign 16
.globl rt_rename
rt_rename:
    mov    $0x52,%eax
    syscall
    ret

.type rt_rename, @function
.size rt_rename, .-rt_rename

.section ".text.rt_exit", "ax"
.balign 16
.globl rt_exit
rt_exit:
    mov    $0x3c,%eax
    syscall
    ud2

.type rt_exit, @function
.size rt_exit, .-rt_exit

.section ".text.rt_strcmp", "ax"
.balign 16
.globl rt_strcmp
rt_strcmp:
    push   %rdi
    push   %rsi
    push   %rbx
    push   %rcx
    push   %rdx
    mov    0x8(%rdi),%rbx
    mov    0x8(%rsi),%rcx
    cmp    %rcx,%rbx
    jne    rt_strcmp.f
    mov    %rbx,%rdx
    add    $0x10,%rdi
    add    $0x10,%rsi
    rt_strcmp.rpt:
    cmp    $0x0,%rdx
    je     rt_strcmp.t
    mov    (%rdi),%bl
    mov    (%rsi),%cl
    cmp    %cl,%bl
    jne    rt_strcmp.f
    inc    %rdi
    inc    %rsi
    dec    %rdx
    jmp    rt_strcmp.rpt
    rt_strcmp.f:
    mov    $0x0,%eax
    pop    %rdx
    pop    %rcx
    pop    %rbx
    pop    %rsi
    pop    %rdi
    ret
    rt_strcmp.t:
    mov    $0x1,%eax
    pop    %rdx
    pop    %rcx
    pop    %rbx
    pop    %rsi
    pop    %rdi
    ret

.type rt_strcmp, @function
.size rt_strcmp, .-rt_strcmp
