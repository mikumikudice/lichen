; usage:
; ==============================================
; input order (max 6 arguments):
; EDI ESI EDX ECX EBX EAX
; ==============================================
; output order (max 6 return values):
; EAX EBX ECX EDX ESI EDI

segment .bss
    buff resb 1

segment .text
global getc, putc, puts, exit

; getc returns a byte char read from the input stream
; returns word char in EAX
getc:
    pusha
    mov   ecx ,  buff

    mov   edx ,  01h                ; number of to-be-read bytes
    mov   ebx ,  02h                ; set as an input call
    mov   eax ,  03h                ; syscall number
    int   80h

    mov   eax ,  buff               ; set return value to default output register

    popa
    ret

; putc(char)
; putc prints one char to the stdout
putc:
    pusha

    mov   ecx ,  eax                ; move the given argument to the required register
    mov   edx ,  1                  ; set syscall to output operation
    mov   ebx ,  1                  ; number of to-be-printed bytes
    mov   eax ,  4                  ; syscall number
    int   80h

    popa
    ret

gets:
    pusha
    mov   ecx ,  buff

    mov   edx ,  01h                ; number of to-be-read bytes
    mov   ebx ,  02h                ; set as an input call
    mov   eax ,  03h                ; syscall number
    int   80h

    mov   eax ,  buff               ; set return value to default output register

    popa
    ret

; puts(str)
; the string type memory layout is
; [ 32bit | ... ]
; [  len  | cnt ]
puts:
    pusha

    mov   esi ,  eax                ; get the address of the string itself
    add   esi ,  4                  ; move address pass the size of the string
    mov   ebx , [eax]               ; get the length of the string

    .prnt:                          ; print char by char
    mov   eax ,  esi                ; set the argument to the address
    call putc

    add  esi  ,  1
    sub  ebx  ,  1                  ; decrement remaining number of chars
    cmp  ebx  ,  0
    jne .prnt

    popa
    ret

; exit(code)
exit:
    mov   ebx ,  eax                ; sets exit code
    mov   eax ,  01h                ; system call (exit)
    int   80h                       ; calls it