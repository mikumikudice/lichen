segment .rod
    rt_stdin dd 0
    rt_stdout dd 1
    rt_stderr dd 2
    empty.str:
        dq 8
        db 0
    empty.arr:
        dq 16
        dq 0
        db 0

segment .data
    buffb db 0
    time_t:
        dq 0
        dq 0
    stko dq 0 ; stack offset
    last dq 0 ; last stackframe

segment .text
global rt_stdin
global rt_stdout
global rt_stderr

global empty.str
global empty.arr

global rt_dummy

global rt_gets
global rt_puts
global rt_open
global rt_close
global rt_putb

global rt_alloc
global rt_free
global rt_setlen
global rt_copy
global rt_strcmp
global rt_strcpy
global rt_strrev

global rt_sleep
global rt_unlink
global rt_exit


; fn(...) unit
rt_dummy:
    ret

; fn(filepath str, flags u32, mode u32) u32
rt_open:
    push rdi
    push rcx
    push rdx
    push rsi

    mov rcx, [last]
    cmp rbp, rcx
    jz .off
    mov [stko], rsi
    mov [last], rbp
    jmp .fnsh
    .off:
    mov rcx, [stko]
    add rcx, rsi
    mov [stko], rcx
    .fnsh:

    mov rcx, rsp
    dec rcx
    mov [rcx], byte 0
    sub rcx, [stko]

    mov rdx, [rdi + 8]
    add rdi, 16
    mov rsi, rdi
    mov rdi, rcx
    call rt_copy

    mov rdi, rcx
    pop rsi
    pop rdx
    mov rax, 2
    syscall
    pop rcx
    pop rdi
    ret

; fn(handle u32) unit
rt_close:
    mov rax, 3
    syscall
    ret

; fn(handler u32, buffer @str) unit
rt_gets:
    push rdx
    push rsi
    mov rdx, [rsi]      ; get max buffer capacity
    add rsi, 16         ; get buffer content address
    mov rax, 0h
    syscall
    
    cmp rax, 0
    jl .err
    pop rsi
    pop rdx
    mov [rsi + 8], rax  ; assign buffer current size
    ret

    .err:
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
    mov rax, 1h         ; system call (write)
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
    call rt_exit

; fn(handler u32, data u8) u32
rt_putb:
    push rdi
    push rsi
    push rcx
    push rdx
    mov ecx, edi
    xor rdi, rdi        ; clear residual bytes
    mov edi, ecx
    mov rdx, rsi
    mov [buffb], dl 
    mov rsi, buffb      ; get data source
    mov rdx, 1          ; gets length
    mov rax, 1h         ; system call (write)
    syscall             ; calls it
    pop rdx
    pop rcx
    pop rsi
    pop rdi
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
    call rt_exit

; fn(ptr u64) unit
rt_free:
    push rdx
    push rsi
    xor rsi, rsi        ; clear unused argument
    mov rax, 0bh        ; munmap syscall
    syscall

    cmp rax, 0
    jl .err

    pop rsi
    pop rdx
    ret
    .err:
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

; fn(dest str, len u64) unit
rt_setlen:
    mov [rdi], rsi
    ret

; fn(dest str, src str, size u64) unit
rt_strcpy:
    push rdi
    push rsi
    push rdx

    add rdi, 8
    add rsi, 8
    call rt_copy

    pop rdx
    pop rsi
    pop rdi
    xor rax, rax
    ret

; fn(src str) str
rt_strrev:
    push rbx
    push rcx
    push rdi
    push rsi
    push rdx
    xor rax, rax
    xor rbx, rbx

    push rdi
    mov rcx, [rdi]
    add rcx, 8
    
    cmp rcx, 0
    jz .nil

    add rdi, 8
    mov rsi, rdi
    mov rdx, rdi
    add rdx, 8
    add rdx, rcx
        
    .next:
        mov bl, [rdi]
        cmp bl, 0
        jz .end
        inc rdi
        cmp rdx, rdi
        jnz .next
    .end:
        dec rdi
        xor rbx, rbx
    .rpt:
        mov al, [rsi]
        mov bl, [rdi]
        mov byte [rsi], bl
        mov byte [rdi], al
        dec rdi
        inc rsi
        cmp rsi, rdi
        jl .rpt
    pop rax
    pop rdx
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret
    .nil:
        pop rax
        pop rdx
        pop rsi
        pop rdi
        pop rcx
        pop rbx
        ret

; fn(sec u64, mili u64) unit
rt_sleep:
    push rdi
    mov rax, time_t
    mov [rax], rdi
    add rax, 8
    mov [rax], rsi
    mov rdi, [time_t]
    mov eax, 23h
    syscall
    pop rdi
    ret

; fn(filepath str) i32
rt_unlink:
    push rdi
    push rsi
    push rdx

    mov rsi, rdi
    mov rdx, [rdi]
    add rsi, 8

    mov rdi, rbp
    mov byte [rdi], 0
    sub rdi, rdx
    dec rdi
    call rt_copy

    pop rdx
    pop rsi
    mov rax, 57h
    syscall

    cmp rax, 0
    jnz .err
    pop rdi
    ret
    .err:
    mov rdi, rax
    call rt_exit

; fn(old_filepath str, new_filepath str) i32
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
