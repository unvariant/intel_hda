    [ORG 0x7c00]
    [BITS 16]

    BOOT_START equ 0x7c00
    BASE_ADDR  equ BOOT_START
    global _start

_start:
    xor ax, ax
    mov es, ax
    mov ds, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    mov sp, 0x7c00

    mov al, 03h
    int 10h

    cld
    cli

;;; https://wiki.osdev.org/A20_Line
test_A20:
    in al, 0x92
    test al, 2
    jnz A20_set
    or al, 2
    and al, 0xFE
    out 0x92, al
A20_set:

;;; https://wiki.osdev.org/Unreal_Mode
;    push ds                 ; save real mode
;    lgdt [gdt.desc] ; load gdt register
;    
;    mov  eax, cr0           ; switch to pmode by
;    or al, 1                ; set pmode bit
;    mov  cr0, eax
;    
;    jmp tmp_protected_mode  ; tell 386/486 to not crash
;tmp_protected_mode:
;    mov  bx, DATA_DESC      ; select descriptor 2
;    mov  ds, bx
;    
;    and al, ~1              ; back to realmode
;    mov  cr0, eax           ; by toggling bit again
;    
;    pop ds                  ; get back old segment

;;; https://wiki.osdev.org/Disk_access_using_the_BIOS_(INT_13h)
check_int13_extensions:
    push _int13_extensions_not_supported
    mov ah, 0x41
    mov bx, 0x55aa
    mov dl, 0x80
    int 13h
    jc error
    add sp, 2

load_rest_of_bootloader:
    mov ecx, BOOT_SECTORS
    mov ebx, 128
    mov edi, 0x7e00
.loop:
    mov eax, ecx
    cmp eax, ebx
    cmovg eax, ebx
    mov word [packet.block_count], ax
    push eax
    push ebx
    push ecx
    push edi
    push _sectors_not_equal
    push ax
    push _disk_read_error
    mov ah, 0x42
    mov dl, 0x80
    xor si, si
    mov ds, si
    mov si, packet
    int 13h
    jc error
    add sp, 2
    pop ax
    cmp ax, word [packet.block_count]
    jnz error
    add sp, 2
    pop edi
    pop ecx
    pop ebx
    pop eax
    add dword [packet.block_low], eax
    sub ecx, eax
    shl eax, 9
    add edi, eax
    mov dword [packet.buffer_offset], edi
    shl word [packet.buffer_segment], 12
    ;;; loop while greater than zero
    cmp ecx, 0
    jg .loop

protected_mode:
    lgdt [gdt.desc]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp 0x08:stage_2

error:
    pop si
    mov di, 0xB800
    mov es, di
    xor di, di
    mov ah, TERM_COLOR
.loop:
    lodsb
    stosw
    cmp byte ds:[si], 0
    jnz .loop
    hlt
    jmp $

CODE_DESC equ gdt.code - gdt
DATA_DESC equ gdt.data - gdt

gdt:
.null: dq 0
.code: dw 0xffff
       dw 0
       db 0
       db 0b10011010
       db 0b11001111
       db 0
.data: dw 0xffff
       dw 0
       db 0
       db 0b10010010
       db 0b11001111
.end:  db 0
.desc: dw gdt.end - gdt
       dd gdt
       dw 0

BOOT_SECTORS equ (BOOT_END - REST_OF_BOOT_START) >> 9

packet:
.size           dw 16
.block_count    dw 0
.buffer_offset  dw 0x7e00
.buffer_segment dw 0
.block_low      dd 1
.block_high     dw 0
                dw 0

TERM_COLOR equ 0x0F

_disk_read_error:                db "int 13h disk read error.", 0
_sectors_not_equal:              db "incorrect number of sectors read", 0
_int13_extensions_not_supported: db "int 13h extensions not supported.", 0

    times 510 - ($ - $$) db 0
    dw 0xaa55
    REST_OF_BOOT_START equ $

    %include "format.asm"
    %include "logger.asm"
    ;%include "paging.asm"
    ; TODO: split pic and idt into separate files
    %include "interrupt.asm"
    %include "ihda.asm"
    %include "bootend.asm"