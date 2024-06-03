segment .rod
    IO.stdin dd 0
    IO.stdout dd 1
    IO.stderr dd 2
    
    t.unt dd 0xcafe00

    empty.str:
        dq 8
        db 0
    empty.arr:
        dq 16
        dq 0
        db 0
segment .text
global IO.stdin
global IO.stdout
global IO.stderr

global t.unt

global empty.str
global empty.arr

global IO.read
global IO.write

global MEM.alloc
global MEM.free
global MEM.copy
global MEM.strlset
global MEM.strcpy
global MEM.strrev
global MEM.memset

global rt.indxb
global rt.mvtob
global rt.strcmp
global rt.absb
global rt.absh
global rt.absw
global rt.absl
global rt.exit

; write = fn(handler : u32, data : str) : u32
IO.write:
    push rsi
    push rcx
    push rdx
    mov ecx, edi
    xor rdi, rdi        ; clear residual bytes
    mov edi, ecx
    mov rdx, [rsi]      ; gets length
    sub rdx, 8
    add rsi, 8
    mov rax, 1          ; system call (write)
    syscall             ; calls it
    pop rdx
    pop rcx
    pop rsi
    ret

; read = fn(handler : u32, buff : str) : u32
IO.read:
    push rdi
    push rsi
    push rcx
    push rdx
    mov ecx, edi
    xor rdi, rdi        ; clear residual bytes
    mov edi, ecx
    mov rdx, [rsi]      ; gets input max length
    sub rdx, 8
    add rsi, 8
    mov rax, 0          ; system call (read)
    syscall             ; calls it
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    ret

; alloc = fn(len : u64) : raw
MEM.alloc:
    push rdi
    push rsi
    push rdx
    push r10
    mov rsi, rdi        ; get memory size
    xor rdi, rdi        ; clear register for null
    mov rdx, 7          ; prot
    mov r10, 22h        ; MAP_ANONYMOUS | MAP_PRIVATE
    mov rax, 09h        ; mmap syscall
    syscall
    pop r10
    pop rdx
    pop rsi
    pop rdx
    ret

; free = fn(ptr : raw) : unit
MEM.free:
    push rdi
    push rdx
    push rsi
    xor rdx, rdx
    mov edx, [rdi]      ; get length from pointer
    mov rsi, rdx
    mov rax, 0bh        ; munmap syscall
    syscall
    lea rax, t.unt
    pop rsi
    pop rdx
    pop rdi
    ret

; copy = fn(dest : raw, src : raw, size : u64) : raw
MEM.copy:
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

; strcpy = fn(dest : str, size : u64) : unit
MEM.strlset:
    mov [rdi], rsi
    lea rax, t.unt
    ret

; strcpy = fn(dest : str, src : str, size : u64) : unit
MEM.strcpy:
    push rdi
    push rsi
    push rdx

    add rdi, 8
    add rsi, 8
    call MEM.copy

    pop rdx
    pop rsi
    pop rdi
    mov [rdi], rdx
    lea rax, t.unt
    ret

; strrev = fn(src : str) : str
MEM.strrev:
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

; memset = fn(dest : raw, src : u8, size : u64) : unit
MEM.memset:
    push rdi
    push rdx
    push rcx
    cmp rdx, 0
    jz .end
    .next:
        mov rcx, rsi
        mov [rdi], cl

        inc rdi
        dec rdx

        cmp rdx, 0
        jz .end
        jmp .next
    .end:
    lea rax, t.unt
    pop rcx
    pop rdx
    pop rdi
    ret

; indxb = fn(arr : raw, idx : u64) : u8
rt.indxb:
    push rdi
    add rdi, 8
    add rdi, rsi
    xor rax, rax
    mov al, [rdi]
    pop rdi
    ret
; asetb = fn(arr : raw, idx : u64, val : u8) : unit
rt.mvtob:
    push rdi
    add rdi, 8
    add rdi, rsi
    mov [rdi], dl
    pop rdi
    lea rax, t.unt
    ret

; strcmp = fn(a : str, b : str) : u8
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
    sub rdx, 8
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

; absb = fn(num : i8) : u8
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

; absh = fn(num : i16) : u16
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

; absw = fn(num : i32) : u32
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

; absl = fn(num : i64) : 64
rt.absl:
    push rbx
    mov rbx, rdi
    mov rax, rdi
    sar rbx, 63
    xor rax, rbx
    sub rax, rbx
    pop rbx
    ret

; exit = fn(code : u32) : never
rt.exit:
    mov rax, 3ch
    syscall
