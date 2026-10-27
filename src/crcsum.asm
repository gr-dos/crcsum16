;
; crcsum - compute and check CRC-32 checksums
;
; An 8086 assembly version of crcsum, as a .COM program using only DOS
; 2.0 calls.  The C version (main.c and its modules, built with libc16)
; is the specification: options, output, messages and ERRORLEVELs are
; the same, and so are the parts of libc16 they depend on, which are
; reimplemented here from libc16's specs: argument splitting, errno and
; strerror, and stdio buffering.  See docs/ASM.md.
;
; Build: nasm -f bin -DVERSION='"0.01"' -o crcsum.com src/crcsum.asm
;
; SPDX-License-Identifier: MIT
;

cpu 8086
bits 16
org 0x100

%ifndef VERSION
%define VERSION "unknown"
%endif

BUFSIZE     equ 16384       ; file read size, as in main.c
LINESIZE    equ 256         ; manifest line buffer, as in main.c
PATHSIZE    equ 144         ; wildcard match path, as in dosglob.c
STACK       equ 1024

RC_OK       equ 0
RC_FAIL     equ 1           ; missing, unreadable or mismatched file
RC_FATAL    equ 2           ; usage error, bad manifest, write error

; manifest line results, as in manifest.h
M_EOF       equ -1
M_LONG      equ -2
M_IOERR     equ -3

; PSP
MEMTOP      equ 0x02
TAILLEN     equ 0x80
TAIL        equ 0x81

; DTA, from find first
DTA_ATTR    equ 0x15
DTA_NAME    equ 0x1e

FINDATTR    equ 0x27        ; normal, read-only, hidden, system, archive
SKIPATTR    equ 0x18        ; directory, volume label

; An output stream, written out at the end of each message.
S_HANDLE    equ 0
S_BUF       equ 2
S_SIZE      equ 4
S_CNT       equ 6
S_ERR       equ 8           ; a write failed, as ferror()
S_ERRNO     equ 9           ; errno from the first failed write

; Messages for strerror, numbered as errlist below.
E_NOERR     equ 0
E_2BIG      equ 1
E_ACCES     equ 2
E_BADF      equ 3
E_EXIST     equ 4
E_INVAL     equ 5
E_MFILE     equ 6
E_NOENT     equ 7
E_NOEXEC    equ 8
E_NOMEM     equ 9
E_NOSPC     equ 10
E_XDEV      equ 11

start:
        cld
        mov     ax, cs                  ; check that the buffers and
        add     ax, MEM_PARAS           ; stack fit, then keep only
        cmp     ax, [MEMTOP]            ; that much memory
        ja      nomem
        mov     sp, mem_end
        mov     bx, MEM_PARAS
        mov     ah, 0x4a                ; ES is the PSP
        int     0x21
        jc      nomem

        mov     dx, dta
        mov     ah, 0x1a
        int     0x21

        call    parse_tail

; Options.  Each option is replaced by 0 in argv.
        mov     bx, argv
.opt:
        cmp     bx, [argv_end]
        jae     .optdone
        mov     si, [bx]
        cmp     byte [endopts], 0
        jne     .file
        cmp     byte [si], '-'
        jne     .file
        mov     al, [si + 1]
        test    al, al
        jz      .stdin
        cmp     al, '-'
        jne     .short
        cmp     byte [si + 2], 0
        jne     .long
        mov     byte [endopts], 1
        jmp     .used
.long:
        mov     di, s_check
        call    stricmp
        je      .check
        mov     di, s_help
        call    stricmp
        je      help
        mov     di, s_version
        call    stricmp
        je      version
        mov     [s1], si
        mov     si, m_unrec
        jmp     usage_err
.stdin:
        mov     si, m_stdin
        jmp     usage_err
.short:
        inc     si
.letter:
        lodsb
        test    al, al
        jz      .used
        cmp     al, '?'
        je      help
        mov     ah, al
        or      ah, 0x20
        cmp     ah, 'h'
        je      help
        cmp     ah, 'c'
        jne     .invalid
        mov     byte [check], 1
        jmp     .letter
