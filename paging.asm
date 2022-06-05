    [BITS 32]
;;; wrote this code because I wasnt sure whether or not the type of memory
;;; the intel hda audio configuration space needed, using paging I made the pages
;;; uncachable and that did not seem to make much of a difference so I removed the code
PD_ADDR equ 0x800000
PT_ADDR equ 0x801000
PRESENT equ 1
RW      equ 1 << 1
PCD     equ 1 << 4
;;; identity map first 16 MB of memory
    mov edi, PD_ADDR
    mov ebx, PT_ADDR | PCD | RW | PRESENT
    mov ecx, 4
.setup_page_directory:
    mov dword [edi], ebx
    add ebx, 0x1000
    add edi, 4
    dec ecx
    jnz .setup_page_directory

    mov edi, PT_ADDR
    mov ebx, 0x000000 | PCD | RW | PRESENT
;;; 4 PD entries were created
;;; each corresponding table contains 1024 entries
;;; therefore 4096 entries will need to be filled
    mov ecx, 4096
.setup_page_tables:
    mov dword [edi], ebx
    add ebx, 0x1000
    add edi, 4
    dec ecx
    jnz .setup_page_tables

    mov eax, 0x800000
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000001
    mov cr0, eax

map_hda_mmio:
    push edi
    push ebx
    mov edi, dword [hda.mmio]
    shr edi, 22
    push edi
    mov ebx, edi
    shl ebx, 12
    add ebx, PT_ADDR
    push ebx
    or ebx, PCD | RW | PRESENT
    mov ecx, 2
    shl edi, 2
    add edi, PD_ADDR
.setup_PD_entries:
    mov dword [edi], ebx
    add ebx, 0x1000
    add edi, 4
    dec ecx
    jnz .setup_PD_entries

    pop edi
    pop ebx
    shl ebx, 22
    or ebx, PCD | RW | PRESENT
    mov ecx, 2048
.setup_PT_entries:
    mov dword [edi], ebx
    add ebx, 0x1000
    add edi, 4
    dec ecx
    jnz .setup_PT_entries

    pop ebx
    pop edi
    ret