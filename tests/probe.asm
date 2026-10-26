;
; probe - run a program with its standard error in a file, and record
; how much memory it had when it exited
;
;   PROBE ERRFILE MEMFILE PROGRAM [ARGUMENTS]
;
; PROGRAM is a file name with its extension.  It gets ARGUMENTS as its
; command tail exactly, and its standard output is PROBE's.  ERRFILE
; gets its standard error, and MEMFILE the size in bytes of its memory
; block (the one holding its PSP) when it called DOS to exit.  PROBE
; exits with PROGRAM's exit code, or 255 if it could not run it.
;
; A test tool for tests/compare.sh, which DOS cannot do by itself:
; COMMAND.COM cannot redirect standard error.
;
; Build: nasm -f bin -o probe.com tests/probe.asm
;
; SPDX-License-Identifier: MIT
;

cpu 8086
bits 16
org 0x100

TAILLEN     equ 0x80
TAIL        equ 0x81

start:
        cld
        mov     sp, stack_top
        mov     bx, (stack_top - start + 0x100 + 15) / 16
        mov     ah, 0x4a                ; leave the rest for PROGRAM
        int     0x21

        mov     si, TAIL
        mov     di, errname
        call    next_word
        mov     di, memname
        call    next_word
        mov     di, progname
        call    next_word
        mov     di, tail + 1            ; the rest, from the separator
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

        mov     dx, errname
        xor     cx, cx
        mov     ah, 0x3c
        int     0x21
        jc      fail
        mov     bx, ax
        mov     cx, 2
        mov     ah, 0x46
        int     0x21
        jc      fail
        mov     ah, 0x3e
        int     0x21

        mov     ax, 0x3521
        int     0x21
        mov     [old21], bx
        mov     [old21 + 2], es
        mov     dx, hook
        mov     ax, 0x2521
        int     0x21

        push    cs
        pop     es
        mov     word [pb_tail + 2], cs
        mov     word [pb_fcb1 + 2], cs
        mov     word [pb_fcb2 + 2], cs
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
        mov     byte [status], 255
        jc      .unhook
        mov     ah, 0x4d
        int     0x21
        mov     [status], al
.unhook:
        push    ds
        lds     dx, [old21]
        mov     ax, 0x2521
        int     0x21
        pop     ds

        mov     dx, memname
        xor     cx, cx
        mov     ah, 0x3c
        int     0x21
        jc      fail
        mov     bx, ax
        mov     ax, [mem]               ; paragraphs to bytes, in decimal
        mov     dx, ax
        mov     cl, 4
        shl     ax, cl
        mov     cl, 12
        shr     dx, cl
        mov     di, numend
        mov     si, 10
.digit:
        mov     cx, ax
        mov     ax, dx
        xor     dx, dx
        div     si
        xchg    ax, cx
        div     si
        dec     di
        add     dl, '0'
        mov     [di], dl
        mov     dx, cx
        mov     cx, ax
        or      cx, dx
        jnz     .digit
        mov     dx, di
        mov     cx, numend + 2
        sub     cx, di
        mov     ah, 0x40
        int     0x21
        mov     ah, 0x3e
        int     0x21

        mov     al, [status]
        mov     ah, 0x4c
        int     0x21

fail:
        mov     ax, 0x4cff
        int     0x21

; Copy the next word of the command tail at SI to DI, with a NUL.
; SI is left on the space or CR that ended it.
next_word:
        lodsb
        cmp     al, ' '
        je      next_word
.c:
        cmp     al, 13
        je      .end
        cmp     al, ' '
        je      .end
        stosb
        lodsb
        jmp     .c
.end:
        dec     si
        mov     byte [di], 0
        ret

; INT 21h: on exit (4Ch), record the size of the caller's memory block.
hook:
        cmp     ah, 0x4c
        jne     .chain
        push    ax
        push    bx
        push    es
        mov     ah, 0x51                ; current PSP, DOS 2 and later
        pushf
        call    far [cs:old21]
        dec     bx
        mov     es, bx
        mov     ax, [es:3]
        mov     [cs:mem], ax
        pop     es
        pop     bx
        pop     ax
.chain:
        jmp     far [cs:old21]

old21       dd  0
mem         dw  0
save_sp     dw  0
save_ss     dw  0
status      db  0
errname     times 64 db 0
memname     times 64 db 0
progname    times 64 db 0
params      dw  0                       ; the environment: PROBE's
pb_tail     dw  tail, 0
pb_fcb1     dw  0x5c, 0
pb_fcb2     dw  0x6c, 0
num         times 10 db 0
numend      db  13, 10
tail        times 130 db 0
            times 256 db 0
stack_top:
