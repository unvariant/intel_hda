    [BITS 32]

IDT_INT32  equ 0x0E
IDT_TRAP32 equ 0x0F

%define IDT_ENTRY(handler, type) ((ADDRESS(handler) >> 16 << 48) | (1 << 47) | (type << 40) | (CODE_DESC << 16) | (ADDRESS(handler) & 0xFFFF))

%define IDT_INT32(x) IDT_ENTRY(x, IDT_INT32)
%define IDT_TRAP32(x) IDT_ENTRY(x, IDT_TRAP32)

IDT_init_interrupts:
    lidt [IDT.desc]
    ret

int32_handler:
    iret

trap32_handler:
    iret

trap32_error_handler:
    add esp, 0x04
    iret

_keystroke: db `key: %x\n`, 0
handle_keyboard:
    pusha

    xor     eax,    eax
    in      al,     0x60

    cmp     al,     0x25
    jz      .scroll_up

    cmp     al,     0x24
    jz      .scroll_down

.done:
    call    flush
    PIC_SEND_EOI 1

    popa
    iret

.scroll_up:
    mov     eax,    dword [screen_offset]
    mov     ecx,    eax
    sub     ecx,    80
    cmovge  eax,    ecx
    mov     dword [screen_offset], eax
    jmp     .done
.scroll_down:
    add     dword [screen_offset], 80
    jmp     .done


%macro STUB_IRQ 1
stub_irq %+ %1:
    PIC_SEND_EOI %1
    iret
%endmacro

%assign i 0
%rep    16
STUB_IRQ i
%assign i i+1
%endrep

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
triple_fault:                   dq 0
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
dq IDT_INT32(stub_irq0)
dq IDT_INT32(handle_keyboard)
dq IDT_INT32(stub_irq2)
dq IDT_INT32(stub_irq3)
dq IDT_INT32(stub_irq4)
dq IDT_INT32(stub_irq5)
dq IDT_INT32(stub_irq6)
dq IDT_INT32(stub_irq7)
;;; next 8 are IRG 8..15
dq IDT_INT32(stub_irq8)
dq IDT_INT32(stub_irq9)
dq IDT_INT32(stub_irq10)
dq IDT_INT32(stub_irq11)
dq IDT_INT32(stub_irq12)
dq IDT_INT32(stub_irq13)
dq 0 ;;; IDT_INT32(stub_irq14)
dq IDT_INT32(stub_irq15)
times (256-32-16) dq 0
IDT.desc:
dw 256*8-1
dd IDT