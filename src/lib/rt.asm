segment .rod
    bad_eq:
        dd 49
        db "runtime bug: mismatch of types during comparison", 10
segment .text
extern write

global ok
global nok
global eq
global neq
global gt
global ls
global ge
global le

global exit

; ok = fn(arg : raw, arg_t : type) : u8
ok:
    ; lft is unit
    cmp rdx, 0xcafe0000
    je .false
    cmp rdx, 0xcafe0001
    je .array
    ; TODO: composite types
    jmp .prim

    .array:
    mov rcx, [rdi]
    cmp rcx, 0
    jnz .true
    jmp .false

    .prim:
    cmp rdi, 0
    jz .false
    jmp .true

    .true:
    mov rax, 1
    ret
    .false:
    mov rax, 0
    ret

; nok = fn(arg : raw, arg_t : type) : u8
nok:
    call ok
    cmp rax, 0
    jz .false
    jmp .true

    .true:
    mov rax, 1
    ret
    .false:
    mov rax, 0
    ret

; eq = fn(lft : raw, rgt : raw, lft_t : type, rgt_t : type) : u8
eq:
    ; lft is unit
    cmp rdx, 0xcafe0000
    je .lft_unit
    cmp rdx, 0xcafe0001
    je .array
    ; TODO: composite types
    jmp .lft_prim

    .lft_unit:
    ; rgt is also unit
    cmp r10, 0xcafe0000
    je .true
    jmp .false

    .lft_prim:
    ; rgt is unit
    cmp r10, 0xcafe0000
    je .false
    jmp .all_prim

    .all_unit:
    cmp rdx, r10
    je .true
    jne .false

    .array:
    cmp r10, 0xcafe0001 ; assert both arem arrays
    jne .bug

    xor rax, rax
    mov eax, [rdi]      ; get length of lft

    xor rbx, rbx
    mov ebx, [rsi]      ; get length of rgt

    cmp rax, rbx        ; compare length
    jne .false

    add rdi, 4
    add rsi, 4
    mov rcx, rax
    mov eax, [rdi]      ; get size of items of lft
    mov ebx, [rsi]      ; get size of items of rgt
    cmp eax, ebx        ; if sizes are different, then the arrays are different
    jne .false
    mov rdx, rax
    add rdi, 4
    add rsi, 4
    xor eax, eax
    xor ebx, ebx
    .rpt:
        cmp rcx, 0
        jz .true
        mov al, [rdi]
        mov bl, [rsi]
        cmp al, bl      ; compare byte by byte
        jne .false
        inc rdi
        inc rsi
        dec rcx
        jmp .rpt        ; repeat until arrays diverge or loop reaches the end
    .bug:
    mov rdi, bad_eq
    call write

    mov rdi, 1
    call exit

    .all_prim:
    cmp rdx, r10
    je .true
    jne .false

    .true:
    mov rax, 1
    ret
    .false:
    mov rax, 0
    ret

; eq = fn(lft : raw, rgt : raw, lft_t : type, rgt_t : type) : u8
neq:
    call eq
    cmp rax, 0
    jz .false
    jmp .true

    .true:
    mov rax, 1
    ret
    .false:
    mov rax, 0
    ret

; ls = fn(lft : raw, rgt : raw, lft_t : type, rgt_t : type) : u8
ls:
    ; lft is unit
    cmp rdx, 0xcafe0000
    je .bug
    cmp rdx, 0xcafe0001
    je .bug
    ; TODO: composite types
    jmp .ok

    .bug:
    mov rdi, bad_eq
    call write

    mov rdi, 1
    call exit

    .ok:
    cmp rdx, r10
    jl .true
    jmp .false

    .true:
    mov rax, 1
    ret
    .false:
    mov rax, 0
    ret

; gt = fn(lft : raw, rgt : raw, lft_t : type, rgt_t : type) : u8
gt:
    ; lft is unit
    cmp rdx, 0xcafe0000
    je .bug
    cmp rdx, 0xcafe0001
    je .bug
    ; TODO: composite types
    jmp .ok

    .bug:
    mov rdi, bad_eq
    call write

    mov rdi, 1
    call exit

    .ok:
    cmp rdx, r10
    jg .true
    jmp .false

    .true:
    mov rax, 1
    ret
    .false:
    mov rax, 0
    ret

; le = fn(lft : raw, rgt : raw, lft_t : type, rgt_t : type) : u8
le:
    ; lft is unit
    cmp rdx, 0xcafe0000
    je .bug
    cmp rdx, 0xcafe0001
    je .bug
    ; TODO: composite types
    jmp .ok

    .bug:
    mov rdi, bad_eq
    call write

    mov rdi, 1
    call exit

    .ok:
    cmp rdx, r10
    jle .true
    jmp .false

    .true:
    mov rax, 1
    ret
    .false:
    mov rax, 0
    ret

; ge = fn(lft : raw, rgt : raw, lft_t : type, rgt_t : type) : u8
ge:
    ; lft is unit
    cmp rdx, 0xcafe0000
    je .bug
    cmp rdx, 0xcafe0001
    je .bug
    ; TODO: composite types
    jmp .ok

    .bug:
    mov rdi, bad_eq
    call write

    mov rdi, 1
    call exit

    .ok:
    cmp rdx, r10
    jge .true
    jmp .false

    .true:
    mov rax, 1
    ret
    .false:
    mov rax, 0
    ret

; exit = fn(code : u32) : unit
exit:
    mov rax,  3ch
    syscall
