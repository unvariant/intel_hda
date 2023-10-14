    [BITS 32]
STACK_TOP         equ 0x200000   ; 2 MB
AUDIO_FILE_BUFFER equ 0x400000   ; 4 MB

    _find_hda: db `FIND HDA\n`, 0
    _hda_init: db `HDA INIT\n`, 0
    _find_outputs: db `FIND OUTPUTS\n`, 0
    _audio_file_info: db `AUDIO FILE INFO\n`, 0
    _log_volume_knob: db `VOLUME KNOB: %x\n`, 0

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

    call help_banner

    push _ihda
    call puts
    pop eax

    ;push (AUDIO_FILE_END - AUDIO_FILE_START) >> 9
    ;push (ADDRESS(AUDIO_FILE_START - BOOT_START) >> 9) & 0xFFFFFFFF
    ;push (ADDRESS(AUDIO_FILE_START - BOOT_START) >> 9) >> 32
    ;push AUDIO_FILE_BUFFER
    ;call disk_read

    ;;; determines hda bus, device, and function numbers
    call find_hda

    push _hda_init
    call puts
    pop eax

    ;;; attempts to find an audio function group (AFG)
    ;;; then enumerates through all the codecs present in the audio function group
    ;;; in each codec sorts the widgets it finds
    call hda_init

    push _find_outputs
    call puts
    pop eax

    ;;; finds an output pin complex widget that is connected to an audio output widget
    call find_outputs

    push _audio_file_info
    call puts
    pop eax

    ;;; extract information from the audio file, expects wav format
    call audio_file_info

    mov eax, dword [widgets.volume_knob]
    push eax
    push 1
    push _log_volume_knob
    call printf

    push _playing_audio
    call puts
    pop eax

    ;;; plays test audio
    call test_audio

    ;;; fills initial buffer
    call audio_file_init
    ;;; fills audio buffer as it plays
    call fill_audio_buffer
hang:
    push _hang
    call puts
    jmp $

_playing_audio: db `BEGINNING AUDIO PLAYBACK\n`, 0

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

;;; ebp+0x14 -> sector count (32 bit number)
;;; ebp+0x10 -> absolute disk block low (lower 32 bits)
;;; ebp+0x0C -> absolute disk block high (upper 16 bits)
;;; ebp+0x08 -> destination buffer
;;; ZF clear on error
disk_read:
    push ebp
    mov ebp, esp

    push edi
    push esi
    push ebx

    push _disk_read
    call puts
    pop eax

    mov edi, 0xFFFF
    mov ebx, dword [ebp+0x14]

    push ebx
    call progress_bar_init
    pop eax

    mov edx, dword [ebp+0x10]
    mov ecx, dword [ebp+0x0C]
    mov eax, dword [ebp+0x08]
    mov esi, ebx
    cmp ebx, edi
    cmovg esi, edi

    push esi
    push edx
    push ecx
    push eax
.read:
    call ata_pio_read
    jz .disk_read_ok

    push _ata_read_error
    call puts
    
    jmp hang

.disk_read_ok:
    mov eax, dword [esp+0x0C]
    add dword [esp+0x08], eax
    adc dword [esp+0x04], 0
    sub ebx, eax
    shl eax, 9
    add dword [esp+0x00], eax

    mov esi, ebx
    cmp ebx, edi
    cmovg esi, edi
    mov dword [esp+0x0C], esi

    cmp ebx, 0
    jg .read
    
    add esp, 0x10

    pop ebx
    pop esi
    pop edi

    leave
    ret


IO_BASE          equ 0x1F0
DATA_REG         equ 0x1F0
SECTOR_COUNT_REG equ 0x1F2
LBA_LOW          equ 0x1F3
LBA_MID          equ 0x1F4
LBA_HIGH         equ 0x1F5
DRIVE_REG        equ 0x1F6
CMD_REG          equ 0x1F7     ; writing to   0x1F7 writes to CMD_REG
STS_REG          equ 0x1F7     ; reading from 0x1F7 returns   STS_REG
READ_SECTORS_EXT equ 0x24

