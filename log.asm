    [BITS 32]

SCROLL_BUFFER equ 0x300000

;;; ebp+0x08 -> string
puts:
    push    ebp
    mov     ebp,    dword [esp + 0x08]
    push    ebp
    call print
    pop     eax
    call flush
    pop     ebp
    ret
    
;;; ebp+0x10.. -> parameters
;;; ebp+0x0C -> number of paramters
;;; ebp+0x08 -> format string

printf:
    push ebp
    mov ebp, esp
    pusha

    mov eax, dword [ebp+0x0C]
    shl eax, 2
    test eax, eax
    jz .no_arguments
    
.copy_parameters:
    mov edx, [ebp+0x0C+eax]
    push edx
    sub eax, 4
    cmp eax, 0
    jge .copy_parameters

.format:
    push printf_buffer
    mov eax, dword [ebp+0x08]
    push eax
    call format

    add esp, 0x0C
    mov eax, dword [ebp+0x0C]
    lea esp, [esp+eax*4]

    push printf_buffer
    call print
.done:
    pop eax

    call flush

    popa
    leave
    ret

.no_arguments:
    mov     eax,    dword [ebp + 0x08]
    push    eax
    call    print
    jmp     .done

printf_buffer: times 1024 db 0
;;; when you want print to write directly to
;;; video memory swap out SCROLL_BUFFER for 0xB8000
buffer: dd SCROLL_BUFFER

;;; ebp+0x08 -> string
print:
    push    ebp
    mov     ebp,    esp
    pusha

    mov     ecx,    dword [write_offset]
    mov     esi,    dword [ebp + 0x08]
    mov     edi,    dword [buffer]
.loop:
    lodsb
    test    al,     al
    jz      .done

    cmp     al,     `\n`
    jnz     .copy
.newline:
    dec     ecx
    mov     eax,    ecx
    mov     ebx,    80
    xor     edx,    edx
    div     ebx
    sub     ecx,    edx
    add     ecx,    80
    jmp     .loop

.copy:
    mov     byte [edi + ecx * 2], al
    mov     byte [edi + ecx * 2 + 1], TERM_COLOR
    inc     ecx

    jmp     .loop

.done:
    mov     dword [write_offset], ecx

    popa
    leave
    ret

flush:
    pusha
    mov     ax,     (TERM_COLOR << 8) |  0x20
    mov     edi,    0xB8000
    mov     ecx,    80 * (25 - HELP_LINES)
    rep     stosw

    mov     edx,    dword [screen_offset]
    mov     edi,    0xB8000
    lea     esi,    [SCROLL_BUFFER + edx * 2]
    mov     ecx,    80 * (25 - HELP_LINES)
    rep     movsw

    popa
    ret

help_banner:
    pusha
    cli

    mov     eax,    dword [write_offset]
    mov     edx,    dword [buffer]
    mov     dword [write_offset], 80 * (25 - HELP_LINES)
    mov     dword [buffer], 0xB8000

    push    0
    push    _help_banner
    call    printf
    add     esp,    8

    mov     dword [write_offset], eax
    mov     dword [buffer], edx

    sti
    popa
    ret

HELP_LINES equ 3
_help_banner:
    db 0xd5
    times 78 db 0xcd
    db 0xb8, 0x0a
    db 0xb3
.start:
    db ` J: SCROLL DOWN - K: SCROLL UP`
    times (78 - ($ - .start)) db 0x20
    db 0xb3, 0x0a
    db 0xd4
    times 78 db 0xcd
    db 0xbe, 0x0a
    db 0

write_offset: dd 0
screen_offset: dd 0