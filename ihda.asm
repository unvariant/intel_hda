    [BITS 32]
STACK_TOP equ 0x200000

stage_2:
    mov ax, DATA_DESC
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, STACK_TOP    ; 2 MB

    call PIC_init
    call IDT_init_interrupts

    call find_hda
    call hda_init

    call test_audio

    mov esi, dword [hda.mmio]
    mov dword [esi+DPUBASE], 0
    mov dword [esi+DPLBASE], address(_debug_buffer) | 1   ; address macro defined in interrupt.asm
    sub esp, 0x28
.loop:
    mov dword [cursor_offset], 0x780
    mov eax, dword [_debug_buffer+28]
    mov dword [esp+0x24], eax
    mov eax, dword [_debug_buffer+24]
    mov dword [esp+0x20], eax
    mov eax, dword [_debug_buffer+20]
    mov dword [esp+0x1C], eax
    mov eax, dword [_debug_buffer+16]
    mov dword [esp+0x18], eax
    mov eax, dword [_debug_buffer+12]
    mov dword [esp+0x14], eax
    mov eax, dword [_debug_buffer+8]
    mov dword [esp+0x10], eax
    mov eax, dword [_debug_buffer+4]
    mov dword [esp+0x0C], eax
    mov eax, dword [_debug_buffer+0]
    mov dword [esp+0x08], eax
    mov dword [esp+0x04], 8
    mov dword [esp+0x00], _debug_info
    call printf
    jmp .loop
    add esp, 0x28

hang:
    push _hang
    call puts
    hlt
    jmp $

;;; calling convention used follows the calling convention specified in the system V abi for i386
;;; paramters are passed on the stack in reverse order, such that the first paramter
;;; is the lowest on the stack, functions preserve ebp, ebx, edi, esi and can use
;;; eax, ecx, edx as scratch. esp is the stack register.

;;; simple and terrible malloc used for allocating memory for widget data
;;; data is not meant to be freed at all
;;; avoids clobbering any registers other than provided register
%macro MALLOC 2
    mov %1, dword [heap_addr]   ; load heap address
    add %1, %2                  ; calculate next heap address
    xchg %1, dword [heap_addr]  ; swap
%endmacro
_tmp: db `tmp:%x\n.`, 0
test_audio:
    push ebp
    mov ebp, esp
    push ebx

    mov eax, dword [hda.mmio]
    movzx ecx, word [eax+0x00]
    shr cx, 8
    movzx edx, cl
    and dl, 0x0f
    push edx
    mov ebx, edx
    shl ebx, 5
    shr cl, 4
    push ecx
    push 2
    push _stream_io_info
    call printf
;;; ebx contains offset to first output stream descriptor
    add ebx, 0x80
    add ebx, dword [hda.mmio]

    push eax
    push ebx
    push 1
    push _tmp
    call printf
    add esp, 0x0C
    pop eax

;;; set all SSYNC bits to stop all streams
    mov dword [eax+SSYNC], 0x3FFFFFFF
;;; turn output stream off by clearing run bit
    and dword [ebx], ~0b10
;;; begin reset stream
    or dword [ebx], 1
.confirm_begin_stream_reset:
    test dword [ebx], 1
    jz .confirm_begin_stream_reset
;;; end reset stream
    and dword [ebx], ~1
.confirm_end_stream_reset:
    test dword [ebx], 1
    jnz .confirm_end_stream_reset
;;; set stream number
    or dword [ebx], 1 << 20
;;; set cyclic buffer length
    mov dword [ebx+0x08], BDL_LEN
;;; set last valid index, once index is reached controller will restart at index 0
    mov byte [ebx+0x0C], 1
;;; set stream format
    mov word [ebx+0x12], STREAM_FORMAT
;;; set BLD lower address
    mov dword [ebx+0x18], _buffer_descriptor_list
    mov dword [ebx+0x1C], 0
