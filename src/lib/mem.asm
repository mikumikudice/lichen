segment .rod
    alloc_err:
        dd 25
        db "alloc: allocation failed", 10
    free_err:
        dd 18
        db "free: double free", 10

segment .text
extern write
extern exit

global alloc
global free
global copy

; alloc = fn(size: u32) : @raw
alloc:
    mov rsi, rdi        ; get memory size
    xor rdi, rdi        ; clear register for null
    mov rdx, 7          ; prot
    mov r10, 22h        ; MAP_ANONYMOUS | MAP_PRIVATE
    mov rax, 09h        ; mmap syscall
    syscall

    cmp rax, 0
    jl .err
    ret

    .err:
    push rax

    mov rdi, 1
    mov rsi, alloc_err
    call write

    pop rdi
    mov rax, -1
    mul rdi

    mov rdi, rax
    call exit

; free = fn(obj : @raw) : unit
free:
    cmp rdi, 0          ; check for null pointer
    jZ .err

    xor rdx, rdx
    mov edx, [rdi]      ; get length from pointer
    mov rsi, rdx
    mov rax, 0bh        ; munmap syscall
    syscall

    xor rax, rax
    ret
    .err:
    mov rdi, 1
    mov rsi, free_err
    call write
    mov rdi, 1
    call exit

; copy = fn(dest : @raw, src : raw, size : u32) : @raw
copy:
    cmp rdx, 0
    jz .end
    xor rcx, rcx
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
    ret