.invalid:
        mov     ah, 0
        mov     [chbuf], ax
        mov     word [s1], chbuf
        mov     si, m_invalid
        jmp     usage_err
.check:
        mov     byte [check], 1
.used:
        mov     word [bx], 0
        jmp     .next
.file:
        mov     byte [anyfile], 1
.next:
        inc     bx
        inc     bx
        jmp     .opt
.optdone:
        cmp     byte [anyfile], 0
        jne     .run
        mov     word [s1], s_file
        cmp     byte [check], 0
        je      .missing
        mov     word [s1], s_manifest
.missing:
        mov     si, m_missing
        jmp     usage_err

; Sum or check each argument.
.run:
        call    crc_init
        mov     word [argi], argv
.each:
        mov     bx, [argi]
        cmp     bx, [argv_end]
        jae     .done
        mov     si, [bx]
        test    si, si
        jz      .skip
        cmp     byte [check], 0
        je      .sum
        call    check_list
        jmp     .worst
.sum:
        call    sum_arg
.worst:
        cmp     al, [rc]
        jbe     .skip
        mov     [rc], al
.skip:
        add     word [argi], 2
        jmp     .each
.done:
        mov     bx, out_s
        call    flush
        cmp     byte [out_s + S_ERR], 0
        je      .exit
        mov     al, [out_s + S_ERRNO]   ; as main.c's write_errno
        mov     [errno], al
        mov     si, m_write
        call    fmt_err
        mov     byte [rc], RC_FATAL
.exit:
        mov     al, [rc]

; Exit with status AL.  Standard output is flushed first, but a write
; error is not reported, as when main returns early.
exit:
        mov     bx, out_s
        call    flush
        mov     ah, 0x4c
        int     0x21

help:
        mov     si, m_usage
        jmp     print_exit0
version:
        mov     si, m_version
print_exit0:
        call    fmt_out
        mov     al, RC_OK
        jmp     exit

; Print the message at SI and the "Try" line on stderr, and exit 2.
usage_err:
        call    fmt_err
        mov     si, m_try
        call    fmt_err
        mov     al, RC_FATAL
        jmp     exit

nomem:
        mov     dx, m_nomem
        mov     cx, m_nomem_len
        mov     bx, 2
        mov     ah, 0x40
        int     0x21
        mov     ax, 0x4c01
        int     0x21

;
; Split the command tail into argv as libc16 does, which is Microsoft
; C's rule: blanks (space, tab) separate arguments; '"' turns quoting
; on and off and is removed; a run of 2n backslashes before '"' gives n
; backslashes and a toggle, and 2n + 1 give n backslashes and a literal
; '"'; any other backslash is literal.  The arguments are copied in
; place, since one is never longer than its text, and each is ended by
; a NUL.  DL is 1 inside quotes; AH counts a run of backslashes.
;
parse_tail:
        mov     si, TAIL
        mov     bl, [si - 1]            ; at most 126 bytes
        cmp     bl, 126
        jbe     .len
        mov     bl, 126
.len:
        mov     bh, 0
        mov     [bx + si], bh           ; so the tail ends at a NUL
        mov     di, si
        mov     bx, argv
.blank:
        lodsb
        cmp     al, ' '
        je      .blank
        cmp     al, 9
        je      .blank
        test    al, al
        jz      .end
        dec     si
        mov     [bx], di                ; an argument starts
        inc     bx
        inc     bx
        xor     dl, dl
.next:
        lodsb
        test    al, al
        jz      .last
        cmp     al, '\'
        je      .run
        cmp     al, '"'
        je      .quote
        test    dl, dl
        jnz     .copy
        cmp     al, ' '
        je      .argend
        cmp     al, 9
        je      .argend
.copy:
        stosb
        jmp     .next
.quote:
        xor     dl, 1
        jmp     .next
.run:
        mov     ah, 0
.count:
        inc     ah
        lodsb
        cmp     al, '\'
        je      .count
        dec     si                      ; the byte after the run is next
        cmp     al, '"'
        mov     al, '\'
        jne     .lits
        shr     ah, 1                   ; n
        sbb     dh, dh                  ; DH = -1 for 2n + 1