;;; set audio convert format
;;; hard coded values for testing
    mov dword [esp+0x08], 0x0200 | 0  ; set format verb
    mov dword [esp+0x04], 0x02       ; node index 2, audio output
    mov dword [esp+0x00], 0x00       ; codec 0
    call codec_query
    test eax, edx
    jz .next0
    push _set_converter_format_fail
    call puts
    jmp hang
.next0:
    mov dword [esp+0x08], 0x70700 | 0b1000000     ; set pin widget control verb, bit 6 set to enable pin complex
    mov dword [esp+0x04], 0x03                    ; node index 3, pin complex
    ;;; codec address already on stack
    call codec_query
    test eax, edx
    jz .next1
    push _enable_pin_complex_fail
    call puts
    jmp hang
.next1:
    mov dword [esp+0x08], 0x70600 | (1 << 4) | 1        ; set converter stream and channel, stream 1, channel 1
    mov dword [esp+0x04], 0x02                          ; node index 2, audio output
    ;;; codec address already on stack
    call codec_query
    mov dword [esp+0x08], 0x70500 | 0                   ; set D0 (fully powered) state
    ;;; node index already on stack
    ;;; codec address already on stack
    call codec_query
    mov dword [esp+0x08], 0x30000 | 0                   ; unmute audio output
    ;;; node index already on stack
    ;;; codec address already on stack
    call codec_query
    mov dword [ebx+SSYNC], 0        ; enable stream 1 in ssync
    or dword [ebx], 0b10             ; set stream run bit

    add esp, 0x10
    pop ebx
    leave
    ret
    ret

CORB_init:
    mov eax, dword [hda.mmio]
.find_CORB_size:
    movzx ecx, byte [eax+CORBSIZE]
    mov dl, cl
    shr cl, 4
;;; upper 4 bits contains possible options for number of entries
;;; bit 7 -> reserved
;;; bit 6 -> 256 entries
;;; bit 5 -> 16 entries
;;; bit 4 -> 2 entries
;;; lower 2 bits contains the chosen size
;;; 0b11 -> reserved
;;; 0b10 -> 256 entries
;;; 0b01 -> 16 entries
;;; 0b00 -> 2 entries
    test cl, cl
    jnz .find_mssb
    push _no_CORB_size
    call puts
    jmp hang
.find_mssb:
    bsr cx, cx
.set_CORB_size:
    and dl, 0b11111100
    or dl, cl
    mov byte [eax+CORBSIZE], dl
    mov cx, word [sizes+ecx*2]
    mov word [corb.size], cx
    dec cx
    mov word [corb.size_mask], cx
.reset_CORB_rp:
    mov dx, word [eax+CORBRP]
    or dx, 0x8000
    mov word [eax+CORBRP], dx       ;;; set bit 15 of CORBRP to begin reset
.wait_CORB_rp_reset:
    mov dx, word [eax+CORBRP]
    test dx, 0x8000                 ;;; hardware sets bit 15 when reset is finished
    jz .wait_CORB_rp_reset
    mov dx, word [eax+CORBRP]
    and dx, ~0x8000                 ;;; software verifies reset by clearing bit 15
    mov word [eax+CORBRP], dx
    mov dx, word [eax+CORBRP]
    test dx, 0x8000  ;;; then checking the bit to make sure it is clear
    jnz .reset_CORB_rp_fail
.reset_CORB_wp:
    mov word [eax+CORBWP], 0
.set_CORB_buffer:
;;; set CORB buffer address
    mov dword [eax+CORBLBASE], _CORB_buffer
    mov dword [eax+CORBUBASE], 0
;;; CORB on
.CORB_on:
    mov byte [eax+CORBCTL], 0b10
    ret

.reset_CORB_rp_fail:
    push _reset_CORB_rp_fail
    call puts
    jmp hang

RIRB_init:
    mov eax, dword [hda.mmio]
.find_CORB_size:
    movzx ecx, byte [eax+RIRBSIZE]
    mov dl, cl
    shr cl, 4
