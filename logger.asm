    [BITS 32]
    
;;; ebp+0x10.. -> parameters
;;; ebp+0x0C -> number of paramters
;;; ebp+0x08 -> format string

printf:
    push ebp
    mov ebp, esp
    mov eax, dword [ebp+0x0C]
    shl eax, 2
.copy_parameters:
    mov edx, [ebp+0x0C+eax]
    push edx
    sub eax, 4
    cmp eax, 0
    jge .copy_parameters
    push printf_buffer
    mov eax, dword [ebp+0x08]
    push eax
    call format
    add esp, 0x0C
    mov eax, dword [ebp+0x0C]
    lea esp, [esp+eax*4]
    push printf_buffer
    call puts
    leave
    ret

printf_buffer: times 1024 db 0

;;; ebp+0x08 -> string
puts:
    push ebp
    mov ebp, esp
    push esi
    push edi
    push ebx
    mov esi, dword [ebp+0x08]
    mov eax, dword [cursor_offset]
    mov ecx, 0xCCCCCCCD
    ;;; not enough precision to perform reciprocal multiplication with 1/160
    ;;; instead use 1/10 and divide by 16 using right shift
    mov bh, TERM_COLOR
.loop:
    mov bl, byte [esi]
    inc esi
    cmp bl, `\n`
    jnz .copy
    add eax, 160
    mul ecx
    shr edx, 3 + 4
    mov eax, edx
    shl edx, 2
    add edx, eax
    shl edx, 2
    lea eax, [edx*8]
    jmp .next
.copy:
    mov word [0xB8000+eax], bx
    add eax, 2
.next:
    cmp byte [esi], 0
    jnz .loop
    mov dword [cursor_offset], eax
    pop ebx
    pop edi
    pop esi
    leave
    ret

cursor_offset: dd 0