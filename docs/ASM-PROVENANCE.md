# Provenance of the assembly version

This is the record for `src/crcsum.asm` and `tests/probe.asm`: what
Open Watcom C runtime source was read while writing them, what was taken
from it, how the assembly was written, and an independent review of the
result. The Open Watcom runtime is under the Sybase Open Watcom Public
License; crcsum is MIT. See [ASM.md](ASM.md) for the experiment itself.

## How the assembly was written

The assembly was written by Claude (an AI coding assistant), working in
one session with Graham Ollis. In that session it:

1. Read crcsum's own C sources (`src/*.c`, MIT), which specify the
   program.
2. Read the Open Watcom runtime files listed below, to learn how the C
   runtime behaves where that behaviour shows in crcsum's output.
3. Wrote `src/crcsum.asm` and `tests/probe.asm` directly, then tested
   them against `crcsum.exe` with `tests/compare.sh`.

**This was not a clean-room process.** The same agent read the Watcom
source and wrote the assembly, with no written specification in
between. As a result, two routines follow their Watcom counterparts
closely (see the review below).

## Watcom sources read

All from [open-watcom-v2](https://github.com/open-watcom/open-watcom-v2)
at commit `41126b781a8e0042380c0e01a6ecf09d9dad68bd`, under `bld/clib`,
plus the headers installed with Open Watcom 2.0.

| File | Routine | What was taken (behaviour or fact) |
| --- | --- | --- |
| `startup/c/initargv.c` | `_SplitParms` | The argument-splitting rules: blanks and tabs separate arguments, `"` toggles quoting and is removed, `\"` is a literal quote, `\\"` keeps one backslash and still toggles. The split is done in place, which affects the `\\"` look-back. |
| `startup/a/cstrt086.asm` | startup, `__do_exit_with_msg_` | The command tail is taken by its length byte with leading spaces skipped. Out of memory gives the message `Not enough memory`, CR LF, exit status 1. |
| `string/c/strerror.c`, `string/h/errstr.h` | `strerror`, `_sys_errlist` | The DOS errno numbering, the message strings, and `unknown error` for an out-of-range errno. |
| `_dos/c/dosret.c` | `__set_errno_dos` | The DOS error → errno table and its DOS 3 adjustments (50h, 20h–21h, 22h and up). |
| `_dos/a/error086.asm` | `__doserror_` | DOS calls made this way set errno on failure, so findfirst and findnext do too. |
| `_dos/c/opendos.c` | `_dos_open` | The default library opens with 3Dh and has no long-filename path. (Also checked in the linker map of `crcsum.exe`.) |
| `_dos/c/finddos.c` | `_dos_findfirst`, `_dos_findnext` | 4Eh and 4Fh through the DTA; errno is set on failure. |
| `handleio/c/open.c` | `__sopen` | Leading spaces are skipped in the name; `O_RDONLY` opens with access mode 0; a handle of 20 or more gives EMFILE. |
| `handleio/c/read.c` | `read` | In binary mode, one DOS read per call. |
| `handleio/c/qwrit.c` | `__qwrite` | A short write sets ENOSPC. |
| `environ/c/isatt.c` | `isatty` | IOCTL 4400h, device bit 80h. |
| `streamio/c/fputc.c` | `fputc` | In text mode `\n` becomes CR LF. The buffer is flushed when full, or at `\n` when line buffered. |
| `streamio/c/flush.c` | `__flush` | A short write is retried; a failed or zero-byte write sets the error flag; the buffer is emptied either way. |
| `streamio/c/chktty.c`, `ioalloc.c` | `__chktty`, `__ioalloc` | A device is line buffered. Buffer sizes are 134 (line buffered), 64 (unbuffered) and `BUFSIZ` otherwise. |
| `streamio/c/iob.c`, `initfile.c` | `__iob`, `__InitFiles` | stdout starts with no buffering mode set; stderr is unbuffered. |
| `streamio/c/fprtf.c` | `__fprtf` | An unbuffered stream is fully buffered for one `printf` and flushed at its end. |
| `streamio/c/fflush.c` | `fflush` | It calls `__flush`. |
| `streamio/c/fgetc.c` | `__fill_buffer`, `fgetc` | A refill reads `bufsize` bytes. 0 bytes is end of file; −1 sets the error flag. |
| `streamio/c/fopen.c` | `fopen` | Skimmed only: compatibility sharing mode. |
| installed `h/stdio.h`, `h/share.h` | | `BUFSIZ` is 512 for 16-bit code; `SH_COMPAT` is 0. |

## Independent review

A separate agent, which had not seen the reasoning behind the code,
compared every routine in both files with the Watcom files above. It
classed each routine as **(a) independent** (from crcsum's own C or
generic technique), **(b) behaviour-matching** (reproduces Watcom
behaviour in its own structure) or **(c) close translation**.

| Routine | Class | Notes |
| --- | --- | --- |
| `parse_tail` | **(c)** | Follows `_SplitParms` (`initargv.c` lines 84–164) statement by statement, including the `p[-2]` look-back. Its three-state enum is reduced to a flag. |
| `set_errno`, `doserrs` table | **(c)** | Translates the DOS branch of `__set_errno_dos` (`dosret.c` 324–385): the same conditions and order, the table value for value, and Watcom's internal table indexes 5, 14 and 19. The mapping values are a compatibility fact, but the layout is Watcom's. |
| `errlist` | (b), data | 15 strings verbatim from `_sys_errlist` and `UNKNOWN_ERROR`, renumbered densely. They must be verbatim for identical output. |
| `putc`, `flush`, `mgetc` | (b) | Same observable sequence as `fputc`, `__flush` + `__qwrite` and `__fill_buffer`, but structured independently; the order is dictated by the behaviour. |
| startup, `nomem`, `open_ro`, `dos`, `isatty` | (b), trivial | Standard DOS idioms that match Watcom's behaviour. |
| everything else in `crcsum.asm` | (a) | Translated from crcsum's own MIT C (`main.c`, `manifest.c`, `dosglob.c`, `crc32.c`), or generic, including the `fmt` format engine. |
| `tests/probe.asm` | (a) | Nothing related to the Watcom files. |

No comments were copied. Identifiers are standard POSIX names
(`errno`, `E_*`) or the project's own.

The reviewer noted one small behavioural difference. Watcom writes
`Not enough memory` to `CON`; the assembly writes it to standard
error. The two differ only when standard error is redirected.

## Status

`parse_tail`, `set_errno` and `doserrs` are close translations of
Watcom-licensed routines. They are short, and almost all of their
content is functional, but until they are rewritten the assembly
should not be described as written independently of Watcom. The
reviewer recommends rewriting them from a prose specification, ideally
by someone who has not read the Watcom files. For `set_errno`, that
means mapping DOS codes straight to messages rather than through
Watcom's table layout. Each rewrite should be tested with comparison
cases for quoting and for every DOS error code.

Nothing from this experiment should be carried into `gr-dos/libc16`,
which keeps its own specification-first process.