;;; upper 4 bits contains possible options for number of entries
;;; bit 7 -> reserved
;;; bit 6 -> 256 entries
;;; bit 5 -> 16 entries
;;; bit 4 -> 2 entries
;;; lower 2 bits contains the chosen size
;;; 0b11 -> reserved
;;; 0b10 -> 256 entries
;;; 0b01 -> 16 entries
;;; 0b00 -> 2 entries
    test cl, cl
    jnz .find_mssb
    push _no_RIRB_size
    call puts
    jmp hang
.find_mssb:
    bsr cx, cx
.set_RIRB_size:
    and dl, 0b11111100
    or dl, cl
    mov byte [eax+RIRBSIZE], dl
    mov cx, word [sizes+ecx*2]
    mov word [rirb.size], cx
    dec cx
    mov word [rirb.size_mask], cx
.reset_RIRB_wp:
;;; setting bit 15 should clear the RIRB write pointer
    mov dx, word [eax+RIRBWP]
    or dx, 0x8000
    mov word [eax+RIRBWP], dx
    mov dx, word [eax+RIRBWP]
;;; set RIRB buffer address
    mov dword [eax+RIRBLBASE], _RIRB_buffer
    mov dword [eax+RIRBUBASE], 0
;;; allow interrupts
    mov dl, byte [eax+RIRBCTL]
    or dl, 1
    mov byte [eax+RIRBCTL], dl
;;; QEMU mishandles this number, 0 is supposed to be interpreted as 256
;;; but QEMU interprets it as zero
    mov byte [eax+RINTCNT], 0xff
;;; RIRB on
    or byte [eax+RIRBCTL], 0b10
    ret

;;; TODO: have functions assume eax holds hda.mmio?
;;; esp+0x04 -> query
CORB_write:
    mov eax, dword [hda.mmio]
    movzx edx, word [eax+CORBWP]            ; get CORB write pointer
    movzx ecx, word [corb.size_mask]
    inc edx
    and edx, ecx                            ; edx = (idx + 1) % size
    mov ecx, dword [esp+0x04]               ; ecx = command
    mov dword [_CORB_buffer+edx*4], ecx     ; write command into buffer
    mov word [eax+CORBWP], dx               ; update wp
.wait:
    mov dx, word [eax+CORBWP]
    cmp dx, word [eax+CORBRP]
    jnz .wait                               ; wait until rp == wp
    ret

;;; returns response in edx:eax
RIRB_read:
    mov eax, dword [hda.mmio]
    movzx edx, word [rirb.rp]               ; get rirb read pointer
    xor ecx, ecx
.wait:
    mov cx, word [eax+RIRBWP]
    cmp dx, cx
    jz .wait                                ; wait until rp != wp
.read:
    mov eax, dword [_RIRB_buffer+ecx*8]     ; lower bits in eax
    mov edx, dword [_RIRB_buffer+ecx*8+4]   ; upper bit in edx
    mov word [rirb.rp], cx                  ; update rp
    ret

;;; ebp+0x10 -> command | data
;;; ebp+0x0C -> node index
;;; ebp+0x08 -> codec number
codec_query:
    push ebp
    mov ebp, esp
    movzx eax, byte [ebp+0x08]
    shl eax, 8
    mov al, byte [ebp+0x0C]
    shl eax, 20
    or eax, dword [ebp+0x10]
    push eax
    call CORB_write
    add esp, 4
    call RIRB_read
    leave
    ret

;;; ebp+0x08 -> pointer to widget struct
connection_list_info:
    push ebp
    mov ebp, esp
    push esi
    push ebx
    mov eax, dword [ebp+0x08]
    xor ebx, ebx
    test byte [eax+W_LONGFORM], 1
    setnz bl
    inc bl                     ; bl = if longform { 2 } else { 1 };
    mov dl, bl
    shl dl, 3
    mov cl, 32
    sub cl, dl
    mov edx, 0xFFFFFFFF
    shr edx, cl
    movzx ecx, byte [eax+W_CONLEN]
    mov eax, dword [eax+W_CONLIST]
    
