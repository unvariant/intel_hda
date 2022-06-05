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
%macro outb 2
    mov dx, %1
    mov al, %2
    out dx, al
%endmacro

;;; returns byte in al from port
%macro inb 1
    mov dx, %1
    in al, dx
%endmacro

%macro io_wait 0
    out 0x80, al
%endmacro

;;; returns secondary irq reg in ah
;;; returns primary irq reg in al
%macro PIC_get_irq_reg 1
    outb PRIMARY_PIC_CMD, %1
    outb SECONDARY_PIC_CMD, %1
    inb SECONDARY_PIC_CMD
    mov ah, al
    inb PRIMARY_PIC_CMD
%endmacro

%macro PIC_get_irr 0
    PIC_get_irq_reg PIC_READ_IRR
%endmacro

%macro PIC_get_isr 0
    PIC_get_irq_reg PIC_READ_ISR
%endmacro

;;; initializes primary and secondary PIC
;;; remaps primary interrupt vector to int 0x20..0x28
;;; remaps secondary interrupt vector to int 0x28..0x30
PIC_init:
    inb PRIMARY_PIC_DATA
    mov bl, al
    inb SECONDARY_PIC_DATA
    mov bh, al

    outb PRIMARY_PIC_CMD, ICW1_INIT | ICW1_ICW4
    io_wait
    outb SECONDARY_PIC_CMD, ICW1_INIT | ICW1_ICW4
    io_wait
    outb PRIMARY_PIC_DATA, PRIMARY_PIC_VECTOR
    io_wait
    outb SECONDARY_PIC_DATA, SECONDARY_PIC_VECTOR
    io_wait
    outb PRIMARY_PIC_DATA, 0b100
    io_wait
    outb SECONDARY_PIC_DATA, 0b10
    io_wait
    outb PRIMARY_PIC_DATA, ICW4_8086
    io_wait
    outb SECONDARY_PIC_DATA, ICW4_8086
    io_wait

    outb PRIMARY_PIC_DATA, bl
    outb SECONDARY_PIC_DATA, bh
    ret

PIC_send_EOI:
    cmp al, 8
    jl .skip_secondary
    outb SECONDARY_PIC_CMD, PIC_EOI
.skip_secondary:
    outb PRIMARY_PIC_CMD, PIC_EOI
    ret

IDT_init_interrupts:
    lidt [IDT.desc]
    ret

%define address(x) (BASE_ADDR + x - $$)

%macro __IDT_entry 2
    dq (address(%1) >> 16 << 48) | (1 << 47) | (%2 << 40) | (CODE_DESC << 16) | (address(%1) & 0xFFFF)
%endmacro

IDT_INT32  equ 0x0E
IDT_TRAP32 equ 0x0F

%define IDT_int32(x) __IDT_entry x, IDT_INT32
%define IDT_trap32(x) __IDT_entry x, IDT_TRAP32

%define IDT_name(x) IDT_interrupt %+ x

%macro stub_IDT_entry 1
IDT_name(%1):
    mov word [0xB8000], 0x0F41
    iret
%endmacro

%assign i 0
%rep    256
stub_IDT_entry i
%assign i i+1
%endrep

IDT:
%assign i 0
%rep    256
IDT_int32(IDT_name(i))
%assign i i+1
%endrep
.desc:
dw 256*8-1
dd IDT