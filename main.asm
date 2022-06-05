stage_2:
    call PIC_init
    call PIC_init_interrupts

detect_hda:
    mov di, 255
.bus:
    mov si, 31
.device:
    mov dx, 7
.function:
    mov cx, 0x08
.register:
    call pci_read
    shr eax, 16
    cmp ax, 0x0403  ; class 0x04, subclass 0x03
    jz .hda_found
.next:
    sub dx, 1
    jns .function
    sub si, 1
    jns .device
    sub di, 1
    jns .bus

    mov si, _no_hda_found
    call print_string
    jmp hang16

.hda_found:
    mov cx, 0x10
    call pci_read
    call print_hex32
    mov eax, 0xFEBF0000
    and eax, 0xFFFFFFF0
    mov edx, eax

.check64:
    mov bl, byte [edx]
    test bl, 1
    mov byte [CORB_config.ok64], bl
    jnz .ok64
    mov si, _no64
    call print_string
    jmp .check64done
.ok64:
    mov si, _ok64
    call print_string
.check64done:

.check_CORB_off:
    mov bl, byte [edx+0x4C]    ; CORB control
    test bl, 0b10
    jz .CORB_off
    ;;; if CORB is not off turn it off
    ;;; by writing a zero bit to (bit 1)
    and bl, 0b11111101
    mov byte [edx+0x4C], bl
    mov si, _turning_CORB_off
    call print_string
.CORB_off:
    mov si, _CORB_off
    call print_string

.check_RIRB_off:
    mov al, byte [edx+0x5C]
    test al, 0b00000010
    jz .RIRB_off
    mov si, _turning_RIRB_off
    call print_string
    and al, 0b11111101
    mov byte [edx+0x5C], al
.RIRB_off:
    mov si, _RIRB_off
    call print_string

.reset_STATESTS:
    mov bx, 0x7FFF
    mov word [edx+0x0E], bx

.controller_reset:
    mov si, _begin_ctl_reset
    call print_string
    mov ebx, dword [edx+8]
    and ebx, ~1
    mov dword [edx+8], ebx
    io_wait
.confirm_ctl_reset_entry:
    test byte [edx+8], 1
    jnz .confirm_ctl_reset_entry

    io_wait
    mov ebx, dword [edx+8]
    or ebx, 1
    mov dword [edx+8], ebx
.confirm_ctl_reset_leave:
    test byte [edx+8], 1
    jz .confirm_ctl_reset_leave
    mov si, _ctl_reset
    call print_string

.enable_WAKEEN_interrupts:
    mov bx, 0x7FFF
    mov word [edx+0x0C], bx

.setup_CORB:
    mov bl, byte [edx+0x4E]
    and bl, 0b01110000
    shr bl, 4
    mov bh, bl
    xor cl, cl
.popcnt:
    xor ch, ch
    test bh, 1
    setnz ch
    shr bh, 1
    add cl, ch
    test bh, bh
    jnz .popcnt
    test cl, cl
    jz .CORB_size_zero
    cmp cl, 1
    jnz .choose_CORB_size
    mov si, _CORB_size_one
    call print_string
    shl bx, 1
    mov bx, word [CORB_entries+bx]
    mov word [CORB_config.entries], bx
    jmp .set_CORB_buffer
.choose_CORB_size:
    mov si, _choose_CORB_size
    call print_string
    ;;; select a CORB size
    jmp hang16
.set_CORB_buffer:
    mov eax, CORB_buffer
    mov dword [edx+0x40], eax   ; CORB base address (lower bits)
    test byte [CORB_config.ok64], 1
    jz .reset_CORB_rp
    xor eax, eax
    mov dword [edx+0x44], eax   ; zero base address upper bits
.reset_CORB_rp:
    mov si, _begin_CORB_rp_reset
    call print_string
    mov ax, word [edx+0x4A]
    or ax, 0x8000
    mov word [edx+0x4A], ax
    io_wait
.confirm_CORB_rp_reset:
    test word [edx+0x4A], 0x8000
    jz .confirm_CORB_rp_reset
    mov ax, word [edx+0x4A]
    and ax, 0x7FFF
    mov word [edx+0x4A], ax
    io_wait
    test word [edx+0x4A], 0x8000
    jnz .fail
    mov si, _CORB_rp_reset
    call print_string
