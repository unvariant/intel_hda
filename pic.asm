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
    ; OUTB PRIMARY_PIC_DATA, bl
    ; OUTB SECONDARY_PIC_DATA, bh

    OUTB PRIMARY_PIC_DATA, 0x01
    OUTB SECONDARY_PIC_DATA, 0x00
    ret

PIC_send_EOI:
    cmp al, 8
    jl .skip_secondary
    OUTB SECONDARY_PIC_CMD, PIC_EOI
.skip_secondary:
    OUTB PRIMARY_PIC_CMD, PIC_EOI
    ret