.half:
        test    ah, ah
        jz      .dquote
        stosb
        dec     ah
        jmp     .half
.dquote:
        test    dh, dh
        jz      .next                   ; 2n: the '"' toggles when read
        movsb                           ; 2n + 1: a literal '"'
        jmp     .next
.lits:
        stosb                           ; no '"' follows: all literal
        dec     ah
        jnz     .lits
        jmp     .next
.argend:
        mov     byte [di], 0
        inc     di
        jmp     .blank
.last:
        mov     byte [di], 0
.end:
        mov     [argv_end], bx
        ret

; Compare SI with the lower case string at DI, ignoring the case of
; ASCII letters.  ZF set if equal.  Keeps SI.
stricmp:
        push    si
.c:
        lodsb
        cmp     al, 'A'
        jb      .cmp
        cmp     al, 'Z'
        ja      .cmp
        add     al, 'a' - 'A'
.cmp:
        cmp     al, [di]
        jne     .ret
        inc     di
        test    al, al
        jnz     .c
.ret:
        pop     si
        ret

;
; Sum the file named at SI, or each file it matches if it has
; wildcards, as sum_arg and dosglob.  Returns the status in AL.
;
; dosglob's "path too long" cannot happen here: the directory part
; comes from a command tail of at most 126 characters, so it and any
; 8.3 name always fit in PATHSIZE.
;
sum_arg:
        mov     [pattern], si
        mov     di, si                  ; end of the directory part
.scan:
        lodsb
        test    al, al
        jz      .plain
        cmp     al, '*'
        je      .wild
        cmp     al, '?'
        je      .wild
        jmp     .scan
.plain:
        mov     si, [pattern]
        jmp     sum_one
.wild:
        mov     si, [pattern]
.dir:
        lodsb
        test    al, al
        jz      .find
        cmp     al, '\'
        je      .sep
        cmp     al, '/'
        je      .sep
        cmp     al, ':'
        jne     .dir
.sep:
        mov     di, si
        jmp     .dir
.find:
        mov     [dirend], di
        mov     byte [matched], 0
        mov     byte [grc], RC_OK
        mov     dx, [pattern]
        mov     cx, FINDATTR
        mov     ah, 0x4e
        call    dos
        jc      .nomatch
.found:
        test    byte [dta + DTA_ATTR], SKIPATTR
        jnz     .findnext
        mov     si, [pattern]
        mov     di, path
        mov     cx, [dirend]
        sub     cx, si
        rep     movsb
        mov     si, dta + DTA_NAME
.copy:
        lodsb
        stosb
        test    al, al
        jnz     .copy
        mov     byte [matched], 1
        mov     si, path
        call    sum_one
        cmp     al, [grc]
        jbe     .findnext
        mov     [grc], al
.findnext:
        mov     ah, 0x4f
        call    dos
        jnc     .found
        cmp     byte [matched], 0
        je      .nomatch
        mov     al, [grc]
        ret
.nomatch:
        mov     ax, [pattern]
        mov     [s1], ax
        mov     si, m_nomatch
        call    fmt_err
        mov     al, RC_FAIL
        ret

; Print the CRC of the file named at SI.  Returns the status in AL.
sum_one:
        mov     [s1], si
        call    crc_file
        jc      .err
        mov     [num], ax
        mov     [num + 2], dx
        mov     si, m_sum
        call    fmt_out
        mov     al, RC_OK
        ret
.err:
        mov     si, m_nameerr
        call    fmt_err
        mov     al, RC_FAIL
        ret

;
; Check the manifest named at SI, as check_list.  Returns the status
; in AL.
;
check_list:
        mov     [listname], si
        call    open_ro
        jnc     .opened
        mov     si, m_nameerr
        jmp     .fatal_list
.opened:
        mov     [mhandle], ax
        mov     word [msize], 128       ; libc16's fopen buffer size
        mov     word [mcnt], 0
        mov     byte [merr], 0
        mov     byte [lrc], RC_OK
        mov     di, counts
        mov     cx, 10
        xor     ax, ax
        rep     stosw

