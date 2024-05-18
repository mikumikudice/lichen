segment .rod
    stdin dd 0
    stdout dd 1
    stderr dd 2

segment .text
extern alloc

global read
global write

global stdin
global stdout
global stderr

; read = fn(handle : u32, size: u32) : @str
read:
    push rdi
    push rsi

    mov rdi, rsi
    call alloc

    pop rdx              ; gets input max length
    pop rdi              ; tells that it's an input call
    mov dword [rax], edx
    mov rsi, rax         ; gets input address
    add rsi, 4
    mov rax, 0           ; system call (read)
    syscall              ; calls it
    ret

; write = fn(handle : u32, data : str) : u32
write:
    xor rdx, rdx
    mov edx, [rsi]      ; gets length
    add rsi, 4
    mov rax, 1          ; system call (write)
    syscall             ; calls it
    ret
