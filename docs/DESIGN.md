# CRCSUM — Design Document

**Status:** Proposed  
**Target:** MS-DOS, 8086/8088 and compatible CPUs  
**Executable:** `CRCSUM.EXE`  
**Implementation:** 16-bit C, Open Watcom, built on Linux

## 1. Purpose

CRCSUM is a small, fast CRC-32 checksum utility for DOS, intended for verifying file transfers on XT-class computers such as Phaistos (NEC V20). It offers the familiar `md5sum` workflow—generate checksums for files, save a manifest, and check the manifest—without the substantial cost of MD5's 32-bit arithmetic on a 16-bit CPU.

CRCSUM detects accidental corruption; **CRC-32 is not cryptographically secure** and must not be used to authenticate untrusted files.

## 2. Goals

- Run on an original IBM PC with an 8088 under DOS, as well as later compatible machines.
- Calculate the standard CRC-32 used by ZIP and Ethernet.
- Support multiple filenames and DOS wildcard patterns, including `*` and `?`.
- Produce and verify a simple, portable, text checksum manifest.
- Match the hexadecimal CRC values reported by conventional Linux ZIP/Ethernet CRC-32 utilities.
- Read input files in binary mode, including embedded `0x1A` bytes.
- Be efficient in conventional memory and on slow processors.
- Return useful DOS `ERRORLEVEL` values for scripts.
- Build and test from Linux using Open Watcom and GNU make.

## 3. Non-goals

- Cryptographic integrity or signatures.
- Support for CRC variants other than CRC-32/ISO-HDLC in the initial version.
- Long-filename support on DOS, recursive directory traversal, or shell-like globbing beyond DOS filename wildcards.
- Changing or repairing files.
- A resident component, driver, or network protocol.

## 4. Command-line interface

```dos
CRCSUM FILE [FILE ...]
CRCSUM PATTERN [PATTERN ...]
CRCSUM -C MANIFEST
CRCSUM -? 
CRCSUM --HELP
CRCSUM --VERSION
```

`-c` and `-C` are equivalent because DOS command-line options are conventionally case-insensitive. Long options are optional conveniences if they fit implementation constraints.

Examples:

```dos
C:\> CRCSUM BCOM.EXE
c9a5b712 *BCOM.EXE

C:\> CRCSUM *.EXE > CRC32.SUM
C:\> CRCSUM -C CRC32.SUM
BCOM.EXE: OK
TICO.EXE: OK
```

The checksum above is illustrative, not a verified checksum of BCOM.EXE.

### 4.1 Checksum output

Each successfully read file produces one line:

```text
<eight lowercase hexadecimal digits><space><asterisk><filename>
```

For example:

```text
cbf43926 *123456789.TXT
```

The asterisk is the conventional `md5sum` binary-mode marker. Filenames are written as supplied or as expanded by DOS wildcard enumeration, without forced uppercasing beyond what DOS returns. CRCSUM itself always reads file contents in binary mode.

Use CRLF when writing DOS output; the manifest parser must accept both CRLF and LF (and may accept lone CR for convenience). The manifest is ASCII text.

**Compatibility note:** This format resembles `md5sum`, but standard GNU `cksum --algorithm=crc32` output formatting is not guaranteed to be identical. Compatibility means identical *CRC values*, not that every Linux checksum utility can directly read CRCSUM manifests. A small Linux-side conversion script or companion tool can be added later if desired.

### 4.2 Check mode

`CRCSUM -C MANIFEST` reads each entry and verifies the named file relative to the current working directory, like `md5sum -c`.

Output:

```text
FOO.EXE: OK
BAR.EXE: FAILED
MISSING.EXE: FAILED open or read
```

The command prints a summary to stderr if any files fail or manifest entries are malformed. Invalid entries must not silently count as successes. If the same file appears more than once, check each entry in order.

### 4.3 Wildcards

`COMMAND.COM` does not expand wildcards. CRCSUM must enumerate matching files itself using DOS `findfirst`/`findnext` services (or the corresponding Open Watcom APIs). Expand patterns independently; emit results in the order DOS returns them, unless sorting is added later. Skip directories and volume labels. A pattern matching nothing is an error, not a successful empty manifest.

A literal filename without wildcards should be opened directly. The initial version does not recurse into directories; paths containing directories are allowed if DOS accepts them.

### 4.4 Error levels

| ERRORLEVEL | Meaning |
| --- | --- |
| `0` | All requested files processed successfully; in check mode, every checksum matched. |
| `1` | At least one file was missing, unreadable, or had a checksum mismatch; or a wildcard matched nothing. |
| `2` | Usage error, unreadable/malformed manifest, or other fatal processing error. |

If both mismatches and malformed entries occur, return `2`. Document error behavior in `--HELP` and the README.

## 5. CRC specification

Use **CRC-32/ISO-HDLC**, also known as CRC-32/ADCCP, ZIP CRC-32, or Ethernet CRC-32:

| Parameter | Value |
| --- | --- |
| Width | 32 bits |
| Polynomial (normal) | `0x04C11DB7` |
| Reflected polynomial | `0xEDB88320` |
| Initial register | `0xFFFFFFFF` |
| Reflect input/output | Yes |
| Final XOR | `0xFFFFFFFF` |
| Check string `123456789` | `0xCBF43926` |

The checksum covers **file bytes only**: do not include filename, file length, DOS EOF marker semantics, or line-ending conversion.

## 6. Implementation

### 6.1 Language and runtime

