segment .data
    stdin dd 0
    stdout dd 1
    stderr dd 2
segment .text
global stdin
global stdout
global stderr

global read
global write

global alloc
global free
global copy

global exit

; write = fn(handler : u32, data : str) : u32
write:
    mov ecx, edi
    xor rdi, rdi        ; clear residual bytes
    mov edi, ecx
    mov rdx, [rsi]      ; gets length
    add rsi, 8
    mov rax, 1          ; system call (write)
    syscall             ; calls it
    ret

; read = fn(handler : u32, buff : str) : u32
read:
    mov ecx, edi
    xor rdi, rdi        ; clear residual bytes
    mov edi, ecx
    add rsi, 8
    mov rdx, [rsi]      ; gets input max length
    mov rax, 0          ; system call (read)
    syscall             ; calls it
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
    xor rdx, rdx
    mov edx, [rdi]      ; get length from pointer
    mov rsi, rdx
    mov rax, 0bh        ; munmap syscall
    syscall
    ret

; copy = fn(dest : raw, src : raw, size : u64) : unit
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

; exit = fn(code : u32) : never
exit:
    mov rax,  3ch
    syscall
