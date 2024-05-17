segment .data
    atoi_bigr:
        dd 36
        db "atoi: character is greater than '9'", 10
    atoi_smlr:
        dd 36
        db "atoi: character is smaller than '0'", 10
    alloc_err:
        dd 25
        db "alloc: allocation failed", 10
    free_err:
        dd 18
        db "free: double free", 10

segment .text
global read
global write

global str_new
global str_rev
global free_str
global concat
global atoi
global itoa

global alloc
global free
global copy

global exit

; u32 write(str data)
write:
    xor rdx, rdx
    mov edx, [rdi]      ; gets length
    mov rsi, rdi        ; gets msg
    add rsi, 4
    mov rdi, 1          ; tells that it's an output call
    mov rax, 1          ; system call (write)
    syscall             ; calls it
    ret

; u64 read(str buff)
read:
    push rdi
    mov rsi, rdi         ; gets input address
    add rsi, 4
    xor rdx, rdx
    mov edx, [rdi]       ; gets input max length
    mov rdi, 0           ; tells that it's an input call
    mov rax, 0           ; system call (read)
    syscall              ; calls it
    ret

; str strnew(u64 len)
str_new:
    add rdi, 4
    push rdi
    call alloc
    pop rdx
    mov dword [rax], edx
    ret

free_str:
    xor rcx, rcx
    mov ecx, [rdi]
    add ecx, 4
    mov [rdi], ecx
    call free
    ret

; str rev(str val)
str_rev:
    xor rax, rax
    xor rbx, rbx
    xor rcx, rcx

    push rdi
    mov ecx, [rdi]
    
    cmp rcx, 0
    jz .nil

    add rdi, 4
    mov rsi, rdi
    mov rdx, rdi
    add rdx, 4
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
    ret
    .nil:
        pop rax
        ret

; str concat(str lft, str rgt)
concat:
    push rsi
    push rdi

    xor rcx, rcx
    mov ecx, [rdi]
    add ecx, [rsi]
    mov rdi, rcx
    call str_new

    mov r10, rax
    pop rsi

    xor rdx, rdx
    mov edx, [rsi]
    add rsi, 4

    mov rdi, rax
    add rdi, 4
    call copy

    pop rsi

    xor rdx, rdx
    mov edx, [rsi]
    add rsi, 4

    mov rdi, rax
    call copy
    
    mov rax, r10
    ret    


; u64 atoi(str num)
atoi:
    xor rcx, rcx
    mov rbx, [rdi]
    mov rdx, rdi
    add rdx, 4
    xor rax, rax
    mov al, [rdx]

    .rpt:
        cmp rax, 39h
        jg .bigr

        cmp rax, 30h
        jl .smlr

        sub rax, 30h

        push rbx
        sub rbx, 2
        cmp rbx, 0
        je .skp

        push rcx
        push rdx
        mov rsi, 10
        .pow:
            mul rsi
            dec rbx

            cmp rbx, 0
            jne .pow

        pop rdx
        pop rcx

        .skp:
        pop rbx

        add rcx, rax
        dec rbx

        cmp rbx, 0
        je .done
        
        inc rdx
        xor rax, rax
        mov al, [rdx]

        cmp rbx, 1
        jne .rpt

    .done:
        mov rax, rcx
        ret

    .bigr:
        mov rdi, atoi_bigr
        call write
        mov rdi, 1
        call exit

    .smlr:
        mov rdi, atoi_smlr
        call write
        mov rdi, 1
        call exit

; str itoa(u64 num)
itoa:
    mov rax, rdi
    xor rbx, rbx
    mov ebx, [rsi]
    mov rdi, rsi
    add rdi, 4

    mov rcx, 10
    .gen:
        xor rdx, rdx
        div rcx
        add rdx, 48
        mov byte [rdi], dl
        inc rdi

        cmp rax, 0
        jz .done
        jmp .gen
    .done:
        mov rdi, rsi
        call str_rev
        ret

; void* alloc(u64 len)
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

    mov rdi, alloc_err
    call write

    pop rdi
    mov rax, -1
    mul rdi

    mov rdi, rax
    call exit

; void free(void* ptr)
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
    mov rdi, free_err
    call write
    mov rdi, 1
    call exit

; void* copy(void* dest, void* src, u64 size)
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

; never exit(u64 code)
exit:
    mov rax,  3ch
    syscall