.line:
        call    getline
        cmp     ax, M_EOF
        je      .close
        mov     di, lineno
        call    inc32
        cmp     ax, M_IOERR
        je      .ioerr
        cmp     ax, M_LONG
        je      .long
        call    parse
        cmp     al, 0
        jg      .line                   ; blank or comment
        jl      .bad

        mov     [s1], si
        call    crc_file
        jc      .unread
        cmp     ax, [want]
        jne     .mismatch
        cmp     dx, [want + 2]
        jne     .mismatch
        mov     di, n_ok
        call    inc32
        mov     si, m_ok
        jmp     .result
.mismatch:
        mov     di, n_sum
        call    inc32
        mov     si, m_failed
        jmp     .result
.unread:
        mov     di, n_read
        call    inc32
        mov     si, m_nameerr
        call    fmt_err
        mov     si, m_failread
.result:
        call    fmt_out
        jmp     .line

.long:
        mov     si, m_toolong
        jmp     .badline
.bad:
        mov     si, m_badline
.badline:
        mov     di, n_fmt
        call    inc32
        mov     ax, [lineno]
        mov     [num], ax
        mov     ax, [lineno + 2]
        mov     [num + 2], ax
        call    .print_list
        jmp     .line

.ioerr:
        mov     si, m_nameerr
        call    .print_list
        mov     byte [lrc], RC_FATAL

.close:
        mov     bx, [mhandle]
        mov     ah, 0x3e
        call    dos
        cmp     byte [lrc], RC_OK
        jne     .summary
        mov     si, counts + 4          ; any n_ok, n_fmt, n_read, n_sum
        mov     cx, 8
        xor     ax, ax
.any:
        or      ax, [si]
        inc     si
        inc     si
        loop    .any
        test    ax, ax
        jnz     .summary
        mov     si, m_nolines
.fatal_list:
        call    .print_list
        mov     al, RC_FATAL
        ret

.summary:
        mov     di, n_fmt
        mov     si, m_warnfmt
        mov     bx, s_is
        mov     dx, s_are
        call    warn
        mov     di, n_read
        mov     si, m_warnread
        mov     bx, s_none
        mov     dx, s_s
        call    warn
        mov     di, n_sum
        mov     si, m_warnsum
        call    warn

        mov     al, RC_FATAL
        mov     bx, n_fmt
        call    nonzero32
        jnz     .ret
        mov     al, [lrc]
        cmp     al, RC_OK
        jne     .ret
        mov     bx, n_read
        call    nonzero32
        jnz     .fail
        mov     bx, n_sum
        call    nonzero32
        jz      .ret
.fail:
        mov     al, RC_FAIL
.ret:
        ret

; Print the message at SI on stderr, with the manifest's name as [s1].
.print_list:
        mov     ax, [listname]
        mov     [s1], ax
        jmp     fmt_err

; Print the warning at SI on stderr if the count at DI is not zero.
; The count is [num], and [s2] is BX if it is 1 and DX if not.
warn:
        mov     ax, [di]
        mov     cx, [di + 2]
        mov     [num], ax
        mov     [num + 2], cx
        mov     [s2], dx
        jcxz    .low
        jmp     fmt_err
.low:
        cmp     ax, 1
        jb      .ret
        ja      .print
        mov     [s2], bx
.print:
        jmp     fmt_err
.ret:
        ret

; ZF clear if the dword at BX is not zero.
nonzero32:
        push    ax
        mov     ax, [bx]
        or      ax, [bx + 2]
        pop     ax
        ret

; Add 1 to the dword at DI.
inc32:
        add     word [di], 1
        adc     word [di + 2], 0
        ret

;
; Read a manifest line into linebuf, as manifest_getline.  Returns its
; length in AX, or M_EOF, M_LONG or M_IOERR.  A line ends at LF, CR LF,
; a lone CR, or end of file; Ctrl-Z marks end of file.
;
getline:
        xor     di, di                  ; length
        mov     dh, 0                   ; too long