;;; eax -> pointer to connection list
;;; ecx -> length of connection list
;;; ebx -> increment amount
;;; edx -> mask
.loop:
    mov esi, dword [eax]
    add eax, ebx
    and esi, edx
    push eax
    push ecx
    push edx
    push esi
    push 1
    push _connection_list_entry
    call printf
    add esp, 0x0C
    pop edx
    pop ecx
    pop eax
    dec ecx
    jnz .loop
    pop ebx
    pop esi
    leave
    ret

;;; ebp+0x08 -> pointer to widget struct
add_widget_entry:
    push ebp
    mov ebp, esp
    mov eax, dword [ebp+0x08]
    movzx edx, byte [eax+W_TYPE]
    lea edx, dword [widgets+edx*4]
.loop:
    mov ecx, dword [edx]
    test ecx, ecx
    cmovz ecx, eax
    mov dword [edx], ecx
    mov edx, ecx
    jnz .loop
.end:
    leave
    ret

;;; NOTE: default configuration details only matter to pin complex widgets

;;; ebp+0x0C -> nid
;;; ebp+0x08 -> coded
widget_info:
    push ebp
    mov ebp, esp
    push edi
    push esi
    push ebx
    MALLOC edi, W_SIZE
    push 0x00                  ; padding
    push 0xF0000 | 0x09        ; get paramter
    movzx eax, byte [ebp+0x0C] ; node index
    push eax
    mov al, byte [ebp+0x08]    ; codec
    push eax
    call codec_query
    shr eax, 20
    and ax, 0x0f
    mov byte [edi+W_TYPE], al
    mov dword [esp+0x08], 0xF0000 | 0x0C
    call codec_query
    mov dword [edi+W_PINCAP], eax
    mov edx, 0x0D
    mov ecx, 0x12
    test eax, PINCAP_OUTPUT
    cmovz ecx, edx
    or ecx, 0xF0000
    mov dword [esp+0x08], ecx
    call codec_query
    mov byte [edi+W_OFFSET], al
    shr eax, 8
    mov byte [edi+W_NUMSTEPS], al
    shr eax, 8
    mov byte [edi+W_STEPSIZE], al
    shr ax, 15
    mov byte [edi+W_MUTABLE], al
    mov dword [esp+0x08], 0xF0000 | 0x0E
    call codec_query
    test al, 0x80
    setnz byte [edi+W_LONGFORM]
    and al, 0x7f
    mov byte [edi+W_CONLEN], al
    mov dword [esp+0x08], 0xF0000 | 0x13
    call codec_query
    test al, 0x80
    setnz byte [edi+W_DELTA]
    and al, 0x7f
    mov byte [edi+W_VOLSTEPS], al
    mov dword [esp+0x08], 0xF1C00 | 0
    call codec_query
    movzx edx, al
    and dl, 0b1111
    mov byte [edi+W_SEQUENCE], dl
    shr eax, 4
    mov dl, al
    and dl, 0b1111
    mov byte [edi+W_ASSOCIATION], dl
    shr eax, 4
    mov dl, al
    and dl, 0b1111
    mov byte [edi+W_MISC], dl
    shr eax, 4
    mov dl, al
    and dl, 0b1111
    mov byte [edi+W_COLOR], dl
    shr eax, 4
    mov dl, al
    and dl, 0b1111
    mov byte [edi+W_CONTYPE], dl
    shr ax, 4
    mov dl, al
    and dl, 0b1111
    mov byte [edi+W_DEVICEDEFAULT], dl
    shr ax, 4
    mov dl, al
    and dl, 0b111111
    mov byte [edi+W_LOCATION], dl
    shr al, 6
    mov byte [edi+W_PORTCON], al
    test byte [edi+W_LONGFORM], 1
    setnz cl
    setz bl
    inc bl
    shl bl, 1
    mov dword [edi+W_CONLIST], 0
    movzx eax, byte [edi+W_CONLEN]
    test eax, eax
    jz .skip_connection_list_entries
    xor cx, cx
    mov dx, 0b11
    and ax, dx
    cmovz dx, cx
    setnz cl
    or ax, dx
    add ax, cx     ; align eax to multiple of 4
    MALLOC esi, eax
    mov dword [edi+W_CONLIST], esi
    mov dword [esp+0x08], 0xF0200 | 0
