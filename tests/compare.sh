#!/bin/sh
#
# Compare two builds of crcsum under DOSBox-X: the same commands are
# run with each, in identical fixture trees, and their standard output,
# standard error and exit status must be the same, byte for byte.  The
# first build is the reference (crcsum.exe from Open Watcom); the
# second is the one under test (crcsum.com from the assembly).  Both
# are then run again with DOS reporting version 2.11.
#
# tests/probe.com (built from tests/probe.asm) runs each command, since
# DOS cannot redirect standard error.  It also records how much memory
# the program had when it exited; that is reported, not compared.
#
# This covers what tests/run.sh does not: standard error, argument
# quoting, option order, buffer and line-length boundaries, manifest
# line endings and malformed lines, 32-bit counters, devices, DOS
# errors, and write errors on a full disk.
#
# Each line of the step list is a step: the arguments for crcsum, run
# with its output, standard error and status recorded.  A line starting
# with "=" is run without the probe, so that its arguments can be
# longer; only its output and status are recorded.  A line starting
# with "!" is a DOS command run as it is, in which %1 is the name of
# the build (its output directory is c:\o\%1) and %2 its extension.
#
# Usage: tests/compare.sh REFERENCE TEST PROBE
# Environment: DOSBOX (default dosbox-x), PYTHON (default python3),
#              KEEP=1 to keep the work directory.

set -u

DOSBOX=${DOSBOX:-dosbox-x}
PYTHON=${PYTHON:-python3}