.c:
        call    mgetc
        jc      .eof
        cmp     al, 0x1a
        je      .ctrlz
        cmp     al, 10
        je      .eol
        cmp     al, 13
        je      .cr
        cmp     di, LINESIZE - 1
        jae     .long
        mov     [linebuf + di], al
        inc     di
        jmp     .c
.long:
        mov     dh, 1
        jmp     .c
.cr:
        call    mgetc
        jc      .eol
        cmp     al, 10
        je      .eol
        call    munget
        jmp     .eol
.ctrlz:
        call    munget                  ; so every later call sees it
        jmp     .end
.eof:
        mov     ax, M_IOERR
        cmp     byte [merr], 0
        jne     .ret
.end:
        mov     ax, M_EOF
        test    di, di
        jnz     .eol
        test    dh, dh
        jz      .ret
.eol:
        mov     ax, M_LONG
        test    dh, dh
        jnz     .ret
        mov     byte [linebuf + di], 0
        mov     ax, di
.ret:
        ret

; Get the next manifest byte in AL.  CF set at end of file or on a read
; error, which also sets [merr], as ferror.
mgetc:
        cmp     word [mcnt], 0
        jne     .get
        push    bx
        push    cx
        push    dx
        mov     bx, [mhandle]
        mov     cx, [msize]
        mov     dx, mbuf
        mov     ah, 0x3f
        call    dos
        pop     dx
        pop     cx
        pop     bx
        jc      .err
        mov     [mcnt], ax
        mov     word [mptr], mbuf
        test    ax, ax
        jnz     .get
        stc
        ret
.err:
        mov     byte [merr], 1
        ret
.get:
        push    si
        mov     si, [mptr]
        lodsb
        mov     [mptr], si
        pop     si
        dec     word [mcnt]
        clc
        ret

; Give back the byte mgetc returned last.
munget:
        dec     word [mptr]
        inc     word [mcnt]
        ret

;
; Parse linebuf, of length AX, as manifest_parse.  Returns AL 0 for an
; entry, with its CRC in [want] and its name at SI; 1 for a blank or
; comment line; and -1 for a malformed line.
;
parse:
        mov     cx, ax
        jcxz    .skip
        mov     si, linebuf
        cmp     byte [si], '#'
        je      .skip
        mov     di, si                  ; an embedded NUL
        mov     al, 0
        push    cx
        repne   scasb
        pop     cx
        je      .bad
        cmp     cx, 8 + 2 + 1
        jb      .bad
        xor     bx, bx
        xor     dx, dx
        mov     cx, 8
.hex:
        lodsb
        call    hexval
        jc      .bad
        push    cx
        mov     cl, 4
.shift:
        shl     bx, 1
        rcl     dx, 1
        dec     cl
        jnz     .shift
        pop     cx
        or      bl, al
        loop    .hex
        mov     [want], bx
        mov     [want + 2], dx
        lodsb
        cmp     al, ' '
        jne     .bad
        lodsb
        cmp     al, '*'
        je      .entry
        cmp     al, ' '
        jne     .bad
.entry:
        mov     al, 0
        ret
.skip:
        mov     al, 1
        ret
.bad:
        mov     al, -1
        ret

; The value of the hex digit in AL.  CF set if it is not one.
hexval:
        cmp     al, '0'
        jb      .bad
        cmp     al, '9'
        jbe     .digit
        or      al, 0x20
        cmp     al, 'a'
        jb      .bad
        cmp     al, 'f'
        ja      .bad
        sub     al, 'a' - 10
        clc
        ret
.digit:
        sub     al, '0'
        clc
        ret
.bad:
        stc
        ret

;
; CRC-32/ISO-HDLC, table driven, as crc32.c.
;

; Build the table.
crc_init:
        mov     di, crctab
        xor     cx, cx
.n:
        mov     ax, cx
        xor     dx, dx
        push    cx
        mov     cx, 8
.k:
        shr     dx, 1
        rcr     ax, 1
        jnc     .z
        xor     ax, 0x8320
        xor     dx, 0xedb8