STATUS_ERR       equ 1 << 0
STATUS_IDX       equ 1 << 1
STATUS_CDATA     equ 1 << 2
STATUS_DRQ       equ 1 << 3    ; data is ready to r/w
STATUS_SRV       equ 1 << 4
STATUS_DF        equ 1 << 5    ; drive fault, does not set STATUS_ERR
STATUS_RDY       equ 1 << 6
STATUS_BSY       equ 1 << 7

CONTROL_BASE     equ 0x3F6
DEV_CNTL_REG     equ 0x3F6

NO_INT           equ 1 << 1

turn_off_disk_irqs:
    mov dx, DEV_CNTL_REG
    mov al, NO_INT
    out dx, al
    ret

;;; can transfer max of 32 MB
;;; ebp+0x14 -> sector count (16 bit number)
;;; ebp+0x10 -> absolute disk block low (lower 32 bits)
;;; ebp+0x0C -> absolute disk block high (upper 16 bits)
;;; ebp+0x08 -> destination buffer
;;; ZF clear on error
ata_pio_read:
    push ebp
    mov ebp, esp

    push edi
    push ebx

    mov edi, dword [ebp+0x08]
    movzx ebx, word [ebp+0x14]
    mov ecx, dword [ebp+0x10]
    push ecx
    shr ecx, 16
    mov ah, cl

    mov dx, DRIVE_REG
    mov al, 1 << 6                ; set LBA bit
    out dx, al

    mov dx, SECTOR_COUNT_REG
    mov al, bh
    out dx, al                   ; send upper 8 bits of sector count
    mov dx, LBA_LOW
    mov al, ch
    out dx, al                   ; LBA 3
    mov dx, LBA_MID
    mov cx, word [ebp+0x0C]
    mov al, cl
    out dx, al                   ; LBA 4
    mov dx, LBA_HIGH
    mov al, ch
    out dx, al                   ; LBA 5

    mov dx, SECTOR_COUNT_REG
    mov al, bl
    out dx, al                   ; send lower 8 bits of sector count
    mov dx, LBA_LOW
    pop ecx
    mov al, cl
    out dx, al                   ; LBA 0
    mov dx, LBA_MID
    mov al, ch
    out dx, al                   ; LBA 1
    mov dx, LBA_HIGH
    mov al, ah
    out dx, al                   ; LBA 2

    mov dx, CMD_REG
    mov al, READ_SECTORS_EXT
    out dx, al

    mov cl, 4
.ignore_err:
    in al, dx
    test al, STATUS_BSY      ; if al & STATUS_BSY == 1 { 0 } else { 1 };
    setz ch
    test al, STATUS_DRQ      ; if al & STATUS_DRQ == 1 { 1 } else { 0 };
    setnz ah
    test ah, ch              ; ZF only clear when STATUS_BSY == 0 and STATUS_DRQ == 1
    jnz .ready
    dec cl
    jnz .ignore_err

.test_err:
    in al, dx
    test al, STATUS_BSY
    jnz .test_err
    test al, STATUS_ERR | STATUS_DF
    jnz .end                 ; ZF clear when jmping to .end

.ready:
    mov dx, DATA_REG
    mov cx, 256
    rep insw

    push 1
    call progress_bar_step
    pop eax

    mov dx, STS_REG
    in al, dx                ; delay 400ns to allow drive to set new values of BSY and DRQ
    in al, dx
    in al, dx
    in al, dx

    dec ebx
    jnz .test_err
    
    in al, dx                ; if error detected ZF clear, otherwise ZF set
    test al, STATUS_ERR | STATUS_DF

.end:
    pop ebx
    pop edi
    leave
    ret

RIFF_ID   equ 0x00
FILE_SIZE equ 0x04
WAVE_ID   equ 0x08
FMT_ID    equ 0x0C
FMT_LEN   equ 0x10
FMT_TYPE  equ 0x14
NUM_CHAN  equ 0x16
SAMPLE_RATE equ 0x18
BYTES_PER_SAMPLE equ 0x1C
BYTES_PER_CHAN   equ 0x20
BITS_PER_SAMPLE  equ 0x22
DATA_ID   equ 0x24
DATA_SIZE equ 0x28
HEADER_SIZE equ 0x2C