[ $# -eq 3 ] || { echo "usage: $0 reference test probe" >&2; exit 2; }
command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
command -v "$PYTHON" >/dev/null || { echo "$PYTHON not found" >&2; exit 2; }
for f in "$@"; do
    [ -f "$f" ] || { echo "$f not found" >&2; exit 2; }
done

ext() { echo "${1##*.}" | tr 'A-Z' 'a-z'; }
rext=$(ext "$1")
text=$(ext "$2")

work=$(mktemp -d "${TMPDIR:-/tmp}/doscmp.XXXXXX")
cp "$1" "$work/r.$rext"
cp "$1" "$work/r2.$rext"
cp "$2" "$work/t.$text"
cp "$2" "$work/t2.$text"
cp "$3" "$work/p.com"
cd "$work" || exit 2
LC_ALL=C
export LC_ALL

# ------------------------------------------------------------------
# fixtures: one tree per run, made the same way each time so that DOS
# lists their directories in the same order

# crc FILE: the file's CRC-32 as eight lower case hex digits
crc() {
    "$PYTHON" -I -c 'import sys, zlib
print("%08x" % zlib.crc32(open(sys.argv[1], "rb").read()))' "$1"
}

# bytes N FILE: N bytes of a fixed pseudo-random sequence
bytes() {
    "$PYTHON" -I -c 'import sys, random
r = random.Random(16)
sys.stdout.buffer.write(bytes(r.getrandbits(8) for _ in range(int(sys.argv[1]))))' "$1" > "$2"
}

fixtures() {
    printf 'hello\n' > a.txt
    : > empty.dat
    bytes 3000 b.bin
    bytes 100001 big.bin
    bytes 1048577 huge.bin
    printf 'one\r\n\032two\000\200\377\032\r\nend' > ctrlz.bin
    printf '123456789' > check.txt
    printf 'a' > va.txt
    printf 'abc' > vabc.txt
    printf 'The quick brown fox jumps over the lazy dog' > vfox.txt
    "$PYTHON" -I -c 'import sys; sys.stdout.buffer.write(bytes(range(256)))' > v256.bin
    head -c 4096 /dev/zero > zeros.bin
    head -c 4096 /dev/zero | tr '\000' '\377' > ff.bin
    # around the 16 KB read size and 64 KB
    for n in 16383 16384 16385 32768 65535 65536 65537; do
        bytes $n "s$n.bin"
    done
    printf 'dash\n' > -x.txt

    mkdir wild wild/dir.c q sub sub/deep many e
    echo one > wild/one.c
    echo two > wild/two.c
    echo hdr > wild/x.h
    echo 1 > q/1.txt
    echo 2 > q/2.txt
    echo 12 > q/12.txt
    echo deep > sub/deep/f.txt
    # 40 lines of output: more than one 512-byte stdout buffer
    i=1
    while [ $i -le 40 ]; do
        echo "$i" > "many/$(printf 'f%02d.txt' $i)"
        i=$((i + 1))
    done
    # 32 lines of 16 bytes: exactly one stdout buffer
    i=10
    while [ $i -le 41 ]; do
        echo "$i" > "e/$i"
        i=$((i + 1))
    done

    sumline() { printf '%s %s%s\n' "$(crc "$1")" "${2:-*}" "$1"; }
    FILES='a.txt empty.dat b.bin big.bin ctrlz.bin'
    for f in $FILES; do sumline "$f"; done > good.sum
    sed 's/$/\r/' good.sum > crlf.sum
    tr '\n' '\r' < good.sum > cr.sum
    {
        echo '# made on Linux'
        printf '%s  a.txt\n' "$(crc a.txt | tr 'a-f' 'A-F')"
        echo
        printf '%s' "$(sumline b.bin ' ')"
    } > text.sum
    echo "$(crc a.txt | tr '0-9a-f' 'f0-9a-e') *a.txt" > bad1.sum
    { cat good.sum; echo "d41d8cd9 *nothere.txt"; } > miss.sum
    { cat good.sum; echo 'this is not a checksum line'; } > malf.sum
    { cat bad1.sum; echo 'cbf43926 *'; } > malfbad.sum
    printf '# nothing here\n\n' > none.sum
    { sumline a.txt; sumline a.txt; } > dup.sum
    { cat good.sum; printf '\032garbage after Ctrl-Z\n'; } > ctrlz.sum
    for f in s16383.bin s16384.bin s16385.bin s32768.bin s65535.bin \
             s65536.bin s65537.bin huge.bin va.txt vabc.txt vfox.txt \
             v256.bin zeros.bin ff.bin check.txt; do
        sumline "$f"
    done > sizes.sum

    # line length: 254 characters is the longest line; 255 is too long
    pad() { printf "%s *%-$(($1 - 10))s\n" "$(crc a.txt)" a.txt; }
    { pad 254; pad 255; pad 256; pad 600; sumline a.txt; } > long.sum
    # a long line across the 512-byte read buffer, then a good line
    { printf '%0700d\n' 0; sumline a.txt; } > long2.sum
    # line endings: LF CR, CR CR, a CR LF split across the read buffer,
    # a CR at the end of the buffer before a non-LF, and a final CR
    {
        printf '%s\n\r' "$(sumline a.txt)"
        printf '%s\r\r' "$(sumline b.bin)"
    } > ends.sum
    "$PYTHON" -I - "$(sumline a.txt)" <<'EOF'
import sys
line = sys.argv[1].encode()
pad = b"#" * (511 - len(line) - 1) + b"\n"
open("split1.sum", "wb").write(pad + line + b"\r\n" + line + b"\r")
pad = b"#" * (512 - len(line) - 1) + b"\n"
open("split2.sum", "wb").write(pad + line + b"\r" + line + b"\n")
EOF
    # malformed lines
    {
        sumline a.txt
        printf 'zzzzzzzz *a.txt\n'
        printf '%s *a.txt\n' "$(crc a.txt | cut -c1-7)"
        printf '%s*a.txt\n' "$(crc a.txt)"
        printf '%s -a.txt\n' "$(crc a.txt)"
        printf '%s *\n' "$(crc a.txt)"
        printf '%s  \n' "$(crc a.txt)"
        printf '%s\n' "$(crc a.txt)"
        printf ' %s *a.txt\n' "$(crc a.txt)"
        printf '%s *a.txt\000x\n' "$(crc a.txt)"
        printf '0x%s *a.txt\n' "$(crc a.txt | cut -c1-6)"
        printf '%s *a.tx\032t\n' "$(crc a.txt)"
    } > formats.sum
    # names: leading spaces (skipped when opening), wildcards (not
    # expanded), a directory, a missing directory, a device
    {
        printf '%s * a.txt\n' "$(crc a.txt)"
        printf '%s *  a.txt\n' "$(crc a.txt)"
        printf '%s *a.tx?\n' "$(crc a.txt)"
        printf '00000000 *wild\n'
        printf '00000000 *nodir\\a.txt\n'
        printf '00000000 *nul\n'
        printf '%s *sub/deep/f.txt\n' "$(crc sub/deep/f.txt)"
        printf '%s *.\\sub\\deep\\f.txt\n' "$(crc sub/deep/f.txt)"
    } > names.sum
    # 70000 comment lines, then a bad line: line numbers past 65535
    { "$PYTHON" -I -c 'print("#\n" * 69999, end="")'; echo bad; } > lineno.sum
    # 65537 bad lines and one good one: counts past 65535
    { "$PYTHON" -I -c 'print("x\n" * 65537, end="")'; sumline a.txt; } > count.sum
    # one bad, one unreadable, one mismatch: singular warnings
    {
        echo bad
        echo '00000000 *nothere'
        echo "$(crc a.txt | tr '0-9a-f' 'f0-9a-e') *a.txt"
    } > one.sum
    # two of each: plural warnings
    { cat one.sum; cat one.sum; } > two.sum
}

for d in r t r2 t2; do
    mkdir "$d" && (cd "$d" && fixtures) || exit 2
done
mkdir o o/r o/t o/r2 o/t2

# Floppy images for write errors, one pair per run.  full.img (A:) has
# no free space.  pre.img (B:) holds PRE.TXT, 100 bytes, and has one
# free 512-byte cluster, so that appending to PRE.TXT gives short
# writes.
"$PYTHON" -I - <<'EOF'
import struct

def image(path, files, free):
    # 160 KB, FAT12: 1 reserved sector, 2 FATs of 1 sector, 64 root
    # entries (4 sectors), 313 clusters of 1 sector
    sec = bytearray(512)
    sec[0:3] = b"\xeb\x3c\x90"
    sec[3:11] = b"CRCSUM  "
    struct.pack_into("<HBHBHHBHHHI", sec, 11,
                     512, 1, 1, 2, 64, 320, 0xfe, 1, 8, 1, 0)
    sec[510:512] = b"\x55\xaa"
    nclusters = 313
    fat = [0xffe, 0xfff] + [0] * nclusters
    root = bytearray(64 * 32)
    data = bytearray(nclusters * 512)
    used = sum((len(b) + 511) // 512 for _, b in files)
    fill = nclusters - free - used
    files = files + [("FILL    BIN", b"\0" * (fill * 512))]
    cluster = 2
    for i, (name, body) in enumerate(files):
        n = (len(body) + 511) // 512
        struct.pack_into("<11sB10sHHHI", root, i * 32, name.encode(),
                         0x20, b"", 0, 0x21, cluster, len(body))
        for k in range(n):
            fat[cluster + k] = cluster + k + 1 if k < n - 1 else 0xfff
        start = (cluster - 2) * 512
        data[start:start + len(body)] = body
        cluster += n
    packed = bytearray(512)
    for i in range(0, len(fat), 2):
        a = fat[i]
        b = fat[i + 1] if i + 1 < len(fat) else 0
        packed[i * 3 // 2:i * 3 // 2 + 3] = bytes(
            (a & 0xff, (a >> 8) | ((b & 0xf) << 4), b >> 4))
    out = sec + packed + packed + root + data
    assert len(out) == 320 * 512
    open(path, "wb").write(out)

for run in ("r", "t", "r2", "t2"):
    image(run + "full.img", [], 0)
    image(run + "pre.img", [("PRE     TXT", b"x" * 99 + b"\n")], 1)
EOF

steps() {
    tab=$(printf '\t')
    long=$(printf 'f%.0s' $(seq 1 116))
    max=$(printf 'g%.0s' $(seq 1 124))
    cat <<EOS
a.txt empty.dat b.bin big.bin ctrlz.bin check.txt
huge.bin
s16383.bin s16384.bin s16385.bin s32768.bin
s65535.bin s65536.bin s65537.bin
va.txt vabc.txt vfox.txt v256.bin zeros.bin ff.bin
wild\\*.c
wild/*.c
wild\\*.*
q\\?.txt
q\\*
.\\q\\?.TXT
c:q\\?.txt
c:\\*.bat
sub\\*
sub\\deep\\*.*
*.zz
nodir\\*.c
q:\\*.c
a.txt *.zz b.bin
many\\*.txt
e\\*
nothere.txt
a.txt nothere.txt b.bin
wild
nodir\\a.txt
q:a.txt
nul
NUL
"a.txt"
"a.txt" b.bin
"a.txt b.bin"
a\\"b
a\\\\"b c"
\\"a.txt
""
" a.txt"
"  a.txt"
"a.txt "
a"."txt
"a.txt
a.txt${tab}b.bin
${tab}a.txt
-c good.sum
-C crlf.sum
--check cr.sum
--CHECK text.sum
--Check dup.sum
-c ctrlz.sum
-c sizes.sum
-c bad1.sum
-c miss.sum
-c malf.sum
-c malfbad.sum
-c none.sum
-c nothere.sum
-c good.sum bad1.sum
-c long.sum
-c long2.sum
-c ends.sum
-c split1.sum
-c split2.sum
-c formats.sum
-c names.sum
-c lineno.sum
-c count.sum
-c one.sum
-c two.sum
-c wild
-c nul
-c q:x.sum
-c good.sum nothere.sum dup.sum
-c "good.sum"
-cC good.sum
-ch good.sum
-hc
-c-
-c --help
--help -x
-x --help
--help --bogus
--version --help
--chec good.sum
--check=x good.sum
---
-- --help
-- -x.txt
-- -
-c -- good.sum
-c --
-c
--

-
-c -
-x a.txt
--bogus a.txt
-?
-H
-h
--help
--HELP
--version
--VERSION
-\\
-c a.txt -- -c
=-c ${long}
=-c "${long}"
=${long}
=${max}
=\\"${long}
!c:\\p c:\\o\\%1\\full1.e c:\\o\\%1\\full1.m c:\\%1.%2 a.txt b.bin >a:\\full1.txt
!call c:\\rc c:\\o\\%1\\full1.r
!c:\\p c:\\o\\%1\\full2.e c:\\o\\%1\\full2.m c:\\%1.%2 e\\* >a:\\full2.txt
!call c:\\rc c:\\o\\%1\\full2.r
!c:\\p c:\\o\\%1\\full3.e c:\\o\\%1\\full3.m c:\\%1.%2 many\\*.txt nothere.txt >a:\\full3.txt
!call c:\\rc c:\\o\\%1\\full3.r
!c:\\p c:\\o\\%1\\full4.e c:\\o\\%1\\full4.m c:\\%1.%2 -c good.sum >a:\\full4.txt
!call c:\\rc c:\\o\\%1\\full4.r
!c:\\p c:\\o\\%1\\full5.e c:\\o\\%1\\full5.m c:\\%1.%2 --help >a:\\full5.txt
!call c:\\rc c:\\o\\%1\\full5.r
!c:\\p c:\\o\\%1\\pre1.e c:\\o\\%1\\pre1.m c:\\%1.%2 many\\*.txt >>b:\\pre.txt
!call c:\\rc c:\\o\\%1\\pre1.r
!copy b:\\pre.txt c:\\o\\%1\\pre1.o >nul
!c:\\p c:\\o\\%1\\self.e c:\\o\\%1\\self.m c:\\%1.%2 many\\*.txt >many\\self.txt
!call c:\\rc c:\\o\\%1\\self.r
!copy many\\self.txt c:\\o\\%1\\self.o >nul
EOS
}

# ------------------------------------------------------------------
# the batch files: steps.bat NAME EXT runs every step with NAME.EXT in
# the tree c:\NAME.  The redirection comes before the arguments, so
# that an unbalanced quote in them does not take it in.

cat > rc.bat <<'EOS'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >%1
goto end
:rc1
echo rc1 >%1
goto end
:rc2
echo rc2 >%1
:end
EOS

steps > steps.txt
n=0
{
    printf '@echo off\r\n'
    printf 'cd \\%%1\r\n'
    while IFS= read -r line; do
        case $line in
        !*) printf '%s\r\n' "${line#!}" ;;
        =*)
            n=$((n + 1))
            printf 'c:\\%%1.%%2 >c:\\o\\%%1\\%d.o %s\r\n' $n "${line#=}"
            printf 'call c:\\rc c:\\o\\%%1\\%d.r\r\n' $n
            ;;
        *)
            n=$((n + 1))
            printf 'c:\\p c:\\o\\%%1\\%d.e c:\\o\\%%1\\%d.m >c:\\o\\%%1\\%d.o c:\\%%1.%%2 %s\r\n' \
                $n $n $n "$line"
            printf 'call c:\\rc c:\\o\\%%1\\%d.r\r\n' $n
            ;;
        esac
    done < steps.txt
    printf 'cd \\\r\n'
} > steps.bat

cat > run.bat <<EOS
@echo off
imgmount a rfull.img -t floppy >nul
imgmount b rpre.img -t floppy >nul
call steps r $rext
imgmount -u a >nul
imgmount -u b >nul
imgmount a tfull.img -t floppy >nul
imgmount b tpre.img -t floppy >nul
call steps t $text
imgmount -u a >nul
imgmount -u b >nul
ver set 2 11
imgmount a r2full.img -t floppy >nul
imgmount b r2pre.img -t floppy >nul
call steps r2 $rext
imgmount -u a >nul
imgmount -u b >nul
imgmount a t2full.img -t floppy >nul
imgmount b t2pre.img -t floppy >nul
call steps t2 $text
EOS
sed -i 's/$/\r/' run.bat

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 1200 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "c:" \
    -c "run.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks: every output, error and status file of the reference must
# exist for the test build and be the same.  Memory (.m) is reported.

pass=0
fail=0
# name: a step number's arguments, or the file's own name
label() {
    case $1 in
    [0-9]*) sed -n "$(grep -vn '^!' steps.txt | sed -n "${1}p" | cut -d: -f1)p" steps.txt ;;
    *) echo "$1" ;;
    esac
}
for pair in "r t" "r2 t2"; do
    set -- $pair
    if [ -z "$(ls "o/$1")" ]; then
        echo "FAIL: $1: no output"
        fail=$((fail + 1))
        continue
    fi
    for f in $(ls "o/$1" | grep -iv '\.m$'); do
        t=$(ls "o/$2" | grep -ix "$f")
        base=${f%.*}
        if [ -z "$t" ]; then
            echo "FAIL: $2 $f ($(label "$base")): missing"
            fail=$((fail + 1))
        elif cmp -s "o/$1/$f" "o/$2/$t"; then
            pass=$((pass + 1))
        else
            echo "FAIL: $2 $f ($(label "$base")): differs (< $1, > $2)"
            diff "o/$1/$f" "o/$2/$t" | sed 's/^/    /' | head -20
            fail=$((fail + 1))
        fi
    done
done

# memory at exit, for the first step and the largest
for run in r t; do
    first=$(tr -d '\r' < "o/$run/1.M" 2>/dev/null)
    most=$(cat o/$run/*.M 2>/dev/null | tr -d '\r' | sort -n | tail -1)
    echo "memory at exit, $run: ${first:-?} bytes for step 1, ${most:-?} at most"
done

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
