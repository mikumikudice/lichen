segment .data
    rt_stdin dd 0
    rt_stdout dd 1
    rt_stderr dd 2
    empty.str:
        dq 16
        dq 0
        db 0
    empty.arr:
        dq 8
        db 0

segment .text
global rt_stdin
global rt_stdout
global rt_stderr

global empty.str
global empty.arr

global rt_gets
global rt_puts
global rt_open
global rt_close

global rt_alloc
global rt_free
global rt_copy
global rt_strcmp

global rt_unlink
global rt_rename
global rt_exit

; fn(handler u32, buffer @str) unit
rt_gets:
    push rdx
    push rsi
    mov rdx, [rsi]      ; get max buffer capacity
    add rsi, 16         ; get buffer content address
    mov rax, 00h
    syscall
    
    cmp rax, 0
    jl .err
    pop rsi
    pop rdx
    mov [rsi + 8], rax  ; assign buffer current size
    ret

    .err:
    mov rdi, rax
    sub rdi, 126
    call rt_exit

; fn(handler u32, data str) u32
rt_puts:
    push rdi
    push rsi
    push rcx
    push rdx
    mov ecx, edi        ; get file descriptor
    xor rdi, rdi        ; clear residual bytes
    mov edi, ecx        ; assign file descriptor
    mov rdx, [rsi + 8]  ; gets length
    add rsi, 16         ; move to actual data address
    mov rax, 01h        ; system call (write)
    syscall             ; calls it

    cmp rax, 0
    jl .err

    pop rdx
    pop rcx
    pop rsi
    pop rdi
    ret

    .err:
    mov rdi, rax
    sub rdi, 126
    call rt_exit

; fn(filepath cstr, flags u32, mode u32) u32
rt_open:
    mov rax, 02h
    syscall
    ret

; fn(handle u32) unit
rt_close:
    mov rax, 03h
    syscall
    ret

; fn(size u64) ptr
rt_alloc:
    push rdi
    push rsi
    push rdx
    push r10
    push r9
    push r8
    xor r9, r9
    xor r8, r8
    mov rsi, rdi        ; get memory size
    add rsi, 8
    xor rdi, rdi        ; clear register for null
    mov rdx, 7          ; prot
    mov r10, 22h        ; MAP_ANONYMOUS | MAP_PRIVATE
    mov rax, 09h        ; mmap syscall
    syscall

    cmp rax, 0
    jl .err

    pop r8
    pop r9
    pop r10
    pop rdx
    pop rsi
    pop rdi

    mov [rax], rdi
    ret
    .err:
    mov rdi, rax
    sub rdi, 126
    call rt_exit

; fn(ptr u64) unit
rt_free:
    push rsi
    mov rsi, [rdi]      ; get pointer size
    mov rax, 0bh        ; munmap syscall
    syscall

    cmp rax, 0
    jl .err

    pop rsi
    ret
    .err:
    mov rdi, rax
    sub rdi, 126
    call rt_exit

; fn(dest raw, src raw, size u64) raw
rt_copy:
    push rcx
    push rdi
    push rsi
    push rdx
    cmp rdx, 0
    jz .end
    .next:
        mov cl, [rsi]
        mov [rdi], cl

        inc rdi
        inc rsi
        dec rdx

        cmp rdx, 0
        jz .end
        jmp .next
    .end:

    mov rax, rdi
    pop rdx
    pop rsi
    pop rdi
    pop rcx
    ret

; fn(filepath cstr) i32
rt_unlink:
    mov rax, 57h
    syscall
    ret

; fn(old_filepath cstr, new_filepath cstr) i32
rt_rename:
    mov rax, 52h
    syscall
    ret

; fn(code u32) void
rt_exit:
    mov rax, 3ch
    syscall
    hlt

; fn(a str, b str) u64
rt_strcmp:
    push rdi
    push rsi
    push rbx
    push rcx
    push rdx

    mov rbx, [rdi + 8]
    mov rcx, [rsi + 8]
    cmp rbx, rcx
    jne .f
    mov rdx, rbx
    add rdi, 16
    add rsi, 16
    .rpt:
        cmp rdx, 0
        jz .t
        mov bl, [rdi]
        mov cl, [rsi]
        cmp bl, cl
        jne .f
        inc rdi
        inc rsi
        dec rdx
        jmp .rpt
    .f:
        mov rax, 0
        pop rdx
        pop rcx
        pop rbx
        pop rsi
        pop rdi
        ret
    .t:
        mov rax, 1
        pop rdx
        pop rcx
        pop rbx
        pop rsi
        pop rdi
        ret