audio_file_info:
    push esi

    mov esi, AUDIO_FILE_BUFFER
    mov eax, dword [esi+RIFF_ID]
    mov edx, "RIFF"
    cmp eax, edx
    jnz .error

    mov eax, dword [esi+WAVE_ID]
    mov edx, "WAVE"
    cmp eax, edx
    jnz .error

    mov eax, dword [esi+FMT_ID]
    ;;; from what I have seen, software that generates wav files
    ;;; can not seem to agree on what the last character is supposed to be
    ;;; some use underscore, space, or null byte. Instead of trying to catch
    ;;; all the cases only check the first three bytes and ignore the last byte
    mov edx, "fmt"
    and eax, 0xFFFFFF
    cmp eax, edx
    jnz .error

    mov eax, dword [esi+FMT_LEN]
    mov edx, 16
    cmp eax, edx
    jnz .error

    mov eax, dword [esi+DATA_ID]
    mov edx, "data"
    cmp eax, edx
    jnz .error

    mov eax, dword [esi+FILE_SIZE]
    mov edx, dword [esi+DATA_SIZE]
    mov dword [audio_file.file_size], eax
    mov dword [audio_file.data_size], edx
    mov edi, audio_file.fmt_type
    add esi, FMT_TYPE
    mov ecx, 0x10
    rep movsb
.end:
    pop esi
    ret

.error:
    push eax
    push edx
    push 2
    push _audio_file_expected
    call printf
    jmp hang

;;; TODO: error if format is non-pcm?
;;; returns audio file format in ax
;;; derives format from audio_file struct
audio_file_format:
    ;;; zero edx or div will result in floating point exception
    xor edx, edx
    ;;; test for 44.1 khz base rate
    mov ecx, 44100
    mov eax, dword [audio_file.sample_rate]
    cmp eax, ecx
    jg .L0
    ;;; if the sample rate is less than the base rate divide base rate by sample rate instead
    ;;; do this by swapping the dividend and divisor
    xchg eax, ecx
.L0:
    div ecx
    ;;; if the remainder is zero this is the properly base rate
    test edx, edx
    jz .base_rate
    ;;; otherwise test for 48 khz base rate
    xor edx, edx
    mov ecx, 48000
    mov eax, dword [audio_file.sample_rate]
    cmp eax, ecx
    jg .L1
    ;;; if the sample rate is less than the base rate divide base rate by sample rate instead
    ;;; do this by swapping the dividend and divisor
    xchg eax, ecx
.L1:
    div ecx
    test edx, edx
    ;;; if the remainder is still non-zero generate error
    jnz .invalid_sample_rate
.base_rate:
    ;;; decrement dl because in the format
    ;;; 0 -> 1
    ;;; 1 -> 2
    ;;; 2 -> 3
    ;;; ...
    ;;; to transform dl to a format number subtract one
    ;;; eax holds the result of the division
    lea edx, [eax - 1]
    ;;; dl holds multiplier
    ;;; dh holds divisor (defaults to zero)
    cmp ecx, dword [audio_file.sample_rate]
    jl .L2
    ;;; if the base rate is greater than the sample rate
    ;;; swap dl and dh to swap multiplier and divisor
    xchg dl, dh
.L2:
    ;;; bit 14 = if base_rate == 44.1 khz { 1 } else { 0 }
    cmp ecx, 44100
    setz al
    xor ah, ah
    ;;; make space for multiplier
    shl al, 3
    ;;; set multiplier
    or al, dl
    ;;; make space for divisor
    shl al, 3
    ;;; set divisor
    or al, dh
    movzx edx, word [audio_file.bits_per_sample]
    mov cx, word [audio_file.channels]
    shl ax, 4
    shr dx, 2
    dec cx
    ;;; set bits per sample (bps)
    or al, byte [.bits_per_sample + edx]
    shl ax, 4
    ;;; set number of channels
    or al, cl

    ret

.invalid_sample_rate:
    push _invalid_sample_rate
    call puts
    jmp hang

.bits_per_sample:
db 0, 0
db 0
db 0
db 1
db 2
db 3
db 0
db 4

