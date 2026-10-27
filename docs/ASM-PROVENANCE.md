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

**This first pass was not a clean-room process.** The same agent read
the Watcom source and wrote the assembly, with no written
specification in between. A first review (below) found two routines
that followed their Watcom counterparts closely. Both were then
rewritten in a clean room (see [Clean-room rewrite](#clean-room-rewrite)),
and a second review found no close translation left.

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

## First review

A separate agent, which had not seen the reasoning behind the code,
compared every routine in both files with the Watcom files above,
before the clean-room rewrite. It classed each routine as **(a) independent** (from crcsum's own C or
generic technique), **(b) behaviour-matching** (reproduces Watcom
behaviour in its own structure) or **(c) close translation**.

| Routine | Class | Notes |
| --- | --- | --- |
| `parse_tail` (since replaced) | **(c)** | Followed `_SplitParms` (`initargv.c` lines 84–164) statement by statement, including the `p[-2]` look-back. Its three-state enum was reduced to a flag. |
| `set_errno`, `doserrs` table (since replaced) | **(c)** | Translated the DOS branch of `__set_errno_dos` (`dosret.c` 324–385): the same conditions and order, the table value for value, and Watcom's internal table indexes 5, 14 and 19. The mapping values are a compatibility fact, but the layout is Watcom's. |
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

## Clean-room rewrite

`parse_tail`, `set_errno` and its table were rewritten in a two-party
clean room:

1. **Black-box tests first.** Before anything was rewritten, the
   following were added to `tests/compare.sh`:
   - 14 more quoting cases, with runs of backslashes before quotes;
   - `tests/fakeerr.asm`, a new tool that runs a build 256 times with
     every DOS open failing with each error code 0–255 in turn, for a
     file and for a manifest.

   They found one more behaviour: an open that "fails" with code 0 is
   reported as `Too many open files`.
2. **The specification.** The author of the first pass wrote
   [ASM-CLEANROOM.md](ASM-CLEANROOM.md). It describes behaviour and
   interfaces only, and its examples and error table were taken from
   the output of `crcsum.exe` (black box), not from the Watcom source.
3. **The implementation.** A separate agent implemented the routines.
   It had never read the Open Watcom runtime source and was told not
   to (on disk, on the web, or from memory). It worked in a copy of
   the repository with the three pieces removed, without git history,
   these documents or the Watcom tree. It read only the
   specification, `src/crcsum.asm` and the test scripts, and tested
   against `crcsum.exe`. Its own statement: it read only those files
   and had no lapses.
4. **Integration.** Its file was copied into the repository unedited.
   Both test suites pass (`tests/run.sh` 72 of 72, `tests/compare.sh`
   778 of 778).

After the second review (below), the internal message numbers (`E_*`)
were renumbered alphabetically. The first pass had numbered the first
ten in the same order as Watcom's DOS errno values; the numbers are
not visible in the output.

## Second review

Another separate agent compared the three new pieces with
`_SplitParms`, `__set_errno_dos` and `__sopen`:

| Routine | Class | Notes |
| --- | --- | --- |
| `parse_tail` | (b) | Same behaviour, including the backslash-quote rule, but its own design: one pass, a quote bit, the previous byte carried in a register, tests in a different order. There is no statement-by-statement correspondence. |
| `set_errno`, `errtab` | (b) | Codes 0–18 by table, then direct range tests, with no index redirection or sentinel entry. The 19 table values equal Watcom's DOS mapping, which is forced, because every code is compared byte for byte with `crcsum.exe`. |
| `open_ro` | (b) | It handles error 0 directly, not through Watcom's mechanism (a sentinel handle and an unsigned compare). |

Verdict, in its words: "None of the three routines is a close
translation … A licensing record can fairly describe these routines
as independently written for compatibility, with the table values
taken for behavioural fidelity."

## Status

No routine is classed as a close translation:

- Every routine in `src/crcsum.asm` is either independent (a) or
  matches Watcom's behaviour in its own structure (b).
- The `strerror` messages, the `Not enough memory` text, the DOS
  error mapping values and the stdio buffer sizes match Watcom
  because they are observable behaviour.

The first-pass versions of `parse_tail` and `set_errno` remain in the
history of PR #3 (commit `1bd6ac4`).

Nothing from this experiment should be carried into `gr-dos/libc16`,
which keeps its own specification-first process.

## Moving to libc16

When `crcsum.exe` moved from Open Watcom's runtime to
[libc16](https://github.com/gr-dos/libc16), the C version stopped
showing Watcom's behaviour, so the assembly had to follow libc16
instead. `parse_tail`, `open_ro`, `set_errno`, the `errtab` and
`errlist` tables and the output code (`fmt_out`, `putc`, `flush`) were
rewritten from libc16's specifications (`docs/spec/startup.md`,
`io.md`, `stdio.md`, `string.md`) by Claude, in the session that wrote
those specifications. That session has not read the Open Watcom
runtime source, and did not use the routines it replaced as a model:
the new `parse_tail` follows the splitter written for
[truncate16](https://github.com/gr-dos/truncate16). Both suites pass
against the libc16 build (`tests/run.sh` 72 of 72, `tests/compare.sh`
778 of 778). Nothing went from this repository into libc16.