.CORB_wp_reset:
    xor eax, eax
    mov dword [edx+0x48], eax
    mov si, _CORB_wp_reset
    call print_string
.set_CORB_run:
    mov al, byte [edx+0x4C]
    or al, 0b10
    mov byte [edx+0x4C], al

.setup_RIRB:
;;; TODO: deal with RIRB size
;;; in QEMU there is only one RIRB size
.set_RIRB_buffer:
    mov eax, RIRB_buffer
    mov dword [edx+0x50], eax
    test byte [CORB_config.ok64] ,1
    jz .reset_RIRB_wp
    xor eax, eax
    mov dword [edx+0x54], eax
.reset_RIRB_wp:
    mov si, _begin_RIRB_wp_reset
    call print_string
    mov ax, word [edx+0x58]
    or ax, 0x8000
    mov word [edx+0x58], ax
    io_wait
    test word [edx+0x58], 0x8000
    jnz .fail
    mov si, _RIRB_wp_reset
    call print_string
.diable_RIRB_interrupt:
    mov al, byte [edx+0x5C]
    and al, 0b11111110
    mov byte [edx+0x5C], al
.set_RIRB_run:
    mov al, byte [edx+0x5C]
    or al, 0b10
    mov byte [edx+0x5C], al

.test_CORB:
    xor ebx, ebx
    mov eax, CORB_buffer
    mov dword [eax], ebx
    mov ax, word [edx+0x48]
    inc ax
    mov word [edx+0x48], ax
.loop:
    mov ax, word [edx+0x4a]
    cmp ax, word [edx+0x48]
    jnz .loop
    int 0x20
    jmp hang16

.CORB_size_zero:
    mov si, _CORB_size_zero
    call print_string
    jmp hang16

.fail:
    mov si, _fail
    call print_string
    jmp hang16

CORB_config:
.entries: dw 0
.ok64: db 0

CORB_entries:
dw 0
dw 2
dw 16
dw 0
dw 256

_begin_ctl_reset: db "beginning controller reset.", 0
_ctl_reset: db "controller reset.", 0
_ok64: db "64 bit addressing detected.", 0
_no64: db "64 bit addressing not detected", 0
_turning_CORB_off: db "turning CORB off.", 0
_CORB_off: db "CORB is off.", 0
_CORB_size_zero: db "no CORB size options found.", 0
_CORB_size_one: db "one CORB size option found.", 0
_choose_CORB_size: db "more than one CORB size option found. Choosing a size.", 0
_begin_CORB_rp_reset: db "resetting CORB read pointer.", 0
_CORB_rp_reset: db "CORB read pointer reset.", 0
_CORB_wp_reset: db "CORB write pointer reset.", 0
_turning_RIRB_off: db "turning RIRB off.", 0
_RIRB_off: db "RIRB is off.", 0
_begin_RIRB_wp_reset: db "resetting RIRB write pointer.", 0
_RIRB_wp_reset: db "RIRB write pointer reset.", 0
_RIRB_rp_reset: db "RIRB read pointer reset.", 0

_fail: db "something went wrong.", 0

    align 128
CORB_buffer: times 1024 db 0

    align 128
RIRB_buffer: times 2048 db 0

;;; buffer is ds:si
;;; converts number from buffer into unsigned number in eax
;;; returns zero if no valid number is found
atoi:
    push ebx
    xor eax, eax
    xor ebx, ebx
.loop:
    cmp byte [ds:si], 0x30
    jb .end
    cmp byte [ds:si], 0x39
    ja .end
    lodsb
    imul ebx, 10
    lea ebx, [ebx+eax-0x30]
    jmp .loop
.end:
    mov eax, ebx
    pop ebx
    ret

;;; bus number in di
;;; device number in si
;;; function number in dx
;;; register offset in cx
;;; result in eax
pci_config_addr:
    mov ax, 0x8000
    or ax, di
    shl eax, 5
    or ax, si
    shl eax, 3
    or ax, dx
    shl eax, 8
    or ax, cx
    ret

pci_read:
    push dx
    call pci_config_addr
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    pop dx
    ret

pci_write:
    push dx
    push eax
    call pci_config_addr
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    pop eax
    out dx, eax
    pop dx
    ret

_print_buffer times 64 db 0
_no_hda_found db `intel hda peripheral could not be found\n`, 0