audio_file_init:
    mov esi, AUDIO_FILE_BUFFER + HEADER_SIZE
    mov edi, _buffer0
    mov ecx, BDL_LEN
    rep movsb
    mov dword [audio_file.offset], BDL_LEN
    mov dword [audio_file.state], BDL_LEN
    ret

FILL_RATE equ 4

fill_audio_buffer:
    mov eax, dword [hda.mmio]
    mov edx, dword [eax+INTSTS]
    test edx, 1 << 4
    jz fill_audio_buffer
    and edx, ~(1 << 4)
    mov dword [eax+INTSTS], edx
    xor eax, eax
    mov edx, dword [audio_file.state]
    add edx, BDL_LEN / FILL_RATE
    cmp edx, BDL_LEN-1
    cmovg edx, eax
    mov dword [audio_file.state], edx
    mov eax, dword [audio_file.offset]
    lea edi, dword [_buffer0 + edx]
    lea esi, dword [AUDIO_FILE_BUFFER + HEADER_SIZE + eax]
    mov ecx, BDL_LEN / FILL_RATE
    rep movsb
    sub esi, AUDIO_FILE_BUFFER + HEADER_SIZE
    mov dword [audio_file.offset], esi
    mov eax, dword [audio_file.data_size]
    cmp esi, eax
    jl fill_audio_buffer
    ret

test_audio:
    push ebp
    mov ebp, esp
    push edi
    push esi
    push ebx

    mov edi, dword [output.audio_output]
    mov esi, dword [output.pin_complex]
    movzx edi, byte [edi+W_NID]                 ; edi contains audio output node index
    movzx esi, byte [esi+W_NID]                 ; esi contains pin complex  node index

    mov eax, dword [hda.mmio]
    movzx ecx, word [eax+0x00]
    shr cx, 8
    movzx edx, cl
    and dl, 0x0f
    push edx
    mov ebx, edx
    shl ebx, 5

;;; ebx contains offset to first output stream descriptor
    add ebx, 0x80
    mov eax, dword [hda.mmio]
    add ebx, eax
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
;;; set stream number & allow interrupt on buffer completion
    or dword [ebx], (1 << 20) | (1 << 2)
;;; set cyclic buffer length
    mov dword [ebx+0x08], BDL_LEN
;;; set last valid index, once index is reached controller will restart at index 0
    mov byte [ebx+0x0C], BDL_ENTRIES - 1
;;; set stream format
    call audio_file_format
    mov word [ebx+0x12], ax
;;; set BLD lower address
    mov dword [ebx+0x18], _buffer_descriptor_list
    mov dword [ebx+0x1C], 0
;;; set audio convert format
    mov edx, dword [output.audio_output]
    movzx edx, byte [edx+W_CODEC]
    movzx eax, ax
    or eax, 0x020000
    push eax                          ; set format verb
    push edi                          ; audio output node index
    push edx                          ; codec address
    call codec_query
    test eax, edx
    jz .next0
    push _set_converter_format_fail
    call puts
    jmp hang
.next0:
    mov dword [esp+0x08], 0x70700 | 0b1000000     ; set pin widget control verb, bit 6 set to enable pin complex
    mov dword [esp+0x04], esi                     ; pin complex node index
    ;;; codec address already on stack
    call codec_query
    test eax, edx
    jz .next1
    push _enable_pin_complex_fail
    call puts
    jmp hang
