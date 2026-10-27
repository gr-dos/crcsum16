# 8086 assembly build (experiment)

This experiment rewrites crcsum in 8086 assembly (`src/crcsum.asm`,
NASM) as a `.COM` file, to see how small a program with no C runtime
can be (issue #2). The C sources, built with Open Watcom and libc16,
are still the default build. Releases include both `crcsum.exe` and `crcsum.com`, and CI
tests both: `make asm` builds `crcsum.com`, and the release workflow
runs `make test-asm` before attaching it. The C version and its tests
are the specification for the assembly version.

## Result

| Build | Format | Bytes | vs C |
| --- | --- | ---: | ---: |
| `crcsum.exe`, Open Watcom with libc16 (default) | `.EXE` | 5,946 | — |
| **`crcsum.com`, NASM** | `.COM` | **3,417** | **−42.5%** |
| `crcsum.exe` with Open Watcom 2.0's own runtime (before libc16) | `.EXE` | 17,042 | +187% |

The `.COM` file is 1,891 bytes of code and 1,526 bytes of data. Of the
data, 688 bytes are the `--help` text and 214 are the `strerror`
messages.

Space taken on disk, in FAT clusters:

| Cluster size (typical media) | `crcsum.exe` | `crcsum.com` |
| --- | ---: | ---: |
| 512 B (1.2 MB, 1.44 MB floppies) | 12 = 6,144 | 7 = 3,584 |
| 1 KB (360 KB, 720 KB floppies) | 6 = 6,144 | 4 = 4,096 |
| 2 KB (FAT16, 64–128 MB) | 3 = 6,144 | 2 = 4,096 |
| 4 KB (FAT12 hard disk; FAT16, 128–256 MB) | 2 = 8,192 | 1 = 4,096 |

On a 360 KB floppy, this saves 2 KB (2 clusters) per copy of crcsum.
Before libc16 it saved 13.

## Memory

| | `crcsum.exe` (libc16) | `crcsum.com` |
| --- | ---: | ---: |
| needed to start | 27,082 bytes (PSP 256 + image 5,898 + minimum allocation 20,928) | 23,824 bytes |
| memory block at exit, measured | 27,072 bytes | 23,824 bytes |

The measured figure is the size of the program's memory block when it
calls DOS to exit, as recorded by `tests/probe.com`. It is the same for
every step of `tests/compare.sh`, summing or checking. For the
`.COM`, it is the PSP, the image, 19,127 bytes of uninitialised data
and a 1 KB stack, rounded up to a paragraph. Most of the data is the 16 KB read buffer that the C
version also has (`BUFSIZE` in `main.c`), and the 1 KB CRC table. The
`.EXE` figure also includes libc16's stack and its static stdio
buffers. (With Open Watcom's own runtime it was 45,888 bytes at exit.)

At startup the `.COM` checks that its buffers and stack fit in the
memory DOS gave it, then shrinks its block to that size. If they do
not fit, it prints `Not enough memory` on standard error and exits
with status 1. (DOS refuses to load the `.EXE` in the same case, since
its header asks for its minimum allocation.)

## Compatibility

- **8086:** the source starts with `cpu 8086`, so NASM rejects any
  later instruction.
- **DOS 2.0 and later:** the program uses only DOS 2.0 functions: 1Ah,
  3Dh, 3Eh, 3Fh, 40h, 4Ah, 4Ch, 4Eh and 4Fh, plus the PSP command
  tail. `tests/compare.sh` runs every comparison a second time with
  DOSBox-X reporting DOS 2.11, with the C build as the reference again,
  and all pass. DOSBox-X still provides its newer
  functions when it reports 2.11, so this checks for version gating
  only; the program has not been run on a real DOS 2.

## Behaviour and tests

| Test | Result |
| --- | --- |
| `tests/run.sh` (72 checks, the existing suite) | 72 passed |
| `tests/compare.sh` (133 cases, 389 files compared, run normally and under DOS 2.11) | 778 passed |

`tests/compare.sh` is new. It runs the same commands with the C build
and the assembly build, each in its own identical fixture tree,
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
  message), and a case where the failed write is followed by the end
  of a wildcard search, which sets `errno` to ENOENT; the message
  still reports the write's own error, as the C version keeps it;
- output redirected to a file that the same command then checksums,
  which shows when output reaches the file.

The harness was checked to catch a difference: a build with a 511-byte
stdout buffer and one changed `strerror` message fails 12 steps.

## Building

    make asm          # crcsum.com
    make test-asm     # tests/run.sh on crcsum.com, then
                      # tests/compare.sh against crcsum.exe

`make test-asm` builds `crcsum.exe` too, as the reference, so it needs
libc16 and its toolchain (fetched by `make`) as well as NASM.

Tools, as tested:

| Tool | Version |
| --- | --- |
| NASM | 3.01 (any NASM 2.x that supports `-f bin` should do) |
| DOSBox-X | 2026.01.02, for the tests |
| libc16 | the revision pinned in `scripts/fetch-libc16`, with its Open Watcom snapshot, for `crcsum.exe`, the reference |
| Python | 3, for fixtures, as `tests/run.sh` already needs |

Build flags: `nasm -f bin -Werror -DVERSION="<VERSION>" -o crcsum.com
src/crcsum.asm`. The build is reproducible: the same source and
version give the same bytes.

## How it differs from the C version

The assembly version is a separate implementation, written from the C
sources. It does not link with any library. The parts of the C runtime
that crcsum's behaviour depends on follow libc16's specifications (its
`docs/spec/`):

- **Argument splitting** (`parse_tail`) follows Microsoft C's rule, as
  libc16 does: spaces and tabs separate, a double quote toggles quoting
  and is removed, a run of 2n backslashes before a quote gives n
  backslashes and a toggle, 2n + 1 give n backslashes and a literal
  quote, and any other backslash is literal.
- **`open`** passes the name to DOS as it is, so a manifest entry
  `* a.txt` names ` a.txt`, which DOS does not find.
- **`errno` and `strerror`**: DOS error codes are mapped as libc16 maps
  them (codes 0 to 18 by table, 80 to EEXIST, any other to EACCES), to
  the same message text.
- **stdio buffering**: libc16's streams are unbuffered, so the assembly
  writes each message out as soon as it is complete (standard output
  in pieces of up to 512 bytes, standard error up to 64). The bytes in
  each stream, their order, and what a file being written holds when
  the program reads it, are the same. A short write sets `ENOSPC`, a
  failed one maps the DOS error, and either sets the error flag. The
  manifest is read in 128-byte blocks, libc16's `fopen` buffer.

What is not the same:

- **Out of memory**: see Memory above.
- **Impossible cases are left out.** crcsum's `dosglob.c` reports `path
  too long` for a directory part over 131 characters, but a DOS
  command tail has at most 126. A DOS error with a nonzero high byte,
  and the C runtime's handle-number limit, cannot happen under DOS. The
  32-bit counters cannot wrap within a file DOS can hold.
- **Stack:** 1 KB. Nothing recurses, and the
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

When `crcsum.exe` moved to libc16, `parse_tail`, `open_ro`,
`set_errno`, the `errtab` and `errlist` tables and the output code were
rewritten to follow libc16's specifications instead, by a session that
had not read the Open Watcom runtime source.

[ASM-PROVENANCE.md](ASM-PROVENANCE.md) is the full record.

## Maintenance cost

`src/crcsum.asm` is 1,276 lines, against 521 lines of C. Every change
in behaviour has to be made twice, and the assembly is harder to
review. `tests/compare.sh` reduces the risk: any difference in output,
standard error or exit status for the cases it covers fails the test.
Still, a new feature needs both its code and its comparison cases
written twice.

crcsum's behaviour is small and settled (CRC-32, `md5sum` manifests),
so changes should be rare.

## Recommendation

**Keep the experiment, opt-in as it is, and adopt `crcsum.com` for
distribution when the same rule as for `which16` is agreed.** Against
the libc16 build the `.COM` is 42% smaller (3.3 KB against 5.8 KB; 2
KB saved on a 360 KB floppy) and needs about 12% less memory. Against
the earlier Open Watcom runtime build it was 79% smaller, and its CRC
loop was about three times as fast in a rough DOSBox-X run (1 MB at a
fixed 3000 cycles: 4.8 s against 14.7 s; not yet measured with
libc16). It runs on the 8086 and DOS 2.0, which is the machine crcsum
is for.

`crcsum.com` is now released alongside `crcsum.exe` (from 0.02). Still
to do:

1. A rule that a PR changing the C version also changes
   `src/crcsum.asm` and adds comparison cases. CI and the release
   workflow already run `make test-asm`.
2. A smoke test on real hardware (the 8088/V20 targets in
   `docs/DESIGN.md`), since all testing so far is under DOSBox-X.

Keep the C version as the specification and reference. It now links
`gr-dos/libc16`, a per-function library, which closes most of the size
gap with one implementation: the `.COM` saves 2 clusters on a 360 KB
floppy, where it used to save 13.
