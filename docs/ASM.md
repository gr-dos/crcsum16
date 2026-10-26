# 8086 assembly build (experiment)

This experiment rewrites crcsum in 8086 assembly (`src/crcsum.asm`,
NASM) as a `.COM` file, to see how small a program with no C runtime
can be (issue #2). The C sources with Open Watcom are still the default
build. Releases include both `crcsum.exe` and `crcsum.com`, and CI
tests both: `make asm` builds `crcsum.com`, and the release workflow
runs `make test-asm` before attaching it. The C version and its tests
are the specification for the assembly version.

## Result

| Build | Format | Bytes | vs Watcom |
| --- | --- | ---: | ---: |
| `crcsum.exe`, Open Watcom 2.0 (default) | `.EXE` | 17,042 | — |
| **`crcsum.com`, NASM** | `.COM` | **3,525** | **−79.3%** |

The `.COM` file is 1,953 bytes of code and 1,572 bytes of data. Of the
data, 688 bytes are the `--help` text and 259 are the `strerror`
messages.

Space taken on disk, in FAT clusters:

| Cluster size (typical media) | `crcsum.exe` | `crcsum.com` |
| --- | ---: | ---: |
| 512 B (1.2 MB, 1.44 MB floppies) | 34 = 17,408 | 7 = 3,584 |
| 1 KB (360 KB, 720 KB floppies) | 17 = 17,408 | 4 = 4,096 |
| 2 KB (FAT16, 64–128 MB) | 9 = 18,432 | 2 = 4,096 |
| 4 KB (FAT12 hard disk; FAT16, 128–256 MB) | 5 = 20,480 | 1 = 4,096 |

On a 360 KB floppy, this saves 13 KB (13 clusters) per copy of crcsum.

## Memory

| | `crcsum.exe` (Watcom) | `crcsum.com` |
| --- | ---: | ---: |
| needed to start | 37,698 bytes (PSP 256 + image 16,994 + minimum allocation 20,448) | 23,936 bytes |
| memory block at exit, measured | 45,888 bytes | 23,936 bytes |

The measured figure is the size of the program's memory block when it
calls DOS to exit, as recorded by `tests/probe.com`. It is the same for
every step of `tests/compare.sh`, summing or checking. For the
`.COM`, it is the PSP, the image, 19,127 bytes of uninitialised data
and a 1 KB stack, rounded up to a paragraph. Most of the data is the 16 KB read buffer that the C
version also has (`BUFSIZE` in `main.c`), and the 1 KB CRC table. The
Watcom figure includes its 2 KB stack and its heap, which holds the
stdio buffers and the argument copy.

At startup the `.COM` checks that its buffers and stack fit in the
memory DOS gave it, then shrinks its block to that size. If they do
not fit, it prints `Not enough memory` on standard error and exits
with status 1. (The Watcom build prints the same text in the same
case, but DOS normally refuses to load it first, since its header asks
for its minimum allocation.)

## Compatibility

- **8086:** the source starts with `cpu 8086`, so NASM rejects any
  later instruction.
- **DOS 2.0 and later:** the program uses only DOS 2.0 functions: 1Ah,
  30h, 3Dh, 3Eh, 3Fh, 40h, 4400h, 4Ah, 4Ch, 4Eh and 4Fh, plus the PSP
  command tail. `tests/compare.sh` runs every comparison a second time
  with DOSBox-X reporting DOS 2.11, with the Watcom build as the
  reference again, and all pass. DOSBox-X still provides its newer
  functions when it reports 2.11, so this checks for version gating
  only; the program has not been run on a real DOS 2.

## Behaviour and tests

| Test | Result |
| --- | --- |
| `tests/run.sh` (72 checks, the existing suite) | 72 passed |
| `tests/compare.sh` (133 cases, 389 files compared, run normally and under DOS 2.11) | 778 passed |

`tests/compare.sh` is new. It runs the same commands with the Watcom
build and the assembly build, each in its own identical fixture tree,
and requires standard output, **standard error** and the exit status
to be the same, byte for byte. DOS cannot redirect standard error, so
the commands are run by `tests/probe.com` (`tests/probe.asm`), a small
test tool that runs a program with its standard error in a file. It
covers what `run.sh` does not:

- known CRC vectors (`a`, `abc`, the quick brown fox, bytes 0 to 255,
  4 KB of 00 and of FF), an empty file, files of 16383, 16384, 16385,
  32768, 65535, 65536 and 65537 bytes around the read size and 64 KB,
  and a 1 MB file;
- wildcards: `*` and `?`, `*.*`, forward slashes, drive-relative
  patterns, directories and subdirectories skipped, no match, a missing
  directory, an invalid drive;
- arguments: quoting (`"a.txt"`, `"a b"`, `a\"b`, `a\\"b c"`, `\"a`,
  `""`, runs of backslashes before a quote, unbalanced quotes, quoted
  leading and trailing spaces), tabs, and command tails of up to 125
  characters;
- every DOS error code 0 to 255, for a file and for a manifest, using
  `tests/fakeerr.com` to make each open fail with it;
- options: every spelling and case, combined short options, options
  after `--`, `-` and `-c -`, and the first of several errors winning;
- manifests: lines of exactly 254 and 255 characters, lines longer
  than the 512-byte read buffer, CR LF split across the read buffer,
  LF CR and CR CR, a final lone CR, embedded NUL and Ctrl-Z, and every
  kind of malformed line;
- 32-bit counters: a malformed line at line 70,000, and 65,537
  malformed lines (the warning count past 65,535);
- singular and plural warnings, and `no checksum lines found`;
- devices (`nul` as a file and as a manifest), a directory as a file
  or manifest, missing files and directories;
- write errors on full floppy images (made by the script): output that
  fails at the final flush, at a buffer flush, and through short
  writes when appending, `--help` to a full disk (status 0, no
  message), and a case where the failed flush is followed by the end
  of a wildcard search, so the message reports the stale `errno`
  ("write error: No such file or directory") as the C version does;
- output redirected to a file that the same command then checksums,
  which shows the stdout buffer size and flush points.

The harness was checked to catch a difference: a build with a 511-byte
stdout buffer and one changed `strerror` message fails 12 steps.

## Building

    make asm          # crcsum.com
    make test-asm     # tests/run.sh on crcsum.com, then
                      # tests/compare.sh against crcsum.exe

`make test-asm` builds `crcsum.exe` too, as the reference, so it needs
Open Watcom as well as NASM.

Tools, as tested:

| Tool | Version |
| --- | --- |
| NASM | 3.01 (any NASM 2.x that supports `-f bin` should do) |
| DOSBox-X | 2026.01.02, for the tests |
| Open Watcom | 2.0 beta, for `crcsum.exe`, the reference |
| Python | 3, for fixtures, as `tests/run.sh` already needs |

Build flags: `nasm -f bin -Werror -DVERSION="<VERSION>" -o crcsum.com
src/crcsum.asm`. The build is reproducible: the same source and
version give the same bytes.

## How it differs from the C version

The assembly version is a separate implementation, written from the C
sources and the behaviour of the Watcom build. It does not link with
any library. The parts of the C runtime that crcsum's behaviour
depends on are reimplemented to match (see Licensing and provenance
for how):

- **Argument splitting** (`parse_tail`) follows the Open Watcom rules
  exactly: spaces and tabs separate, a double quote toggles quoting and
  is removed, `\"` is a literal quote, but in `\\"` the second
  backslash is dropped and the quote still toggles quoting.
- **`open`** skips leading spaces in the name, so a manifest entry
  `* a.txt` opens `a.txt` but is reported as ` a.txt`.
- **`errno` and `strerror`**: DOS error codes are mapped as the Watcom
  runtime does (including its DOS 3 adjustments for sharing errors and
  "file exists"), to the same message text. `errno` is kept across
  calls as in C, which is visible in the final `write error` message.
- **stdio buffering**: standard output is buffered in 512 bytes, or
  flushed at each line on a device; standard error is written in
  64-byte pieces and flushed after each message. A short write sets
  `ENOSPC` and the rest is retried; a failed write sets the error flag
  and the buffer is discarded, as in the Watcom runtime. The manifest
  is read in 512-byte blocks (134 from a device). So the bytes written
  and read, and when, are the same.

What is not the same:

- **Out of memory**: see Memory above. The message also goes to
  standard error, where Watcom writes it to `CON`.
- **Impossible cases are left out.** crcsum's `dosglob.c` reports `path
  too long` for a directory part over 131 characters, but a DOS
  command tail has at most 126. A DOS error with a nonzero high byte,
  and the C runtime's handle-number limit, cannot happen under DOS. The
  32-bit counters cannot wrap within a file DOS can hold.
- **Stack:** 1 KB, against Watcom's 2 KB. Nothing recurses, and the
  deepest call chain uses under 100 bytes, leaving the rest for
  interrupt handlers.

## Licensing and provenance

`src/crcsum.asm` and the test tools `tests/probe.asm` and
`tests/fakeerr.asm` were written for this repository and are MIT
licensed (with SPDX headers).

While writing the first pass, parts of the Open Watcom C runtime
source were read to learn its behaviour; that was not a clean-room
process. A review found two routines that closely translated Watcom
routines: `parse_tail` and `set_errno`. Both were then rewritten in a
two-party clean room, from [ASM-CLEANROOM.md](ASM-CLEANROOM.md), by
an implementer that had not read the Watcom source. A second review
classes no routine as a close translation.

The `strerror` strings, `Not enough memory`, the DOS error mapping and
the stdio buffer sizes match Watcom because they are observable
output.

[ASM-PROVENANCE.md](ASM-PROVENANCE.md) is the full record.

## Maintenance cost

`src/crcsum.asm` is 1,305 lines (about 810 instructions), against 480
lines of C. Every change in behaviour has to be made twice, and the
assembly is harder to review. `tests/compare.sh` reduces the risk: any
difference in output, standard error or exit status for the cases it
covers fails the test. Still, a new feature needs both its code and
its comparison cases written twice.

crcsum's behaviour is small and settled (CRC-32, `md5sum` manifests),
so changes should be rare.

## Recommendation

**Keep the experiment, opt-in as it is, and adopt `crcsum.com` for
distribution when the same rule as for `which16` is agreed.** The
`.COM` is 79% smaller (3.5 KB against 17 KB; 13 KB saved on a 360 KB
floppy), needs about half the memory, and its CRC loop is about three
times as fast as Watcom's in a rough DOSBox-X run (1 MB at a fixed
3000 cycles: 4.8 s against 14.7 s). It runs on the 8086 and DOS 2.0,
which is the machine crcsum is for.

`crcsum.com` is now released alongside `crcsum.exe` (from 0.02). Still
to do:

1. A rule that a PR changing the C version also changes
   `src/crcsum.asm` and adds comparison cases. CI and the release
   workflow already run `make test-asm`.
2. A smoke test on real hardware (the 8088/V20 targets in
   `docs/DESIGN.md`), since all testing so far is under DOSBox-X.

Keep the C version as the specification and reference. Linking the C
version against a minimal per-function library (`gr-dos/libc16`) is a
separate alternative that keeps one implementation; it was not
evaluated here and is worth measuring before the rule is adopted for
more utilities.