.next1:
    mov dword [esp+0x08], 0x70600 | (1 << 4) | 1        ; set converter stream and channel, stream 1, channel 1
    mov dword [esp+0x04], edi                           ; audio output node index
    ;;; codec address already on stack
    call codec_query
    mov dword [esp+0x08], 0x70500 | 0                   ; set D0 (fully powered) state
    ;;; node index already on stack
    ;;; codec address already on stack
    call codec_query
    mov eax, dword [output.audio_output]
    movzx edx, byte [eax+W_OFFSET]
    or edx, 0x30000 | (0 << 7)
    mov dword [esp+0x08], edx                           ; unmute audio output
    ;;; node index already on stack
    ;;; codec address already on stack
    call codec_query
    mov eax, dword [hda.mmio]
    mov dword [eax+SSYNC], 0         ; enable stream 1 in ssync
    or dword [ebx], 1 << 1           ; set stream run bit

    add esp, 0x0C
    pop ebx
    pop esi
    pop edi
    leave
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
    test dx, 0x8000                 ;;; then checking the bit to make sure it is clear
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
;;; but QEMU interprets it as zero, so instead set it as 255
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
;;; bit 35 is set to 1 to indicate valid GET response
;;; however response is all zeros for SET responses
    bt edx, 3
    jc .valid
    push eax
    push edx
    push 2
    push _warn_invalid_response
    call printf
    add esp, 8
    pop edx
    pop eax
.valid:
    leave
    ret

_warn_invalid_response: db `WARN: INVALID RIRB RESPONSE: [hi:lo] %x:%x\n`, 0

;;; ebp+0x08 -> pointer to widget struct
connection_list_info:
    push ebp
    mov ebp, esp
    push esi
    push ebx
    mov eax, dword [ebp+0x08]
    movzx ebx, byte [eax+W_LONGFORM]
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
    push 0xF0000 | 0x09        ; get paramter
    movzx eax, byte [ebp+0x0C] ; node index
    mov byte [edi+W_NID], al
    push eax
    mov al, byte [ebp+0x08]    ; codec
    mov byte [edi+W_CODEC], al
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

.skip_connection_list_entries:
    mov dword [esp], edi
    call add_widget_entry

    add esp, 0x0C
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
    movzx esi, al     ; widget count
    shr eax, 0x10
    movzx edi, al     ; widget start node
    add esi, edi      ; ending widget
.loop:
    mov dword [esp+0x04], edi
    call widget_info
    inc edi
    cmp edi, esi
    jnz .loop

    add esp, 0x0C
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
    add esp, 0x0C
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
    mov dword [eax+INTCTL], 0 ; 0xC00000FF

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
.end:
    pop ebx
    pop edi
    pop esi
    leave
    ret

;;; struct connection list {
;;;     list: dd 0,
;;;     long_form: db 0,
;;; }
;;; ebp+0x0C -> index
;;; ebp+0x08 -> connection list struct
connection_list_next:
    push ebp
    mov  ebp, esp
    mov  eax, dword [ebp+0x08]
    mov  edx, dword [ebp+0x0C]
    mov  cl,  byte  [eax+0x04]
    mov  eax, dword [eax]
    shl  edx, cl
    movzx eax, word [eax + edx]
    shl  cl,  3
    mov  dx,  0xFF
    shl  dx,  cl
    mov  dl,  0xFF
    and  ax,  dx
    leave
    ret

;;; ebp+0x10 -> node index
;;; ebp+0x0C -> codec address
;;; ebp+0x08 -> pointer to widget list
widget_list_search:
    push ebp
    mov ebp, esp
    mov eax, dword [ebp+0x08]
    test eax, eax
    jz .end
    mov dh, byte [ebp+0x10]         ; dh contains node index
    mov dl, byte [ebp+0x0C]         ; dl contains codec address
.loop:
    cmp dl, byte [eax+W_CODEC]
    jnz .loopend
    cmp dh, byte [eax+W_NID]
    jz .end
.loopend:
    mov eax, dword [eax+W_NEXT]
    test eax, eax
    jnz .loop
.end:
    leave
    ret

find_outputs:
    push ebp
    mov ebp, esp
    push edi
    push esi
    push ebx
    sub esp, 0x08
    mov ebx, dword [widgets.pin_complex]
    test ebx, ebx
    jz find_outputs_fail

.loop_audio_outputs:
    movzx eax, byte [ebx+W_CONLEN]
    movzx edi, byte [ebx+W_CODEC]
    lea esi, dword [ebx+W_CONLIST]
    dec eax
    js .continue
    mov dword [esp+0x04], eax
    mov dword [esp+0x00], esi

