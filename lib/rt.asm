segment .rod
    stdin dd 0
    stdout dd 1
    stderr dd 2
    
    t.unt dd 0xcafe00

    empty.str:
        dq 8
        db 0
    empty.arr:
        dq 16
        dq 0
        db 0
segment .text
global stdin
global stdout
global stderr

global t.unt

global empty.str
global empty.arr

global read
global write

global alloc
global free
global copy
global strlset
global strcpy
global strcmp
global memset

global absb
global absh
global absw
global absl

global exit

; write = fn(handler : u32, data : str) : u32
write:
    push rsi
    mov ecx, edi
    xor rdi, rdi        ; clear residual bytes
    mov edi, ecx
    mov rdx, [rsi]      ; gets length
    sub rdx, 8
    add rsi, 8
    mov rax, 1          ; system call (write)
    syscall             ; calls it
    pop rsi
    ret

; read = fn(handler : u32, buff : str) : u32
read:
    push rsi
    mov ecx, edi
    xor rdi, rdi        ; clear residual bytes
    mov edi, ecx
    mov rdx, [rsi]      ; gets input max length
    sub rdx, 8
    add rsi, 8
    mov rax, 0          ; system call (read)
    syscall             ; calls it
    pop rsi
    ret

; alloc = fn(len : u64) : raw
alloc:
    mov rsi, rdi        ; get memory size
    xor rdi, rdi        ; clear register for null
    mov rdx, 7          ; prot
    mov r10, 22h        ; MAP_ANONYMOUS | MAP_PRIVATE
    mov rax, 09h        ; mmap syscall
    syscall
    ret

; free = fn(ptr : raw) : unit
free:
    push rdi
    xor rdx, rdx
    mov edx, [rdi]      ; get length from pointer
    mov rsi, rdx
    mov rax, 0bh        ; munmap syscall
    syscall
    lea rax, t.unt
    pop rdi
    ret

; copy = fn(dest : raw, src : raw, size : u64) : raw
copy:
    push rdi
    push rsi

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
    pop rsi
    pop rdi
    ret

; strcpy = fn(dest : str, size : u64) : unit
strlset:
    mov [rdi], rsi
    lea rax, t.unt
    ret

; strcpy = fn(dest : str, src : str, size : u64) : unit
strcpy:
    push rdi
    push rsi
    push rdx

    add rdi, 8
    add rsi, 8
    call copy

    pop rdx
    pop rsi
    pop rdi
    mov [rdi], rdx
    lea rax, t.unt
    ret

; strcmp = fn(a : str, b : str) : u8
strcmp:
    push rdi
    push rsi
    push rbx

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
        pop rbx
        pop rsi
        pop rdi
        mov rax, 0
        ret
    .t:
        pop rbx
        pop rsi
        pop rdi
        mov rax, 1
        ret

; memset = fn(dest : raw, src : u8, size : u64) : unit
memset:
    push rdi
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
    pop rdi
    lea rax, t.unt
    ret

; absb = fn(num : i8) : u8
absb:
    xor rax, rax
    xor rbx, rbx
    mov bx, di
    mov al, bl
    sar bl, 7
    xor al, bl
    sub al, bl
    ret

; absh = fn(num : i16) : u16
absh:
    xor rax, rax
    xor rbx, rbx
    mov bx, di
    mov ax, di
    sar bx, 15
    xor ax, bx
    sub ax, bx
    ret

; absw = fn(num : i32) : u32
absw:
    xor rax, rax
    xor rbx, rbx
    mov ebx, edi
    mov eax, edi
    sar ebx, 31
    xor eax, ebx
    sub eax, ebx
    ret

; absl = fn(num : i64) : 64
absl:
    mov rbx, rdi
    mov rax, rdi
    sar rbx, 63
    xor rax, rbx
    sub rax, rbx
    ret

; exit = fn(code : u32) : never
exit:
    mov rax,  3ch
    syscall
