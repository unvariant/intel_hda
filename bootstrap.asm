_bootstrap:
    push ds                ; save real mode
 
    lgdt [unreal.desc]     ; load gdt register
 
    mov  eax, cr0          ; switch to pmode by
    or al,1                ; set pmode bit
    mov  cr0, eax
    jmp 0x8:.pmode
 
.pmode:
    mov  bx, 0x10          ; select descriptor 2
    mov  ds, bx            ; 10h = 10000b
 
    and al,0xFE            ; back to realmode
    mov  cr0, eax          ; by toggling bit again
    jmp 0x0:.unreal
 
.unreal:
    pop ds                 ; get back old segment

    BATCH equ 64

    mov edi, AUDIO_FILE_BUFFER
    mov esi, ADDRESS(AUDIO_FILE_START - BOOT_START) / 512
    mov ebx, AUDIO_FILE_SECTORS
load_audio_file:
    push edi
    push ecx
    push ebx
    push esi

    mov edi, BOOT_END
    mov ecx, BATCH
    cmp ecx, ebx
    cmovg ecx, ebx
    call int_13h_disk_read

    pop esi
    pop ebx
    pop ecx
    pop edi

    add esi, BATCH

    mov edx, BOOT_END
    mov ecx, BATCH * 512 / 4
.copy:
    mov eax, dword [edx]
    mov dword [edi], eax
    add edx, 4
    add edi, 4
    dec ecx
    jnz .copy

    sub ebx, BATCH
    jg  load_audio_file

protected_mode:
    lgdt [gdt.desc]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp 0x08:stage_2

 
unreal:  dd 0,0        ; entry 0 is always unused
.code:   db 0xff, 0xff, 0, 0, 0, 10011010b, 00000000b, 0
.flat:   db 0xff, 0xff, 0, 0, 0, 10010010b, 11001111b, 0
.end:
.desc:
   dw .end - unreal - 1   ;last byte in table
   dd unreal              ;start of table