.z:
        loop    .k
        stosw
        xchg    ax, dx
        stosw
        pop     cx
        inc     cl
        jnz     .n
        ret

; Feed CX bytes at SI into the CRC in DX:AX.  CX must not be 0.
crc_update:
        push    bx
.byte:
        mov     bl, [si]
        inc     si
        xor     bl, al
        mov     bh, 0
        shl     bx, 1
        shl     bx, 1
        mov     al, ah
        mov     ah, dl
        mov     dl, dh
        mov     dh, 0
        xor     ax, [crctab + bx]
        xor     dx, [crctab + bx + 2]
        loop    .byte
        pop     bx
        ret

; The CRC of the file named at SI, in DX:AX, as crc_file.  CF set on
; error, with [errno] set.
crc_file:
        call    open_ro
        jc      .ret
        mov     bx, ax
        mov     ax, 0xffff
        mov     dx, ax
.read:
        push    ax
        push    dx
        mov     dx, iobuf
        mov     cx, BUFSIZE
        mov     ah, 0x3f
        call    dos
        mov     cx, ax
        pop     dx
        pop     ax
        jc      .rderr
        jcxz    .eof
        mov     si, iobuf
        call    crc_update
        jmp     .read
.eof:
        not     ax
        not     dx
        push    ax
        push    dx
        mov     ah, 0x3e
        call    dos
        pop     dx
        pop     ax
        clc
        ret
.rderr:
        mov     al, [errno]             ; close may clobber a read error
        push    ax
        mov     ah, 0x3e
        call    dos
        pop     ax
        mov     [errno], al
        stc
.ret:
        ret

; Open the file named at SI for reading, as open().  Returns the
; handle in AX; CF set on error.
open_ro:
        mov     dx, si
        mov     ax, 0x3d00
        ; fall through

; Call DOS.  If it fails (CF set), set [errno] from the error in AX.
dos:
        int     0x21
        jnc     .ret
        call    set_errno
.ret:
        ret

; Set [errno] from the DOS error in AX, and set CF.  Keeps all
; registers.  As in libc16, errors 0 to 18 are looked up in errtab, 80
; is EEXIST and anything else is EACCES.
set_errno:
        push    ax
        push    bx
        cmp     ax, 19
        jae     .high
        mov     bx, errtab
        xlat
        jmp     .set
.high:
        cmp     ax, 80
        mov     al, E_EXIST
        je      .set
        mov     al, E_ACCES
.set:
        mov     [errno], al
        pop     bx
        pop     ax
        stc
        ret

;
; Output.  libc16's streams are unbuffered, so each message is written
; out when it is complete (in pieces of at most 512 bytes on stdout and
; 64 on stderr): the bytes, and their order across the two streams, are
; the same.
;

; Print the format at SI on stdout.
fmt_out:
        mov     word [cur], out_s
        call    fmt
        push    bx
        mov     bx, out_s
        call    flush
        pop     bx
        ret

; Print the format at SI on stderr.
fmt_err:
        mov     word [cur], err_s
        call    fmt
        push    bx
        mov     bx, err_s
        call    flush
        pop     bx
        ret

; Print the format at SI on the current stream.  Bytes 1 to 6 are
; replaced: 1 by the string at [s1], 2 by the string at [s2], 3 by
; strerror(errno), 4 by [num] in decimal, 5 by [num] in eight hex
; digits, and 6 by "crcsum: ".  Keeps all registers but SI.
fmt:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
.c:
        lodsb
        cmp     al, 7
        jae     .char
        test    al, al
        jz      .ret
        mov     bl, al
        mov     bh, 0
        shl     bx, 1
        push    si
        call    [fmt_codes - 2 + bx]
        pop     si
        jmp     .c
.char:
        call    putc
        jmp     .c
.ret:
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

fmt_s1:
        mov     si, [s1]
        jmp     puts
fmt_s2:
        mov     si, [s2]
        jmp     puts
fmt_strerror:
        mov     si, errlist
        mov     cl, [errno]
        mov     ch, 0
        jcxz    puts