.loop_connection_list:
    call connection_list_next
    push eax
    push edi
    push widgets.audio_output
    call widget_list_search
    add esp, 0x0C

    mov dword [output.audio_output], eax
    mov dword [output.pin_complex], ebx
    test eax, eax
    jnz .end

    dec dword [esp+0x04]
    jns .loop_connection_list

.continue:
    mov ebx, dword [ebx+W_NEXT]
    test ebx, ebx
    jnz .loop_audio_outputs
    jmp find_outputs_fail

.end:
    add esp, 0x08
    pop ebx
    pop esi
    pop edi
    leave
    ret

find_outputs_fail:
    push _find_outputs_fail
    call puts
    jmp hang

%macro PCI_CONFIG_ADDR 0
    mov ax, 0x8000
    mov al, byte [ebp+0x08]
    shl eax, 5
    or al, byte  [ebp+0x0C]
    shl eax, 3
    or al, byte  [ebp+0x10]
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

    PCI_CONFIG_ADDR
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

    PCI_CONFIG_ADDR
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    mov eax, dword [ebp+0x18]
    out dx, eax

    leave
    ret

;;; ebp+0x08 -> max
progress_bar_init:
    push ebp
    mov ebp, esp
    push ebx

    mov ecx, 160
    mov eax, dword [write_offset]
    add eax, ecx
    mov ebx, eax
    xor edx, edx
    div ecx
    sub ebx, edx
    mov dword [write_offset], ebx
    sub ebx, ecx
    mov word [0xB8000+ebx], 0x0F5B
    mov word [0xB8000+ebx+158], 0x0F5D
    add ebx, 2
    mov eax, dword [ebp+0x08]
    mov dword [progress_bar_cursor_offset], ebx
    mov dword [progress_bar_offset], 0
    mov dword [progress_bar_max], eax
    mov dword [progress_bar_cur], 0

    pop ebx
    leave
    ret

;;; ebp + 0x08 -> amount to step by
progress_bar_step:
    push ebp
    mov ebp, esp
    push edi

    mov eax, dword [ebp+0x08]
    mov edi, dword [progress_bar_offset]
    add eax, dword [progress_bar_cur]
    mov ecx, dword [progress_bar_max]
    mov dword [progress_bar_cur], eax

    cmp eax, ecx
    ja .end

    imul eax, 78
    xor edx, edx
    div ecx
    shl eax, 1

    mov ecx, eax
    sub ecx, edi
    lea eax, [edi + ecx]
    mov dword [progress_bar_offset], eax
    shr cl, 1

    add edi, 0xB8000
    add edi, dword [progress_bar_cursor_offset]
    mov ax, 0x0F3D
    rep stosw

.end:
    pop edi
    leave
    ret

;;; strings/data
_no_hda: db `no hda device found.`, 0
_hang:   db `hang.`, 0
_no_CORB_size: db `no CORB sizes found.`, 0
_no_RIRB_size: db `no RIRB sizes found.`, 0
_reset_CORB_rp_fail: db `failed to reset CORB read pointer.`, 0
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
_connection_list_entry: db `entry:%4x.\n`, 0
_set_converter_format_fail: db `failed to set converter format.\n`, 0
_enable_pin_complex_fail: db `failed to enable pin complex.\n`, 0
_find_outputs_fail: db `failed to find output widgets\n`, 0
_ihda: db `IHDA START\n`, 0
_audio_file_expected: db `expected %8x, found %8x\n`, 0
_invalid_sample_rate: db `invalid sample rate. must be a multiple or divisor of 44.1 khz or 48 khz\n`, 0
_disk_read: db `reading file from disk\n`, 0
_AFG_enumerate: db `AFG enumerate\n`, 0
_codec_enumerate: db `codec enumerate\n`, 0
_widget_info: db `widget info\n`, 0
_ata_read_error: db `disk read error`, 0

progress_bar_cursor_offset: dd 0
progress_bar_offset: dd 0
progress_bar_max: dd 0
progress_bar_cur: dd 0

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
SSYNC      equ 0x34   ; according to the specification SSYNC is at offset 0x38, osdev wiki uses offset 0x34 and qemu also uses offset 0x34 (qemu-7.0.0/hw/audio/intel-hda-defs.h)
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