.get_connection_list_entries:
    call codec_query
    mov dword [esi], eax
    add byte [esp+0x08], bl
    add esi, 4
    mov al, byte [esp+0x08]
    cmp al, byte [edi+W_CONLEN]
    jl .get_connection_list_entries

    mov dword [esp], edi
    call connection_list_info

.skip_connection_list_entries:
    mov dword [esp], edi
    call add_widget_entry

    movzx eax, byte [edi+W_CONTYPE]
    mov edx, dword [port_connection_types+eax*4]
    mov dword [esp+0x0C], edx
    mov al, byte [edi+W_SEQUENCE]
    mov dword [esp+0x08], eax
    mov al, byte [edi+W_ASSOCIATION]
    mov dword [esp+0x04], eax
    mov al, byte [edi+W_DEVICEDEFAULT]
    mov edx, dword [device_types+eax*4]
    mov dword [esp+0x00], edx
    mov al, byte [edi+W_TYPE]
    mov edx, dword [widget_types+eax*4]
    push edx
    mov al, byte [ebp+0x0C]
    push eax
    mov al, byte [ebp+0x08]
    push eax
    mov al, byte [edi+W_CONLEN]
    push eax
    push 8
    push _widget_info
    call printf

    add esp, 0x28
    pop ebx
    pop esi
    pop edi
    leave
    ret

AFG_enumerate:
    push esi
    push edi
    push ebx
    push 0xf0000 | 0x04
    movzx eax, byte [afg.nid]
    push eax
    movzx ebx, byte [afg.codec]
    push ebx
    call codec_query
    add esp, 0x04
    movzx esi, al     ; widget count
    shr eax, 0x10
    movzx edi, al     ; widget start node
    add esi, edi      ; ending widget
    mov dword [esp+0x00], ebx
    push esi
    push edi
    push 2
    push _AFG_node_info
    call printf
    add esp, 0x10
.loop:
    mov dword [esp+0x04], edi
    call widget_info
    inc edi
    cmp edi, esi
    jnz .loop
    add esp, 4
    pop ebx
    pop edi
    pop esi
    ret

;;; ebp+0x08 -> codec number
codec_enumerate:
    push ebp
    mov ebp, esp
    push esi
    push edi
    push ebx
    mov eax, dword [ebp+0x08]
    push 0xf0000 | 0x04
    push 0x00
    push eax
    call codec_query
    movzx esi, al      ; node count
    shr eax, 16
    movzx edi, al      ; starting node
    add esi, edi       ; ending node
    ;;; reuse existing stack space
    ;;; set command data
    mov dword [esp+0x08], 0xF0000 | 0x05
    push esi
    push edi
    mov eax, dword [ebp+0x08]
    push eax
    push 3
    push _codec_info
    call printf
    add esp, 0x14
