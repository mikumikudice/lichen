global puts
global gets
global alloc

segment .bss
    resb

segment .text
puts:
    mov edx, [eax]      ; gets length
    mov ecx, eax        ; gets msg
    add ecx, 4
    mov ebx, 1          ; tells that it's an output call
    mov eax, 4          ; system call (write)
    int 80h             ; calls it
    ret

gets:
    push eax
    mov ecx, eax         ; gets output address
    add ecx, 4
    mov edx, [eax]       ; gets output max length
    mov ebx, 0           ; tells that it's an input call
    mov eax, 3           ; system call (read)
    int 80h              ; calls it

    mov ebx, eax
    pop eax
    mov [eax], ebx
    ret

alloc:

