# crcsum16

A small, fast CRC-32 checksum utility for 16-bit MS-DOS, built with Open
Watcom. It works like `md5sum`: print checksums for files, save them to
a manifest, and check the manifest later, for example after copying
files to an XT.

The resulting `crcsum.exe` is a small-model, real-mode 8086 executable
(about 17 KB) that runs on any DOS from an original PC up.

CRC-32 detects accidental corruption. It is **not** cryptographically
secure and must not be used to authenticate untrusted files.

## Building

Requires Open Watcom (tested with the Linux-hosted toolchain).

    make                         # uses ~/opt/watcom by default
    make WATCOM=/path/to/watcom  # or point it elsewhere
    make test                    # host unit tests, then DOS tests
    make unit                    # host unit tests only
    make dostest                 # tests/run.sh under DOSBox-X only
    make clean

The unit tests need a host C compiler (`HOSTCC`, default `cc`). The DOS
tests need `dosbox-x` and `python3` on the host (override with `DOSBOX=`
and `PYTHON=`); set `KEEP=1` to keep the work directory.

`make asm` builds `crcsum.com`, an experimental 8086 assembly version of
the same program (needs `nasm`): 3.5 KB instead of 17 KB. `make
test-asm` runs the DOS tests on it and compares it with `crcsum.exe`.
It is not part of releases; see [docs/ASM.md](docs/ASM.md).

The version is the one line in `VERSION`, DOS style (0.01, 0.02, ...
1.00), not semantic versioning. When a PR that changes it is merged to
`main`, the release workflow tags the merge commit `v<VERSION>` and
publishes a GitHub release with `crcsum.exe` attached.

## Usage

    crcsum FILE...
    crcsum -c MANIFEST...

DOS does not expand wildcards, so `crcsum` does it itself: `crcsum *.exe`
works. Options are case-insensitive.

| Option | Meaning |
| --- | --- |
| `-c`, `-C`, `--check` | read checksums from the MANIFESTs and verify them |
| `-h`, `-?`, `--help` | show help |
| `--version` | show version |
| `--` | treat the remaining arguments as files |

### Examples

    C:\> crcsum *.exe > crc32.sum
    C:\> type crc32.sum
    3d8e1f0a *BCOM.EXE
    9c6b2e47 *TICO.EXE
    C:\> crcsum -c crc32.sum
    BCOM.EXE: OK
    TICO.EXE: OK

(The checksums above are illustrative.)

### Output

Each file gives one line: eight lower case hex digits, a space, `*`, and
the file name. Names given in full are printed as typed; names found by
wildcard expansion are printed as DOS returns them (upper case), after
the pattern's directory part. Lines end in CR LF.

### Manifests

`crcsum -c` reads lines of the form

    <8 hex digits><space><* or space><file name>

Files are opened relative to the current directory. Manifests may use
CR LF, LF or CR line endings, and the last line need not be terminated.
Hex digits may be either case. Blank lines and lines starting with `#`
are skipped, and a Ctrl-Z ends the manifest. A file listed more than
once is checked each time.

Each entry prints `OK`, `FAILED` (wrong checksum) or `FAILED open or
read`. Malformed lines and a summary of failures go to standard error;
the remaining entries are still checked.

### ERRORLEVEL

| ERRORLEVEL | Meaning |
| --- | --- |
| 0 | every file was read and, when checking, every checksum matched |
| 1 | a file was missing, unreadable or did not match, or a wildcard matched nothing |
| 2 | usage error, unreadable manifest, manifest with malformed lines or no entries, or a write error on standard output |

A run with both mismatches and malformed manifest lines exits with 2.

## The CRC

CRC-32/ISO-HDLC, the CRC used by ZIP, gzip and Ethernet: reflected
polynomial `0xEDB88320`, initial value and final XOR `0xFFFFFFFF`. The
check value of `123456789` is `cbf43926`. Only the file's bytes are
hashed, read in binary mode, so Ctrl-Z and CR LF are hashed as they are.

The values match Python's `zlib.crc32` and the CRCs stored in ZIP
files. The plain `cksum` command uses a different CRC.

On Linux, a manifest can be made with:

    python3 -c 'import sys, zlib
    for f in sys.argv[1:]:
        print("%08x *%s" % (zlib.crc32(open(f, "rb").read()), f))' *.exe > crc32.sum

## Limits

- Files are read in 16 KB chunks; file size is limited only by DOS.
- Manifest lines may be up to 255 characters; longer lines are treated
  as malformed.
- Standard input is not supported.
- No recursion into directories; names are DOS 8.3.

## Files

- `src/crc32.c`, `src/crc32.h`: table-driven CRC-32
- `src/manifest.c`, `src/manifest.h`: manifest line reading and parsing
- `src/dosglob.c`, `src/dosglob.h`: DOS wildcard expansion
- `src/main.c`: the command-line program
- `tests/test_*.c`: host unit tests
- `tests/run.sh`: DOS tests, run under DOSBox-X
- `docs/DESIGN.md`: the design
- `src/crcsum.asm`, `tests/compare.sh`, `tests/probe.asm`,
  `docs/ASM.md`, `docs/ASM-PROVENANCE.md`: the assembly experiment
- `Makefile`: Open Watcom build
- `VERSION`: the version, compiled in and printed by `--version`

## License

MIT. See `LICENSE`.
