    [BITS 32]

;;; programmable interrupt controller (PIC) is different from
;;; the peripheral component interconnect (PCI)
;;; PCI is for communicating with a locating peripheral devices
;;; hard drives, speakers, keyboard, etc.
;;; PIC is for managing how hardware interrupts map to system interrupts

PRIMARY_PIC        equ 0x20
SECONDARY_PIC      equ 0xA0
PRIMARY_PIC_CMD    equ PRIMARY_PIC
PRIMARY_PIC_DATA   equ PRIMARY_PIC+1
SECONDARY_PIC_CMD  equ SECONDARY_PIC
SECONDARY_PIC_DATA equ SECONDARY_PIC+1

PIC_EOI      equ 0x20 ;;; PIC end of interrupt
PIC_READ_IRR equ 0x0A
PIC_READ_ISR equ 0x0B

ICW1_ICW4     equ 0x01
ICW1_SINGLE   equ 0x02
ICW_INTERVAL4 equ 0x04
ICW1_LEVEL    equ 0x08
ICW1_INIT     equ 0x10

ICW4_8086          equ 0x01
ICW4_AUTO          equ 0x02
ICW4_BUF_SECONDARY equ 0x08
ICW4_BUF_PRIMARY   equ 0x0C
ICW4_SFNM          equ 0x10

PRIMARY_PIC_VECTOR   equ 0x20
SECONDARY_PIC_VECTOR equ 0x28

;;; outputs byte from al to port
%macro OUTB 2
    mov dx, %1
    mov al, %2
    out dx, al
%endmacro

;;; returns byte in al from port
%macro INB 1
    mov dx, %1
    in al, dx
%endmacro

%macro IO_WAIT 0
    out 0x80, al
%endmacro

;;; returns secondary irq reg in ah
;;; returns primary irq reg in al
%macro PIC_GET_IRQ_REG 1
    OUTB PRIMARY_PIC_CMD, %1
    OUTB SECONDARY_PIC_CMD, %1
    INB SECONDARY_PIC_CMD
    mov ah, al
    INB PRIMARY_PIC_CMD
%endmacro

%macro PIC_GET_IRR 0
    PIC_GET_IRQ_REG PIC_READ_IRR
%endmacro

%macro PIC_GET_ISR 0
    PIC_GET_IRQ_REG PIC_READ_ISR
%endmacro

;;; initializes primary and secondary PIC
;;; remaps primary interrupt vector to int 0x20..0x28
;;; remaps secondary interrupt vector to int 0x28..0x30
PIC_init:
    ; save masks
    INB PRIMARY_PIC_DATA
    mov bl, al
    INB SECONDARY_PIC_DATA
    mov bh, al

    OUTB PRIMARY_PIC_CMD, ICW1_INIT | ICW1_ICW4
    IO_WAIT
    OUTB SECONDARY_PIC_CMD, ICW1_INIT | ICW1_ICW4
    IO_WAIT
    OUTB PRIMARY_PIC_DATA, PRIMARY_PIC_VECTOR
    IO_WAIT
    OUTB SECONDARY_PIC_DATA, SECONDARY_PIC_VECTOR
    IO_WAIT
    OUTB PRIMARY_PIC_DATA, 0b100
    IO_WAIT
    OUTB SECONDARY_PIC_DATA, 0b10
    IO_WAIT
    OUTB PRIMARY_PIC_DATA, ICW4_8086
    IO_WAIT
    OUTB SECONDARY_PIC_DATA, ICW4_8086
    IO_WAIT

    ; restore masks
    OUTB PRIMARY_PIC_DATA, bl
    OUTB SECONDARY_PIC_DATA, bh

    OUTB PRIMARY_PIC_DATA, 0x00
    OUTB SECONDARY_PIC_DATA, 0x00
    ret

PIC_send_EOI:
    cmp al, 8
    jl .skip_secondary
    OUTB SECONDARY_PIC_CMD, PIC_EOI
.skip_secondary:
    OUTB PRIMARY_PIC_CMD, PIC_EOI
    ret

%macro PIC_SEND_EOI 1
    push eax
    push edx
%if %1 > 7
    OUTB SECONDARY_PIC_CMD, PIC_EOI
%endif
OUTB PRIMARY_PIC_CMD, PIC_EOI
    pop edx
    pop eax
%endmacro

IDT_init_interrupts:
    lidt [IDT.desc]
    ret

%define IDT_ENTRY(handler, type) ((ADDRESS(handler) >> 16 << 48) | (1 << 47) | (type << 40) | (CODE_DESC << 16) | (ADDRESS(handler) & 0xFFFF))

IDT_INT32  equ 0x0E
IDT_TRAP32 equ 0x0F

%define IDT_INT32(x) IDT_ENTRY(x, IDT_INT32)
%define IDT_TRAP32(x) IDT_ENTRY(x, IDT_TRAP32)

int32_handler:
    iret

trap32_handler:
    iret

trap32_error_handler:
    pop eax
    iret

tick:
    PIC_SEND_EOI 0
    iret

test:
    push eax
    mov eax, dword [cursor_offset]
    mov dword [0xB8000 + eax], 0x0F410F5A
    add eax, 4
    mov dword [cursor_offset], eax
    pop eax
    PIC_SEND_EOI 1
    iret

%assign INT32_ENTRY         IDT_INT32(int32_handler)
%assign TRAP32_ENTRY        IDT_TRAP32(trap32_handler)
%assign TRAP32_ERROR_ENTRY  IDT_TRAP32(trap32_error_handler)

;;; https://wiki.osdev.org/Exceptions
IDT:
;;; first 32 entries are common exceptions
;;; that occur in protected mode
div_by_zero:                    dq TRAP32_ENTRY
debug:                          dq TRAP32_ENTRY
non_masked_interrupt:           dq INT32_ENTRY
breakpoint:                     dq TRAP32_ENTRY
overflow:                       dq TRAP32_ENTRY
bound_range_exceeded:           dq TRAP32_ENTRY
illegal_opcode:                 dq TRAP32_ENTRY
device_not_available:           dq TRAP32_ENTRY
double_fault:                   dq TRAP32_ERROR_ENTRY
coprocessor_segment_overrun:    dq TRAP32_ENTRY
invalid_tss:                    dq TRAP32_ERROR_ENTRY
segment_not_present:            dq TRAP32_ERROR_ENTRY
stack_segment_fault:            dq TRAP32_ERROR_ENTRY
general_protection_fault:       dq TRAP32_ERROR_ENTRY
page_fault:                     dq TRAP32_ERROR_ENTRY
dq 0
x87_fpu_exception:              dq TRAP32_ENTRY
alignment_check:                dq TRAP32_ERROR_ENTRY
machine_check:                  dq TRAP32_ENTRY
simd_fpu_exception:             dq TRAP32_ENTRY
virtualization_exception:       dq TRAP32_ENTRY
control_protection_exception:   dq TRAP32_ERROR_ENTRY
times 6 dq 0
hypervisor_injection_exception: dq TRAP32_ENTRY
vmm_communication_exception:    dq TRAP32_ERROR_ENTRY
security_exception:             dq TRAP32_ERROR_ENTRY
dq 0
;;; next 8 are IRQ 0..7
;dq tick
;dq test
times 8 dq 0
;;; next 8 are IRG 8..15
times 8 dq 0
times (256-32-16) dq 0
IDT.desc:
dw 256*8-1
dd IDT