.skip:
        lodsb
        test    al, al
        jnz     .skip
        loop    .skip
        jmp     puts
fmt_prog:
        mov     si, s_prog
        jmp     puts
fmt_hex:
        mov     ax, [num + 2]
        call    .word
        mov     ax, [num]
.word:
        mov     cx, 4
.digit:
        push    cx
        mov     cl, 4
        rol     ax, cl
        pop     cx
        push    ax
        and     al, 0x0f
        add     al, '0'
        cmp     al, '9'
        jbe     .put
        add     al, 'a' - '9' - 1
.put:
        call    putc
        pop     ax
        loop    .digit
        ret
fmt_dec:
        mov     ax, [num]
        mov     dx, [num + 2]
        mov     bx, 10
        xor     cx, cx
.div:
        push    ax                      ; DX:AX / 10, in two steps
        mov     ax, dx
        xor     dx, dx
        div     bx
        mov     di, ax
        pop     ax
        div     bx
        push    dx
        inc     cx
        mov     dx, di
        or      di, ax
        jnz     .div
.put:
        pop     ax
        add     al, '0'
        call    putc
        loop    .put
        ret

; Print the string at SI as it is.
puts:
        lodsb
        test    al, al
        jz      .ret
        call    putc
        jmp     puts
.ret:
        ret

; Put AL on the current stream, as fputc in text mode: '\n' is written
; as CR LF.
putc:
        push    bx
        mov     bx, [cur]
        cmp     al, 10
        jne     .one
        push    ax
        mov     al, 13
        call    .put
        pop     ax
        call    .put
        jmp     .ret
.one:
        call    .put
.ret:
        pop     bx
        ret
.put:
        push    di
        mov     di, [bx + S_CNT]
        add     di, [bx + S_BUF]
        mov     [di], al
        inc     word [bx + S_CNT]
        mov     di, [bx + S_CNT]
        cmp     di, [bx + S_SIZE]
        pop     di
        je      flush
        ret

; Write out the stream at BX, as libc16's write does: a short write
; sets errno to ENOSPC, and a failed one maps the DOS error.  Either
; sets the stream's error flag; the first also keeps errno in the
; stream.  The buffer is emptied either way.  Keeps all registers.
flush:
        push    ax
        push    cx
        push    dx
        mov     cx, [bx + S_CNT]
        mov     dx, [bx + S_BUF]
.write:
        jcxz    .done
        push    bx
        mov     bx, [bx + S_HANDLE]
        mov     ah, 0x40
        call    dos
        pop     bx
        jc      .err
        cmp     ax, cx
        je      .done
        mov     byte [errno], E_NOSPC
.err:
        cmp     byte [bx + S_ERR], 0
        jne     .done
        mov     byte [bx + S_ERR], 1
        mov     al, [errno]
        mov     [bx + S_ERRNO], al
.done:
        mov     word [bx + S_CNT], 0
        pop     dx
        pop     cx
        pop     ax
        ret

;
; Data
;

fmt_codes:
        dw      fmt_s1, fmt_s2, fmt_strerror, fmt_dec, fmt_hex, fmt_prog

out_s:  dw      1, outbuf, 512, 0
        db      0, 0
err_s:  dw      2, errbuf, 64, 0
        db      0, 0

errno       db  0
rc          db  RC_OK
check       db  0
endopts     db  0
anyfile     db  0

; errno for DOS errors 0 to 18, as libc16 maps them
errtab:
        db      E_ACCES, E_INVAL, E_NOENT, E_NOENT, E_MFILE, E_ACCES
        db      E_BADF, E_NOMEM, E_NOMEM, E_INVAL, E_2BIG, E_NOEXEC
        db      E_INVAL, E_INVAL, E_ACCES, E_NOENT, E_ACCES, E_XDEV
        db      E_NOENT

; strerror messages, numbered by the E_* constants
errlist:
        db      "No error", 0
        db      "Arg list too long", 0
        db      "Permission denied", 0
        db      "Bad file number", 0
        db      "File exists", 0
        db      "Invalid argument", 0
        db      "Too many open files", 0
        db      "No such file or directory", 0
        db      "Exec format error", 0
        db      "Not enough memory", 0
        db      "No space left on device", 0
        db      "Cross-device link", 0

