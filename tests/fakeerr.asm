;
; fakeerr - run a program once for each DOS error code, with every
; file open failing with that code
;
;   FAKEERR PROGRAM [ARGUMENTS]
;
; PROGRAM is a file name with its extension.  It is run 256 times with
; ARGUMENTS as its command tail; on run N, every open (INT 21h, 3Dh)
; fails with error N.  For each run FAKEERR prints "N: STATUS" on
; standard output; PROGRAM's own output goes where FAKEERR's does.
;
; A test tool for tests/compare.sh, to compare how two builds report
; every DOS error.
;
; Build: nasm -f bin -o fakeerr.com tests/fakeerr.asm
;
; SPDX-License-Identifier: MIT
;

cpu 8086
bits 16
org 0x100

TAIL        equ 0x81

start:
        cld
        mov     sp, stack_top
        mov     bx, (stack_top - start + 0x100 + 15) / 16
        mov     ah, 0x4a                ; leave the rest for PROGRAM
        int     0x21

        mov     si, TAIL                ; PROGRAM, then its tail
.skip:
        lodsb
        cmp     al, ' '
        je      .skip
        mov     di, progname
.name:
        cmp     al, 13
        je      .named
        cmp     al, ' '
        je      .named
        stosb
        lodsb
        jmp     .name
.named:
        mov     byte [di], 0
        dec     si
        mov     di, tail + 1
.copy:
        lodsb
        cmp     al, 13
        je      .tailend
        stosb
        jmp     .copy
.tailend:
        mov     [di], al
        mov     ax, di
        sub     ax, tail + 1
        mov     [tail], al
        mov     word [pb_tail + 2], cs
        mov     word [pb_fcb1 + 2], cs
        mov     word [pb_fcb2 + 2], cs

        mov     ax, 0x3521
        int     0x21
        mov     [old21], bx
        mov     [old21 + 2], es
        mov     dx, hook
        mov     ax, 0x2521
        int     0x21

.run:
        push    cs
        pop     es
        mov     [save_sp], sp
        mov     [save_ss], ss
        mov     dx, progname
        mov     bx, params
        mov     ax, 0x4b00
        int     0x21
        cli                             ; DOS 2 keeps no registers
        mov     ss, [cs:save_ss]
        mov     sp, [cs:save_sp]
        sti
        push    cs
        pop     ds
        push    cs
        pop     es
        cld
        mov     al, 255
        jc      .report
        mov     ah, 0x4d
        int     0x21
.report:
        push    ax
        mov     ax, [code]
        call    print_num
        mov     dx, colon
        mov     cx, 2
        call    write
        pop     ax
        mov     ah, 0
        call    print_num
        mov     dx, crlf
        mov     cx, 2
        call    write
        inc     word [code]
        cmp     word [code], 256
        jb      .run

        push    ds
        lds     dx, [old21]
        mov     ax, 0x2521
        int     0x21
        pop     ds
        mov     ax, 0x4c00
        int     0x21

; Print AX in decimal on standard output.
print_num:
        mov     di, numend
        mov     bx, 10
.digit:
        xor     dx, dx
        div     bx
        dec     di
        add     dl, '0'
        mov     [di], dl
        test    ax, ax
        jnz     .digit
        mov     dx, di
        mov     cx, numend
        sub     cx, di

; Write CX bytes at DX on standard output.
write:
        mov     bx, 1
        mov     ah, 0x40
        int     0x21
        ret

; INT 21h: fail every open with error [code].
hook:
        cmp     ah, 0x3d
        jne     .chain
        mov     ax, [cs:code]
        push    bp
        mov     bp, sp
        or      byte [bp + 6], 1        ; CF in the caller's flags
        pop     bp
        iret
.chain:
        jmp     far [cs:old21]

old21       dd  0
save_sp     dw  0
save_ss     dw  0
code        dw  0
colon       db  ": "
crlf        db  13, 10
num         times 6 db 0
numend:
progname    times 64 db 0
params      dw  0                       ; the environment: FAKEERR's
pb_tail     dw  tail, 0
pb_fcb1     dw  0x5c, 0
pb_fcb2     dw  0x6c, 0
tail        times 130 db 0
            times 256 db 0
stack_top:
