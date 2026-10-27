# Clean-room specification: argument splitting and DOS error messages

This is the specification given to the implementer of `parse_tail`,
`set_errno` and the error-code part of `open_ro` in `src/crcsum.asm`.
It describes behaviour and interfaces only. The behaviour was observed
from `crcsum.exe` (the Open Watcom build) with `tests/compare.sh` and
`tests/fakeerr.com`. The implementer works from this document, the
rest of `src/crcsum.asm`, crcsum's C sources and black-box tests, and
has not read the Open Watcom runtime source. See
[ASM-PROVENANCE.md](ASM-PROVENANCE.md) for the process.

This document is historical: since `crcsum.exe` links libc16, these
routines follow libc16's specifications instead (see "Moving to
libc16" in ASM-PROVENANCE.md).

## 1. Splitting the command tail into arguments

### Interface

`parse_tail` is called once at startup with DS = ES = CS (the PSP
segment) and the direction flag clear. It may change AX, BX, CX, DX,
SI and DI. It must:

- store a pointer to each argument, in order, in the word array
  `argv` (64 words), and set `argv_end` to the address just past the
  last pointer stored;
- leave each argument as a NUL-terminated string that stays unchanged
  for the rest of the run.

Bytes 80h–FFh of the PSP (the tail) are not used for anything else
after `parse_tail` returns. You may use them for the strings, or a
buffer of your own in the uninitialised data. The DTA is elsewhere.
DOS limits the tail so that there are never more than 63 arguments.

### Input

The byte at PSP:80h is the tail length L. The tail is the min(L, 126)
bytes from PSP:81h. A NUL byte within those bytes ends the tail early.
The CR that DOS puts after the tail is not part of it.

### Rules

1. Arguments are separated by runs of spaces (20h) and tabs (09h) that
   are not inside quotes. Blanks at the start and end of the tail are
   ignored.
2. A double quote (`"`) switches quoting on or off and is not part of
   the argument. Inside quotes, spaces and tabs are ordinary
   characters. Quoting can switch on and off any number of times within
   one argument. A quote left open runs to the end of the tail.
3. An argument exists as soon as a byte that is not a blank starts it,
   even if quotes then remove everything (`""` is one empty argument).
4. A backslash (`\`) that is not immediately followed by `"` is an
   ordinary character.
5. A backslash immediately followed by `"` is not copied. What happens
   to the `"` depends on the byte just before the backslash in the
   original tail:
   - If that byte is not a backslash, the `"` is a literal character in
     the argument and does not switch quoting.
   - If that byte is a backslash, the `"` switches quoting as in rule 2.

   The earlier backslash still counts here even though rule 4 has
   already copied it. If the backslash is the first byte of the tail,
   the byte before it counts as not a backslash.
6. Nothing else is special: there is no wildcard expansion, no case
   change and no other escape.

### Examples

Observed from `crcsum.exe`. The left column is the text after the
program name; each argument is shown in brackets.

| Tail | Arguments |
| --- | --- |
| `"a.txt" b.bin` | `[a.txt]` `[b.bin]` |
| `"a.txt b.bin"` | `[a.txt b.bin]` |
| `a"."txt` | `[a.txt]` |
| `"a"b"c d"` | `[abc d]` |
| `a""b` | `[ab]` |
| `""` | `[]` |
| `" a.txt"` | `[ a.txt]` |
| `"a.txt "` | `[a.txt ]` |
| `"a.txt` | `[a.txt]` |
| `a.txt<TAB>b.bin` | `[a.txt]` `[b.bin]` |
| `<TAB>a.txt` | `[a.txt]` |
| `a\b` | `[a\b]` |
| `a\` | `[a\]` |
| `"a\ b"` | `[a\ b]` |
| `a\"b` | `[a"b]` |
| `\"a.txt` | `["a.txt]` |
| `x\"y\"z` | `[x"y"z]` |
| `"a\"b"` | `[a"b]` |
| `"\"a.txt"` | `["a.txt]` |
| `a\\"b c"` | `[a\b c]` |
| `\\"a.txt b"` | `[\a.txt b]` |
| `\\"x"` | `[\x]` |
| `"\\"` | `[\]` |
| `\\\"a.txt` | `[\\a.txt]` |
| `a\\\"b` | `[a\\b]` |
| `a\\\\"b c"` | `[a\\\b c]` |

## 2. DOS error codes to messages

### Interface

`[errno]` is a byte holding the number of the message that `strerror`
would give: one of the `E_*` constants in `src/crcsum.asm`, which
number the strings in `errlist`. `[dosmajor]` holds the DOS major
version (from INT 21h function 30h).

`set_errno` is called (with CALL) after a DOS call fails, with the DOS
error code in AL (ignore AH). It must set `[errno]` from the code as
below, return with CF set, and keep every other register.

### Mapping

| DOS error code (decimal) | Message (`E_*`) |
| --- | --- |
| 0 | No error (`E_NOERR`), except for open: see below |
| 1 | Invalid argument (`E_INVAL`) |
| 2, 3 | No such file or directory (`E_NOENT`) |
| 4 | Too many open files (`E_MFILE`) |
| 5 | Permission denied (`E_ACCES`) |
| 6 | Bad file number (`E_BADF`) |
| 7, 8, 9 | Not enough memory (`E_NOMEM`) |
| 10 | Arg list too big (`E_2BIG`) |
| 11 | Exec format error (`E_NOEXEC`) |
| 12 | unknown error (`E_UNKNOWN`) |
| 13 | Result too large (`E_RANGE`) |
| 14 | File exists (`E_EXIST`) |
| 15 | No such device (`E_NODEV`) |
| 16 | Permission denied (`E_ACCES`) |
| 17 | Cross-device link (`E_XDEV`) |
| 18 | No such file or directory (`E_NOENT`) |
| 32, 33, DOS 3 or later | Permission denied (`E_ACCES`) |
| 80, DOS 3 or later | File exists (`E_EXIST`) |
| any other code (19–255, and 32, 33 and 80 before DOS 3) | unknown error (`E_UNKNOWN`) |

This was observed for every code 0–255 by making each file open fail
with it, under DOS 5 and DOS 2.11 as DOSBox-X reports them.

### Open failing with code 0

When the open in `open_ro` (INT 21h, AX = 3D00h) returns CF set with
AX = 0, the failure is reported as Too many open files (`E_MFILE`), not
No error. `open_ro` must still return CF set. (DOS never does this; the
behaviour is observed with `tests/fakeerr.com`.) For every other DOS
call, code 0 gives No error.

## 3. Tests

Both are run by `make test-asm`:

- **`tests/compare.sh`:** the quoting cases in the step list, and the
  `err1` and `err2` steps (`tests/fakeerr.com`, every error code, for
  a file and for a manifest), all compared with `crcsum.exe` under
  DOS 5 and DOS 2.11.
- **`tests/run.sh`:** the general suite.
