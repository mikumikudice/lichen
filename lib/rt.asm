segment .rod
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
segment .bss
    cstr_b resb 2048

segment .text
global empty.str
global empty.arr

global rt.dummy

global rt.gets
global rt.puts
global rt.open
global rt.close
global rt.putb

global rt.arena
global rt.free
global rt.copy
global rt.strlset
global rt.strcpy
global rt.strrev
global rt.memset

global rt.sleep
global rt.unlink
global rt.exit

global rt.indxb
global rt.mvtob
global rt.strcmp
global rt.absb
global rt.absh
global rt.absw
global rt.absl

; fn(...) unit
rt.dummy:
    ret

; fn(filepath str, flags u32, mode u32) u32
rt.open:
    push rdi
    push rcx
    push rdx
    push rsi

    mov rsi, rdi
    mov rdx, [rdi]
    add rsi, 8

    mov rdi, rbp
    mov byte [rdi], 0
    sub rdi, rdx
    dec rdi
    call rt.copy

    pop rsi
    pop rdx
    mov rax, 2
    syscall
    pop rcx
    pop rdi
    ret

; (handle u32) unit
rt.close:
    mov rax, 3
    syscall
    ret

; fn(handler u32, bz u64) str
rt.gets:
    push rcx
    push rdx
    push rsi

    mov rcx, rbp
    sub rcx, rsi
    push rcx

    mov rdx, rsi
    mov rsi, rcx
    xor rax, rax
    syscall
    
    cmp rax, 0
    jl .err
    pop rcx
    sub rcx, 8
    dec rax
    mov [rcx], rax

    mov rax, rcx
    pop rsi
    pop rdx
    pop rcx
    ret

    .err:
    call rt.exit

; fn(handler u32, data str) u32
rt.puts:
    push rdi
    push rsi
    push rcx
    push rdx
    mov ecx, edi
    xor rdi, rdi        ; clear residual bytes
    mov edi, ecx
    mov rdx, [rsi]      ; gets length
    add rsi, 8
    mov rax, 1          ; system call (write)
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
    call rt.exit

; putb = fn(handler u32, data u8) u32
rt.putb:
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
    mov rax, 1          ; system call (write)
    syscall             ; calls it
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    ret

; fn(size u64) rec { u64, u64 }
rt.arena:
    push rdi
    push rsi
    push rdx
    push r10
    push r9
    push r8
    xor r9, r9
    xor r8, r8
    mov rsi, rdi        ; get memory size
    add rsi, 16
    xor rdi, rdi        ; clear register for null
    mov rdx, 7          ; prot
    mov r10, 22h        ; MAP_ANONYMOUS | MAP_PRIVATE
    mov rax, 09h        ; mmap syscall
    syscall

    cmp rax, 0
    jl .err

    mov rdx, rax
    add rdx, 16
    mov [rax], rdx
    mov rdi, rax
    add rdi, 8
    mov [rdi], rsi
    add [rdi], rax
    pop r8
    pop r9
    pop r10
    pop rdx
    pop rsi
    pop rdi
    ret
    .err:
    call rt.exit

; fn(ptr rec { u64, u64 }) unit
rt.free:
    push rdi
    push rdx
    push rsi
    mov rdx, [rdi + 8]  ; get length from pointer
    sub rdx, rdi
    mov rsi, rdx
    mov rax, 0bh        ; munmap syscall
    syscall

    cmp rax, 0
    jl .err

    pop rsi
    pop rdx
    pop rdi
    ret
    .err:
    call rt.exit

; copy = fn(dest raw, src raw, size u64) raw
rt.copy:
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

; strcpy = fn(dest str, src str, size u64) unit
rt.strcpy:
    push rdi
    push rsi
    push rdx

    add rdi, 8
    add rsi, 8
    call rt.copy

    pop rdx
    pop rsi
    pop rdi
    mov [rdi], rdx
    xor rax, rax
    ret

; strrev = fn(src str) str
rt.strrev:
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

; sleep = fn(sec u64, mili u64) unit
rt.sleep:
    push rdi
    mov rax, time_t
    mov [rax], rdi
    add rax, 8
    mov [rax], rsi
    lea rdi, time_t
    mov eax, 23h
    syscall
    pop rdi
    ret

; unlink = fn(filepath str) i32
rt.unlink:
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
    call rt.copy

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
    call rt.exit

; rename = fn(old_filepath str, new_filepath str) i32
rt.rename:
    mov rax, 52h
    syscall
    ret

; fn(code u32) void
rt.exit:
    call rt.absw
    mov rdi, rax
    mov rax, 3ch
    syscall
    hlt

; fn(a str, b str) u8
rt.strcmp:
    push rdi
    push rsi
    push rbx
    push rcx
    push rdx

    mov rbx, [rdi]
    mov rcx, [rsi]
    cmp rbx, rcx
    jne .f
    mov rdx, rbx
    add rdi, 8
    add rsi, 8
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

; absb = fn(num i8) u8
rt.absb:
    push rbx
    xor rax, rax
    xor rbx, rbx
    mov bx, di
    mov al, bl
    sar bl, 7
    xor al, bl
    sub al, bl
    pop rbx
    ret

; absh = fn(num i16) u16
rt.absh:
    push rbx
    xor rax, rax
    xor rbx, rbx
    mov bx, di
    mov ax, di
    sar bx, 15
    xor ax, bx
    sub ax, bx
    pop rbx
    ret

; absw = fn(num i32) u32
rt.absw:
    push rbx
    xor rax, rax
    xor rbx, rbx
    mov ebx, edi
    mov eax, edi
    sar ebx, 31
    xor eax, ebx
    sub eax, ebx
    pop rbx
    ret

; absl = fn(num i64) 64
rt.absl:
    push rbx
    mov rbx, rdi
    mov rax, rdi
    sar rbx, 63
    xor rax, rbx
    sub rax, rbx
    pop rbx
    ret
