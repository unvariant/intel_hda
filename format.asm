    [BITS 32]
    
;;; ebp+0x14.. -> parameters
;;; ebp+0x10 -> number of parameters
;;; ebp+0x0C -> buffer
;;; ebp+0x08 -> format string
format:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    sub esp, 4

    mov esi, dword [ebp+0x08]
    mov edi, dword [ebp+0x0C]
    mov ebx, 0x14
.loop:
    lodsb
    cmp al, '%'
    jnz .copy
    push esi
    call atoi
    pop esi
    push eax
    push edi
    mov ecx, dword [ebp+ebx]
    add ebx, 4
    push ecx
    xor eax, eax
    lodsb
    sub al, 0x61
    call dword [.switch+eax*4]
    mov edi, dword [esp+0x04]
    add esp, 0x0C
    jmp .check
.copy:
    stosb
.check:
    cmp byte [esi], 0
    jnz .loop
    mov byte [edi], 0

.end:
    add esp, 4
    pop edi
    pop esi
    pop ebx
    leave
    ret

.unimplemented:
    add esp, 0x0C
    ret

    align 8
.switch:
dd .unimplemented    ; a
dd .unimplemented    ; b
dd .unimplemented    ; c
dd itoa              ; d
dd .unimplemented    ; e
dd .unimplemented    ; f
dd .unimplemented    ; g
dd .unimplemented    ; h
dd .unimplemented    ; i
dd .unimplemented    ; j
dd .unimplemented    ; k
dd .unimplemented    ; l
dd .unimplemented    ; m
dd .unimplemented    ; n
dd .unimplemented    ; o
dd .unimplemented    ; p
dd .unimplemented    ; q
dd .unimplemented    ; r
dd _strcpy            ; s
dd .unimplemented    ; t
dd .unimplemented    ; u
dd .unimplemented    ; v
dd .unimplemented    ; w
dd _xtoa              ; x
dd .unimplemented    ; y
dd .unimplemented    ; z

;;; ebp+0x08 -> string
;;; returns number in eax
atoi:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    mov esi, dword [ebp+0x08]
    xor ebx, ebx
    xor eax, eax
.loop:
    lodsb         ;;; load next char, might be numeric
    cmp al, 0x30
    jb .end
    cmp al, 0x39
    ja .end
    lea ebx, [ebx*4+ebx-0x18]
    shl ebx, 1
    add ebx, eax
    jmp .loop
.end:
    mov eax, ebx
    dec esi
    mov dword [ebp+0x08], esi
    pop esi
    pop ebx
    leave
    ret

;;; ebp+0x0C -> buffer
;;; ebp+0x08 -> number
;;; returns number of bytes written (not including null terminator)
itoa:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    sub esp, 16
    mov eax, dword [ebp+0x08]
    mov edi, dword [ebp+0x0C]
    mov ecx, 0xCCCCCCCD
    lea esi, [esp+16]
.loop:
    mov ebx, eax
    mul ecx
    shr edx, 3
    mov eax, edx
    shl edx, 2
    add edx, eax
    shl edx, 1
    sub ebx, edx
    add bl, 0x30
    dec esi
    mov byte [esi], bl
    test eax, eax
    jnz .loop
    lea ecx, [esp+16]
    sub ecx, esi
    mov eax, ecx
    rep movsb
    mov byte [edi], 0 ;;; null terminator
    mov dword [ebp+0x0C], edi
    add esp, 16
    pop edi
    pop esi
    pop ebx
    leave
    ret

;;; ebp+0x10 -> number of bytes to transfer
;;; ebp+0x0C -> destination
;;; ebp+0x08 -> source
_strcpy:
    push ebp
    mov ebp, esp
    push esi
    push edi
    mov ecx, dword [ebp+0x10]
    mov edi, dword [ebp+0x0C]
    mov esi, dword [ebp+0x08]
    test ecx, ecx
    jz .implicit_length
.explicit_length:
    rep movsb
    jmp .end
.implicit_length:
    movsb
    cmp byte [edi-1], 0
    jnz .implicit_length
    dec edi
.end:
    mov dword [ebp+0x0C], edi
    pop edi
    pop esi
    leave
    ret

;;; ebp+0x10 -> number of bytes to write
;;; ebp+0x0C -> buffer
;;; ebp+0x08 -> number
;;; returns number of bytes written in eax
_xtoa:
    push ebp
    mov ebp, esp
    push edi
    mov edx, dword [ebp+0x08]
    mov edi, dword [ebp+0x0C]
    mov ecx, dword [ebp+0x10]
    mov eax, 8
    shl ecx, 2
    ror edx, cl
    shr ecx, 2
    cmovz ecx, eax
.loop:
    mov eax, edx
    shr eax, 28
    shl edx, 4
    cmp eax, 9
    ja .alpha
    add eax, 0x30
    jmp .next
.alpha:
    add eax, 0x37
.next:
    stosb
    dec ecx
    jg .loop
    mov byte [edi], 0
    mov dword [ebp+0x0C], edi
    pop edi
    leave
    ret