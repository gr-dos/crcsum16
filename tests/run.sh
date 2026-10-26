#!/bin/sh
#
# Test crcsum.exe (or crcsum.com, the assembly version) under DOSBox-X.
#
# Fixtures and expected checksums are made on the host with Python's
# zlib.crc32, one batch file runs every DOS-side step, and the results
# are checked on the host afterwards.  Each step N records crcsum's exit
# status in RN.TXT and its standard output in ON.TXT.  DOS cannot
# redirect standard error, so diagnostics are not checked.  rc.bat uses
# goto rather than "if errorlevel N echo ... >file" because the DOSBox-X
# shell opens the redirection even when the test is false.
#
# Usage: tests/run.sh [path/to/crcsum.exe or crcsum.com]
# Environment: DOSBOX (default dosbox-x), PYTHON (default python3),
#              KEEP=1 to keep the work directory.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
exe=${1:-$top/crcsum.exe}
DOSBOX=${DOSBOX:-dosbox-x}
PYTHON=${PYTHON:-python3}

command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
command -v "$PYTHON" >/dev/null || { echo "$PYTHON not found" >&2; exit 2; }
[ -f "$exe" ] || { echo "$exe not found" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/doscrc.XXXXXX")
pass=0
fail=0
LC_ALL=C
export LC_ALL

# crc FILE: the file's CRC-32 as eight lower case hex digits
crc() {
    "$PYTHON" -I -c 'import sys, zlib
print("%08x" % zlib.crc32(open(sys.argv[1], "rb").read()))' "$1"
}

# ------------------------------------------------------------------
# fixtures

cd "$work" || exit 2
cp "$exe" "crcsum.$(echo "${exe##*.}" | tr 'A-Z' 'a-z')"

printf 'hello\n' > a.txt
: > empty.dat
head -c 3000 /dev/urandom > b.bin
# bigger than 64 KB and not a multiple of the 16 KB read size
head -c 100001 /dev/urandom > big.bin
# Ctrl-Z, CR LF and high bytes must all be hashed as they are
printf 'one\r\n\032two\000\200\377\032\r\nend' > ctrlz.bin
printf '123456789' > check.txt
printf 'dash\n' > -x.txt

mkdir wild wild/dir.c q
echo one > wild/one.c
echo two > wild/two.c
echo hdr > wild/x.h
echo 1 > q/1.txt
echo 2 > q/2.txt
echo 12 > q/12.txt

# sumline FILE [MARKER]: a manifest line for FILE
sumline() { printf '%s %s%s\n' "$(crc "$1")" "${2:-*}" "$1"; }

FILES='a.txt empty.dat b.bin big.bin ctrlz.bin'
for f in $FILES; do sumline "$f"; done > good.sum
sed 's/$/\r/' good.sum > crlf.sum
tr '\n' '\r' < good.sum > cr.sum
# GNU text marker, upper case hex, comments, blank line, no final newline
{
    echo '# made on Linux'
    printf '%s  a.txt\n' "$(crc a.txt | tr 'a-f' 'A-F')"
    echo
    printf '%s' "$(sumline b.bin ' ')"
} > text.sum
# a.txt with a wrong checksum
echo "$(crc a.txt | tr '0-9a-f' 'f0-9a-e') *a.txt" > bad1.sum
{ cat good.sum; echo "d41d8cd9 *nothere.txt"; } > miss.sum
{ cat good.sum; echo 'this is not a checksum line'; } > malf.sum
{ cat bad1.sum; echo 'cbf43926 *'; } > malfbad.sum
{ cat good.sum; printf '%0300d *a.txt\n' 0; } > long.sum
printf '# nothing here\n\n' > none.sum
{ sumline a.txt; sumline a.txt; } > dup.sum
{ cat good.sum; printf '\032garbage after Ctrl-Z\n'; } > ctrlz.sum
(cd wild && sumline one.c) > wild.sum

cat > rc.bat <<'EOF'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >c:\r%1.txt
goto end
:rc1
echo rc1 >c:\r%1.txt
goto end
:rc2
echo rc2 >c:\r%1.txt
:end
EOF

cat > steps.bat <<'EOF'
@echo off
rem --- sum files
crcsum a.txt empty.dat b.bin big.bin ctrlz.bin check.txt >o1.txt
call rc 1
rem --- wildcards
crcsum wild\*.c >o2.txt
call rc 2
crcsum q\?.txt >o3.txt
call rc 3
crcsum *.zz >o4.txt
call rc 4
crcsum a.txt *.zz b.bin >o5.txt
call rc 5
rem --- missing files
crcsum nothere.txt >o6.txt
call rc 6
crcsum a.txt nothere.txt b.bin >o7.txt
call rc 7
rem --- check
crcsum -c good.sum >o8.txt
call rc 8
crcsum -C crlf.sum >o9.txt
call rc 9
crcsum --check cr.sum >o10.txt
call rc 10
crcsum -c text.sum >o11.txt
call rc 11
crcsum -c dup.sum >o12.txt
call rc 12
crcsum -c ctrlz.sum >o13.txt
call rc 13
crcsum -c bad1.sum >o14.txt
call rc 14
crcsum -c miss.sum >o15.txt
call rc 15
crcsum -c malf.sum >o16.txt
call rc 16
crcsum -c malfbad.sum >o17.txt
call rc 17
crcsum -c long.sum >o18.txt
call rc 18
crcsum -c none.sum >o19.txt
call rc 19
crcsum -c nothere.sum >o20.txt
call rc 20
crcsum -c good.sum bad1.sum >o21.txt
call rc 21
cd wild
..\crcsum -c ..\wild.sum >..\o22.txt
call ..\rc 22
cd ..
rem --- round trip a manifest made on DOS
crcsum a.txt b.bin big.bin ctrlz.bin >dos.sum
crcsum -c dos.sum >o23.txt
call rc 23
rem --- options
crcsum -- -x.txt >o24.txt
call rc 24
crcsum >o25.txt
call rc 25
crcsum -c >o26.txt
call rc 26
crcsum --bogus a.txt >o27.txt
call rc 27
crcsum -x a.txt >o28.txt
call rc 28
crcsum - >o29.txt
call rc 29
rem --- help and version
crcsum --help >o30.txt
call rc 30
crcsum -? >o31.txt
call rc 31
crcsum -H >o32.txt
call rc 32
crcsum --HELP >o33.txt
call rc 33
crcsum --version >o34.txt
call rc 34
crcsum --VERSION >o35.txt
call rc 35
EOF

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "c:" \
    -c "steps.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks

ok()     { pass=$((pass + 1)); }
not_ok() { echo "FAIL: $*"; fail=$((fail + 1)); }

# check NAME COMMAND...
check() {
    name=$1
    shift
    if "$@"; then ok; else not_ok "$name"; fi
}

# rc STEP EXPECTED-STATUS
rc() {
    got=$(tr -d ' \r' < "R$1.TXT" 2>/dev/null | sed 's/^rc//')
    if [ "$got" = "$2" ]; then
        ok
    else
        not_ok "step $1: exit status ${got:-missing}, expected $2"
    fi
}

# expect STEP < expected-lines; compares ON.TXT with CRs removed
expect() {
    tr -d '\r' < "O$1.TXT" 2>/dev/null > got.txt
    cat > want.txt
    if cmp -s got.txt want.txt; then
        ok
    else
        not_ok "step $1: output differs"
        diff want.txt got.txt | sed 's/^/    /'
    fi
}

# expect_sorted STEP < expected-lines; as expect, ignoring line order
expect_sorted() {
    tr -d '\r' < "O$1.TXT" 2>/dev/null | sort > got.txt
    sort > want.txt
    if cmp -s got.txt want.txt; then
        ok
    else
        not_ok "step $1: output differs"
        diff want.txt got.txt | sed 's/^/    /'
    fi
}

# sum files
rc 1 0
expect 1 <<EOF
$(cat good.sum)
cbf43926 *check.txt
EOF
check "step 1: lines end in CR LF" \
    sh -c "[ \$(grep -c \"\$(printf '\r')\$\" O1.TXT) -eq 6 ]"

# wildcards: names come back as DOS returns them; directories skipped
rc 2 0
expect_sorted 2 <<EOF
$(crc wild/one.c) *wild\\ONE.C
$(crc wild/two.c) *wild\\TWO.C
EOF
rc 3 0
expect_sorted 3 <<EOF
$(crc q/1.txt) *q\\1.TXT
$(crc q/2.txt) *q\\2.TXT
EOF
rc 4 1
expect 4 < /dev/null
rc 5 1
expect 5 <<EOF
$(sumline a.txt)
$(sumline b.bin)
EOF

# missing files
rc 6 1
expect 6 < /dev/null
rc 7 1
expect 7 <<EOF
$(sumline a.txt)
$(sumline b.bin)
EOF

# check
for n in 8 9 10 13; do
    rc $n 0
    expect $n <<'EOF'
a.txt: OK
empty.dat: OK
b.bin: OK
big.bin: OK
ctrlz.bin: OK
EOF
done
rc 11 0
expect 11 <<'EOF'
a.txt: OK
b.bin: OK
EOF
rc 12 0
expect 12 <<'EOF'
a.txt: OK
a.txt: OK
EOF
rc 14 1
expect 14 <<'EOF'
a.txt: FAILED
EOF
rc 15 1
expect 15 <<'EOF'
a.txt: OK
empty.dat: OK
b.bin: OK
big.bin: OK
ctrlz.bin: OK
nothere.txt: FAILED open or read
EOF
# malformed lines: the rest is still checked, but the status is 2
rc 16 2
expect 16 <<'EOF'
a.txt: OK
empty.dat: OK
b.bin: OK
big.bin: OK
ctrlz.bin: OK
EOF
rc 17 2
expect 17 <<'EOF'
a.txt: FAILED
EOF
rc 18 2
expect 18 <<'EOF'
a.txt: OK
empty.dat: OK
b.bin: OK
big.bin: OK
ctrlz.bin: OK
EOF
rc 19 2
expect 19 < /dev/null
rc 20 2
expect 20 < /dev/null
rc 21 1
expect 21 <<'EOF'
a.txt: OK
empty.dat: OK
b.bin: OK
big.bin: OK
ctrlz.bin: OK
a.txt: FAILED
EOF
rc 22 0
expect 22 <<'EOF'
one.c: OK
EOF

# round trip
rc 23 0
expect 23 <<'EOF'
a.txt: OK
b.bin: OK
big.bin: OK
ctrlz.bin: OK
EOF
cp DOS.SUM Odos.TXT 2>/dev/null
expect dos <<EOF
$(sumline a.txt)
$(sumline b.bin)
$(sumline big.bin)
$(sumline ctrlz.bin)
EOF

# options
rc 24 0
expect 24 <<EOF
$(sumline -x.txt)
EOF
for n in 25 26 27 28 29; do
    rc $n 2
    expect $n < /dev/null
done

# help and version
rc 30 0
check "step 30: help" grep -q '^Usage: crcsum' O30.TXT
for n in 31 32 33; do
    rc $n 0
    check "step $n: same as --help" cmp -s O30.TXT O$n.TXT
done
for n in 34 35; do
    rc $n 0
    expect $n <<EOF
crcsum (crcsum16) $(cat "$top/VERSION")
EOF
done

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
