    [BITS 32]

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

%define ADDRESS(x) (BASE_ADDR + x - $$)