.loop:
    ;;; command is unmodified and still on stack
    ;;; set node index
    mov dword [esp+0x04], edi
    ;;; codec number is unmodified and still on stack
    call codec_query
    cmp al, 1           ; type 0x01 is AFG
    jnz .next
    and ah, 1
    mov byte [afg.invalid_cap], ah
    mov al, byte [ebp+0x08]
    mov byte [afg.codec], al
    mov ax, di          ; cant access dil :(
    mov byte [afg.nid], al

    call AFG_enumerate
    jmp .end
.next:
    inc edi
    cmp edi, esi
    jnz .loop
    xor eax, eax
.end:
    add esp, 0x0C        ; function call stack space
    pop ebx
    pop edi
    pop esi
    leave
    ret

hda_AFG_init:
    push ebp
    mov ebp, esp
    push esi
    push edi
    xor edi, edi
    mov esi, dword [hda.mmio]
    mov si, word [esi+STATESTS]
    shr si, 1
.loop:
    jnc .next
    push edi
    call codec_enumerate
    add esp, 4
    test eax, eax
    jnz .end
.next:
    inc edi
    shr si, 1
    jnz .loop
    push _no_AFG
    call puts
    jmp hang
.end:
    pop edi
    pop esi
    leave
    ret
    ret

hda_init:
    push ebp
    mov ebp, esp
    mov eax, dword [hda.mmio]
;;; CORB off
    mov byte [eax+CORBCTL], 0
;;; RIRB off
    mov byte [eax+RIRBCTL], 0
.confirm_CR_reset:
    mov dl, byte [eax+CORBCTL]
    and dl, 0b10
    mov cl, byte [eax+RIRBCTL]
    and cl, 0b10
    or dl, cl
    jnz .confirm_CR_reset
;;; reset STATESTS register
    and word [eax+STATESTS], ~0x8000
;;; begin controller reset
    mov dl, byte [eax+GCTL]
    and dl, ~1
    mov byte [eax+GCTL], dl
.confirm_begin_reset:
    test byte [eax+GCTL], 1
    jnz .confirm_begin_reset
    mov dl, byte [eax+GCTL]
    or dl, 1
    mov byte [eax+GCTL], dl
.confirm_reset:
    test byte [eax+GCTL], 1
    jz .confirm_reset

    mov word [eax+WAKEEN], 0x7FFF
    mov dword [eax+INTCTL], 0x800000FF

    call CORB_init
    call RIRB_init

    mov ecx, 0xFFFFFF
    loop $

    call hda_AFG_init

    leave
    ret

find_hda:
    push ebp
    mov ebp, esp
    push esi
    push edi
    push ebx
    mov esi, 255
.bus:
    mov edi, 31
.device:
    mov ebx, 7
.function:
    push 0x08
    push ebx
    push edi
    push esi
    call pci_read
    add esp, 0x10
    shr eax, 0x10
    cmp ax, 0x0403
    jz .ok_hda
    dec ebx
    jns .function
    dec edi
    jns .device
    dec esi
    jns .bus
.no_hda:
    push _no_hda
    call puts
    jmp hang
.ok_hda:
    ;;; cant access sil or dil :(
    mov word [hda.bus], si
    mov word [hda.device], di
    mov word [hda.function], bx
    push eax
    shr ax, 8
    push eax
    push 2
    push _ok_hda.class
    call printf
    add esp, 0x10
    push 0x04
    push ebx
    push edi
    push esi
    call pci_read
    add esp, 0x10
    or eax, 0b110
    push eax
    push 0x04
    push ebx
    push edi
    push esi
    call pci_write
    add esp, 0x14
    push 0x10
    push ebx
    push edi
    push esi
    call pci_read
    add esp, 0x10
    and eax, ~0x0F
    mov dword [hda.mmio], eax
    push eax
    push 1
    push _ok_hda.bar0
    call printf
    add esp, 0x0C
.end:
    pop ebx
    pop edi
    pop esi
    leave
    ret

%macro __pci_config_addr 0
    mov ax, 0x8000
    mov al, byte [ebp+0x08]
    shl eax, 5
    or al, byte[ebp+0x0C]
    shl eax, 3
    or al, byte [ebp+0x10]
    shl eax, 8
    mov al, byte [ebp+0x14]
%endmacro

;;; ebp+0x14 -> register offset
;;; ebp+0x10 -> function
;;; ebp+0x0C -> device
;;; ebp+0x08 -> bus
pci_read:
    push ebp
    mov ebp, esp

    __pci_config_addr
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx

    leave
    ret

;;; ebp+0x18 -> output value
;;; ebp+0x14 -> register offset
;;; ebp+0x10 -> function
;;; ebp+0x0C -> device
;;; ebp+0x08 -> bus
pci_write:
    push ebp
    mov ebp, esp

    __pci_config_addr
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    mov eax, dword [ebp+0x18]
    out dx, eax

    leave
    ret

;;; strings/data
_no_hda: db `no hda device found.`, 0
_ok_hda:
.class:  db `class:%2x.subclass:%2x.\n`, 0
.bar0:   db `bar0:%x.\n`, 0
_hang:   db `hang.`, 0
_no_CORB_size: db `no CORB sizes found.`, 0
_no_RIRB_size: db `no RIRB sizes found.`, 0
_reset_CORB_rp_fail: db `failed to reset CORB read pointer.`, 0
_display_STATESTS: db `STATESTS:%4x.`, 0
_RIRBWP: db `RIRBWP:%4x.`, 0
_CORBWP: db `CORBWP:%4x.`, 0
_CORBRP: db `CORBRP:%4x.`, 0
_codec_info: db `codec %d. nodes:start:%d,end:%d.\n`, 0
_no_AFG: db `no audio function group found.`, 0
_audio_output: db `audio output`, 0
_audio_input: db `audio input`, 0
_audio_mixer: db `audio mixer`, 0
_audio_selector: db `audio selector`, 0
_pin_complex: db `pin complex`, 0
_power: db `power`, 0
_volume_knob: db `volume knob`, 0
_beep_generator: db `beep generator`, 0
_vendor_defined: db `vendor defined`, 0
_line_out: db `line out`, 0
_speaker: db `speaker`, 0
_HP_out: db `HP out`, 0
_CD: db `CD`, 0
_SPDIF_out: db `SPDIF out`, 0
_digital_other_out: db `digital other out`, 0
_modem_line_side: db `modem line side`, 0
_modem_handset_side: db `modem handset side`, 0
_line_in: db `line in`, 0
_AUX: db `AUX`, 0
_mic_in: db `mic in`, 0
_telephony: db `telephony`, 0
_SPDIF_in: db `SPDIF in`, 0
_digital_other_in: db `digital other in`, 0
_jack_connection: db `jack`, 0
_no_connection: db `none`, 0
_internal_connection: db `internal`, 0
_both_connections: db `both`, 0
_unknown: db `unknown`, 0
_widget_info: db `len:%d.codec:%2x,nid:%2x,%s,%s,order:%2x,%2x,con:%s.\n`, 0
_AFG_node_info: db `AFG widgets. nodes:start:%d,end:%d.\n`, 0
_connection_list_entry: db `entry:%4x.\n`, 0
_stream_io_info: db `output streams:%d,input streams:%d.\n`, 0
_set_converter_format_fail: db `failed to set converter format.\n`, 0
_enable_pin_complex_fail: db `failed to enable pin complex.\n`, 0
_debug_info: db `0:%x,1:%x,2:%x,3:%x,4:%x,5:%x,6:%x,7:%x.\n`, 0

widget_types:
dd _audio_output
dd _audio_input
dd _audio_mixer
dd _audio_selector
dd _pin_complex
dd _power
dd _volume_knob
dd _beep_generator
times 7 dd _unknown
dd _vendor_defined

device_types:
dd _line_out
dd _speaker
dd _HP_out
dd _CD
dd _SPDIF_out
dd _digital_other_out
dd _modem_line_side
dd _modem_handset_side
dd _line_in
dd _AUX
dd _mic_in
dd _telephony
dd _SPDIF_in
dd _digital_other_in
dd _unknown
dd _unknown

port_connection_types:
dd _jack_connection
dd _no_connection
dd _internal_connection
dd _both_connections

GCAP equ   0x00
VMIN equ   0x02
VMAJ equ   0x03
OUTPAY     equ 0x04
INPAY      equ 0x06
GCTL       equ 0x08
WAKEEN     equ 0x0C
STATESTS   equ 0x0E
GSTS       equ 0x10
OUTSTRMPAY equ 0x18
INSTRMPAY  equ 0x1A
INTCTL     equ 0x20
INTSTS     equ 0x24
COUNTER    equ 0x30
SSYNC      equ 0x38
CORBLBASE  equ 0x40
CORBUBASE  equ 0x44
CORBWP     equ 0x48
CORBRP     equ 0x4A
CORBCTL    equ 0x4C
CORBSTS    equ 0x4D
CORBSIZE   equ 0x4E
RIRBLBASE  equ 0x50
RIRBUBASE  equ 0x54
RIRBWP     equ 0x58
RINTCNT    equ 0x5A
RIRBCTL    equ 0x5C
RIRBSTS    equ 0x5D
RIRBSIZE   equ 0x5E
DPLBASE    equ 0x70
DPUBASE    equ 0x74

hda:
.mmio:        dd 0
.bus:         dw 0
.device:      dw 0
.function:    dw 0

corb:
.size:        dw 0
.size_mask:   dw 0

rirb:
.size:        dw 0
.size_mask:   dw 0
.rp:          dw 0

afg:
.codec:       db 0
.nid:         db 0
.node_start:  db 0
.node_count:  db 0
.invalid_cap: db 0

PINCAP_OUTPUT equ 1 << 4

W_NEXT        equ 0x00
W_TYPE        equ 0x04
W_PINCAP      equ 0x05
W_OFFSET      equ 0x09
W_NUMSTEPS    equ 0x0A
W_STEPSIZE    equ 0x0B
W_MUTABLE     equ 0x0C
W_LONGFORM    equ 0x0D
W_CONLEN      equ 0x0E
W_CONLIST     equ 0x0F
W_VOLSTEPS    equ 0x13
W_DELTA       equ 0x14
W_SEQUENCE    equ 0x15
W_ASSOCIATION equ 0x16
W_MISC        equ 0x17
W_COLOR       equ 0x18
W_CONTYPE     equ 0x19
W_DEVICEDEFAULT  equ 0x1A
W_LOCATION    equ 0x1B
W_PORTCON     equ 0x1C
W_SIZE        equ 0x20

;;; example entry in widget forward only linked list
;;; sizeof(widget) = 32 bytes
;;; widget:
;;; .next:      dd 0
;;; .type:      db 0
;;; .pin_capabilities dd 0
;;; .offset:    db 0
;;; .num_steps: db 0
;;; .step_size: db 0
;;; .mutable:   db 0
;;; ;;; see section 7.1.2
;;; .long_form: db 0
;;; .connection_list_len: db 0
;;; .connection_list: dd 0
;;; .volume_steps: db 0
;;; .delta:     db 0
;;; .sequence:  db 0
;;; .default_association: db 0
;;; .misc: db 0
;;; .color: db 0
;;; .connection_type: db 0
;;; .device_default: db 0
;;; .location: db 0
;;; .port_connectivity: db 0

widgets:
audio_output:   dd 0
audio_input:    dd 0
audio_mixer:    dd 0
audio_selector: dd 0
pin_complex:    dd 0
power:          dd 0
volume_knob:    dd 0
beep_generator: dd 0
;;; unknown widgets
times 7 dd 0
vendor_defined: dd 0

sizes:
dw 2      ; 0b00 (0) -> 2 entries
dw 16     ; 0b01 (1) -> 16 entries
dw 256    ; 0b10 (2) -> 256 entries

;;; set heap bottom to stack top
heap_addr: dd STACK_TOP

    align 256
_CORB_buffer: times 1024 db 0
_RIRB_buffer: times 2048 db 0
_debug_buffer: times 1024 db 0

;;; NOTE: address macro defined in interrupt.asm
%macro BDL_entry 3
dq address(%1), (%3 << 32) | %2
%endmacro

PCM equ 0
KHZ44.1 equ 1
KHZ48   equ 0
MULT    equ 0      ; 0 -> mult of 1, 1 -> mult of 2...
DIVISOR equ 1      ; 0 -> div  of 1, 1 -> div  of 2...
BPS     equ 0b100  ; 0b100 -> 32 bits per sample
CHAN    equ 0b0000 ; 0 -> 1 channel, 1 -> 2 channels...
STREAM_FORMAT equ (PCM << 15) | (KHZ44.1 << 14) | (MULT << 13) | (DIVISOR << 8) | (BPS << 4) | CHAN
BDL_LEN equ 0x2000

    align 256
_buffer_descriptor_list:
BDL_entry _buffer0, 0x1000, 0
BDL_entry _buffer1, 0x1000, 0
_buffer0: times 0x1000 db 0xff
_buffer1: times 0x1000 db 0xff