s_check     db  "--check", 0
s_help      db  "--help", 0
s_version   db  "--version", 0
s_prog      db  "crcsum: ", 0
s_file      db  "FILE", 0
s_manifest  db  "MANIFEST", 0
s_is        db  " is", 0
s_are       db  "s are", 0
s_s         db  "s"
s_none      db  0

m_nomem     db  "Not enough memory", 13, 10
m_nomem_len equ $ - m_nomem

m_usage:
        db      "Usage: crcsum FILE...", 10
        db      "  or:  crcsum -c MANIFEST...", 10
        db      "Print or check CRC-32 (ZIP/Ethernet) checksums.", 10
        db      "Wildcards (* and ?) in FILE are expanded.", 10
        db      10
        db      "  -c, --check    read checksums from the MANIFESTs and check them", 10
        db      "  -h, -?, --help display this help and exit", 10
        db      "      --version  output version information and exit", 10
        db      "      --         treat the remaining arguments as files", 10
        db      10
        db      "ERRORLEVEL is 0 if all files were read and all checksums matched,", 10
        db      "1 if a file was missing, unreadable or did not match, or a wildcard", 10
        db      "matched nothing, and 2 for a usage error, an unreadable or", 10
        db      "malformed manifest, or an output write error.", 10
        db      10
        db      "CRC-32 detects accidental corruption; it is not secure against", 10
        db      "deliberate tampering.", 10, 0
m_version   db  "crcsum (crcsum16) ", VERSION, 10, 0
m_try       db  "Try 'crcsum --help' for more information.", 10, 0
m_stdin     db  6, "reading standard input is not supported", 10, 0
m_unrec     db  6, "unrecognized option '", 1, "'", 10, 0
m_invalid   db  6, "invalid option -- '", 1, "'", 10, 0
m_missing   db  6, "missing ", 1, " operand", 10, 0
m_sum       db  5, " *", 1, 10, 0
m_nameerr   db  6, 1, ": ", 3, 10, 0
m_nomatch   db  6, 1, ": no matching files", 10, 0
m_toolong   db  6, 1, ": ", 4, ": line too long", 10, 0
m_badline   db  6, 1, ": ", 4, ": improperly formatted line", 10, 0
m_nolines   db  6, 1, ": no checksum lines found", 10, 0
m_warnfmt   db  6, "WARNING: ", 4, " line", 2, " improperly formatted", 10, 0
m_warnread  db  6, "WARNING: ", 4, " listed file", 2, " could not be read", 10, 0
m_warnsum   db  6, "WARNING: ", 4, " computed checksum", 2, " did NOT match", 10, 0
m_write     db  6, "write error: ", 3, 10, 0
m_ok        db  1, ": OK", 10, 0
m_failed    db  1, ": FAILED", 10, 0
m_failread  db  1, ": FAILED open or read", 10, 0

image_end:

;
; Uninitialised data, not in the file.  DOS does not clear it.
;
absolute image_end

iobuf       resb BUFSIZE
crctab      resd 256
linebuf     resb LINESIZE
mbuf        resb 512
outbuf      resb 512
errbuf      resb 64
path        resb PATHSIZE
dta         resb 43
chbuf       resb 2
alignb 2
argv        resw 64
argv_end    resw 1
argi        resw 1
cur         resw 1
s1          resw 1
s2          resw 1
num         resd 1
want        resd 1
pattern     resw 1
dirend      resw 1
listname    resw 1
mhandle     resw 1
msize       resw 1
mcnt        resw 1
mptr        resw 1
counts:
lineno      resd 1
n_ok        resd 1
n_fmt       resd 1
n_read      resd 1
n_sum       resd 1
matched     resb 1
grc         resb 1
merr        resb 1
lrc         resb 1
            resb STACK
mem_end:

MEM_PARAS   equ (mem_end - start + 0x100 + 15) / 16