W_NEXT           equ 0x00
W_TYPE           equ 0x04
W_PINCAP         equ 0x05
W_OFFSET         equ 0x09
W_NUMSTEPS       equ 0x0A
W_STEPSIZE       equ 0x0B
W_MUTABLE        equ 0x0C
W_CONLEN         equ 0x0D
W_CONLIST        equ 0x0E
W_LONGFORM       equ 0x12
W_VOLSTEPS       equ 0x13
W_DELTA          equ 0x14
W_SEQUENCE       equ 0x15
W_ASSOCIATION    equ 0x16
W_MISC           equ 0x17
W_COLOR          equ 0x18
W_CONTYPE        equ 0x19
W_DEVICEDEFAULT  equ 0x1A
W_LOCATION       equ 0x1B
W_PORTCON        equ 0x1C
W_CODEC          equ 0x1D
W_NID            equ 0x1E

W_SIZE           equ 0x20

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
;;; ;;; see section 7.1.2 of intel hda docs
;;; .connection_list_len: db 0
;;; .connection_list: dd 0
;;; .long_form: db 0
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
;;; .codec_address: db 0
;;; .node_index: db 0

widgets:
.audio_output:   dd 0
.audio_input:    dd 0
.audio_mixer:    dd 0
.audio_selector: dd 0
.pin_complex:    dd 0
.power:          dd 0
.volume_knob:    dd 0
.beep_generator: dd 0
;;; unknown widgets
times 7 dd 0
.vendor_defined: dd 0

output:
.audio_output: dd 0
.pin_complex: dd 0

sizes:
dw 2      ; 0b00 (0) -> 2 entries
dw 16     ; 0b01 (1) -> 16 entries
dw 256    ; 0b10 (2) -> 256 entries

;;; https://web.archive.org/web/20120113025807/http://technology.niagarac.on.ca:80/courses/ctec1631/WavFileFormat.html
audio_file:
.file_size:         dd 0
.data_size:         dd 0
.fmt_type:          dw 0
.channels:          dw 0
.sample_rate:       dd 0
.bytes_per_second:  dd 0
.bytes_per_sample:  dw 0
.bits_per_sample:   dw 0
.offset:            dd 0
.state:             dd 0

;;; set heap bottom to stack top
heap_addr: dd STACK_TOP

    align 256
_CORB_buffer: times 1024 db 0
_RIRB_buffer: times 2048 db 0

PCM equ 0
KHZ44.1 equ 1
KHZ48   equ 0
MULT    equ 0b111   ; 0 -> mult of 1, 1 -> mult of 2...
DIVISOR equ 0b000   ; 0 -> div  of 1, 1 -> div  of 2...
BPS     equ 0b011   ; 0b100 -> 32 bits per sample
CHAN    equ 0b0000  ; 0 -> channel 1, 1 -> channel 2...
STREAM_FORMAT equ (PCM << 15) | (KHZ44.1 << 14) | (MULT << 11) | (DIVISOR << 8) | (BPS << 4) | CHAN

;;; annoyingly nasm decided to handle `align 4096` by padding the beginning of the file
;;; which of course messes up the bootloader code
%define __ALIGN_UP__(x, alignment) ((x + alignment - 1) & ~(alignment - 1))
%define __ALIGN__(alignment) times (__ALIGN_UP__(ADDRESS($), alignment) - ADDRESS($)) db 0

%define BUFFER_NAME(x) _buffer %+ x

;;; NOTE: address macro defined in interrupt.asm
%macro BDL_ENTRY 3
dq ADDRESS(%1), (%3 << 32) | %2
%endmacro

BDL_ENTRIES equ 32
BDL_LEN equ BDL_ENTRIES * 0x1000

    align 256
_buffer_descriptor_list:
%assign i 0
%rep BDL_ENTRIES
BDL_ENTRY BUFFER_NAME(i), 0x1000, ((i + 1) % (BDL_ENTRIES / FILL_RATE) == 0)
%assign i i+1
%endrep

    __ALIGN__(4096)
%assign i 0
%rep BDL_ENTRIES
BUFFER_NAME(i):
times 0x200 dq 0
%assign i i+1
%endrep