- ANSI C compatible with Open Watcom's 16-bit DOS compiler.
- Target an 8086-compatible real-mode DOS executable; do not require 286+ instructions, DPMI, or extended memory.
- Keep dependencies limited to the DOS C runtime and small local modules.
- Prefer a simple command-line utility rather than a complex framework.

### 6.2 CRC computation

Use a 256-entry lookup table of 32-bit values (1,024 bytes). Generate the table at compile time or initialize it once at startup. For each input byte:

```c
crc = table[(crc ^ byte) & 0xff] ^ (crc >> 8);
```

Initialize `crc` to `0xFFFFFFFF` and XOR with `0xFFFFFFFF` when finished. Open Watcom may implement 32-bit operations using multiple 16-bit instructions; benchmark before considering assembly optimization or slicing algorithms.

Read files in chunks (initially 4–16 KiB, benchmarked on real hardware). Do not load whole files into memory. Open in binary mode (`"rb"`) so DOS C runtime text translation and `0x1A` handling cannot affect results.

### 6.3 Filename and manifest handling

- DOS 8.3 filenames are the initial scope; use DOS paths and separators.
- Read manifest lines into a bounded buffer large enough for DOS paths; detect and reject overlong lines rather than truncating them.
- Parse exactly eight hexadecimal digits, a space, and either `*` (binary) or optionally a space (GNU text marker), followed by a nonempty filename.
- Since CRCSUM hashes bytes exactly, treat both markers identically when verifying, but always emit `*`.
- Support CRLF and LF manifest lines.
- Do not execute or interpret filenames as commands.
- The first version may reject filenames containing newline characters, which are not valid conventional DOS filenames.
- Treat a filename starting with `-` as an operand only when option parsing has ended (e.g., after `--`, if supported).

### 6.4 Robustness

- Report path and DOS error context for failed opens/reads.
- Check write errors on stdout as well as read errors; a full disk while redirecting a manifest must produce a nonzero exit status where detectable.
- Never modify input files.
- Avoid large stack allocations and recursion.
- Support files larger than 64 KiB by streaming; do not assume `size_t` or offsets are 32-bit.
- Check arithmetic types carefully: use an explicitly 32-bit unsigned type for CRC state.

## 7. Suggested repository structure

```text
crcsum/
  README.md
  DESIGN.md
  VERSION
  Makefile
  src/
    main.c
    crc32.c
    crc32.h
    manifest.c
    manifest.h
    dosglob.c
    dosglob.h
  tests/
    test_crc32.c
    test_manifest.c
  .github/workflows/
    ci.yml
    release.yml
```

Use the existing `hello16`/tico16 Open Watcom build and CI patterns where convenient, without taking on editor-specific infrastructure.

## 8. Testing strategy

### 8.1 Host-side unit tests

Compile portable CRC and manifest code with a native C compiler on Linux:

- Empty file → `00000000`.
- ASCII `123456789` → `cbf43926`.
- Binary vectors containing `0x00`, `0x1A`, `0x80`, and `0xFF`.
- Chunk-boundary tests and incremental CRC updates.
- Manifest parsing for LF and CRLF, invalid hex, missing marker, empty filename, overlong line, and missing final newline.

### 8.2 DOS integration tests

Run `CRCSUM.EXE` in DOSBox-X or another DOS emulator:

- Hash one file and multiple files.
- Expand `*.EXE`, `?.TXT`, and a wildcard with no matches.
- Generate a manifest with output redirection and verify with `-C`.
- Detect modified files, missing files, malformed manifests, and unreadable inputs.
- Verify `ERRORLEVEL` for success, mismatch, and fatal error.
- Verify that binary files containing Ctrl+Z hash fully.
- Check paths containing spaces if supported by the chosen DOS shell and argument parsing.

### 8.3 Real hardware

Test on Phaistos (NEC V20, DOS 6.22), particularly:

- Startup and memory footprint.
- CRC correctness on transferred executables.
- Throughput compared with the available DOS `md5sum`.
- File I/O and disk cache effects for small and large files.
- Manifest generation and verification after copying files from Linux.

## 9. Performance

Optimize for simplicity first. The lookup-table approach should be substantially cheaper than MD5 on a V20, but actual speed depends on Open Watcom code generation, storage, and UART/disk transfer rates. Record measured throughput in KiB/s on Phaistos rather than promising a particular speedup.

Potential follow-up optimizations, only if measurements justify them:

- Tune read buffer size.
- Profile C runtime I/O versus direct DOS reads.
- Consider a carefully tested 8086/V20 assembly CRC loop.

## 10. Acceptance criteria

1. `CRCSUM FILE` emits the expected standard CRC-32 value in a stable manifest format.
2. `CRCSUM *.EXE > CRC32.SUM` works under DOS without shell glob expansion.
3. `CRCSUM -C CRC32.SUM` verifies all entries and reports each result.
4. A mismatch, missing file, malformed manifest, and unmatched wildcard yield documented nonzero `ERRORLEVEL`s.
5. CRC calculations are byte-exact for binary files, including embedded `0x1A`.
6. LF and CRLF manifests are supported.
7. The executable runs on an 8088-class DOS machine without protected-mode requirements.
8. Linux-hosted tests and DOS emulator integration tests pass.
9. A real-hardware smoke test succeeds on Phaistos.

## 11. Possible future enhancements

- An optional Linux-native CRCSUM build using the same manifest format, for seamless cross-platform generation and checking.
- Recursive directory traversal with relative paths.
- Additional checksum algorithms only if there is a demonstrated need.
- Optional quiet/status modes compatible with familiar GNU checksum conventions.

The initial release should remain a small, focused tool: **calculate CRC32 quickly, and check what was copied.**
