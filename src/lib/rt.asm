segment .text
global exit
; exit = fn(code : u32) : unit
exit:
    mov rax,  3ch
    syscall
