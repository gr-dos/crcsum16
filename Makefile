# Build crcsum.exe for 16-bit MS-DOS with Open Watcom and libc16.
#   make             fetch the pinned libc16 release into build/libc16,
#                    then build crcsum.exe
#   make LIBC16_ROOT=../libc16
#                    use a libc16 checkout built with its make
#   make test        host unit tests, then DOS tests under DOSBox-X
#
# crcsum.exe is compiled and linked against libc16 only (its ABI is in
# libc16's docs/ABI.md), with the Open Watcom toolchain libc16 was built
# with: the libc16 tree's tools/fetch-watcom fetches it into build/tools.
#
# Optionally, build crcsum.com from 8086 assembly (see docs/ASM.md).
#   make asm
#   make test-asm    DOS tests on crcsum.com, then compare it with crcsum.exe

LIBC16_ROOT ?= build/libc16
# A release tree, or a checkout, whose make stages the same layout in
# build/stage.
LIBC16_DIR  := $(if $(wildcard $(LIBC16_ROOT)/build/stage/VERSION),$(LIBC16_ROOT)/build/stage,$(LIBC16_ROOT))
LIBC16      := $(LIBC16_DIR)/lib/LIBC16.LIB
TOOLS_ENV   := build/tools.env
WATCOM_ENV   = . ./$(TOOLS_ENV) && PATH=$$WATCOM/binl64:$$PATH

VERSION := $(shell cat VERSION)

CC     = wcc
CFLAGS = -q -zq -zl -zld -x -ms -0 -os -s -bt=dos -wx -we \
         -I$(LIBC16_DIR)/include '-DVERSION="$(VERSION)"'

HOSTCC     ?= cc
HOSTCFLAGS ?= -std=c89 -pedantic -Wall -Wextra -Werror -O2

SRCS = src/main.c src/crc32.c src/manifest.c src/dosglob.c
HDRS = src/crc32.h src/manifest.h src/dosglob.h

OBJS = $(patsubst src/%.c,build/dos/%.obj,$(SRCS))

UNIT = build/test_crc32 build/test_manifest

crcsum.exe: $(OBJS) $(LIBC16) $(TOOLS_ENV)
	$(WATCOM_ENV) && wlink option quiet, nodefaultlibs, map=build/crcsum.map \
	  format dos name $@ $(foreach o,$(OBJS),file $(o)) library $(LIBC16)

build/dos/%.obj: src/%.c $(HDRS) VERSION $(LIBC16) $(TOOLS_ENV)
	@mkdir -p build/dos
	$(WATCOM_ENV) && $(CC) $(CFLAGS) -fo=$@ $<

# The pinned libc16 release (scripts/fetch-libc16). A LIBC16_ROOT given
# on the command line must already be built.
ifeq ($(LIBC16_ROOT),build/libc16)
$(LIBC16): scripts/fetch-libc16
	scripts/fetch-libc16 $(LIBC16_ROOT)
endif

# The Open Watcom snapshot libc16 names, as shell assignments.
$(TOOLS_ENV): $(LIBC16)
	mkdir -p build
	watcom=$$(sh $(LIBC16_DIR)/tools/fetch-watcom $(CURDIR)/build/tools) \
	  && printf 'WATCOM=%s\nexport WATCOM\n' "$$watcom" > $@

build/test_crc32: tests/test_crc32.c tests/unit.h src/crc32.c src/crc32.h
	@mkdir -p build
	$(HOSTCC) $(HOSTCFLAGS) -Isrc -o $@ tests/test_crc32.c src/crc32.c

build/test_manifest: tests/test_manifest.c tests/unit.h src/manifest.c src/manifest.h
	@mkdir -p build
	$(HOSTCC) $(HOSTCFLAGS) -Isrc -o $@ tests/test_manifest.c src/manifest.c

unit: $(UNIT)
	@for t in $(UNIT); do echo "$$t"; ./$$t || exit 1; done

dostest: crcsum.exe
	sh tests/run.sh $(CURDIR)/crcsum.exe

test: unit dostest

# 8086 assembly, as a .COM
NASM ?= nasm

asm: crcsum.com

crcsum.com: src/crcsum.asm VERSION
	$(NASM) -f bin -Werror '-DVERSION="$(VERSION)"' -o $@ src/crcsum.asm

build/probe.com: tests/probe.asm
	@mkdir -p build
	$(NASM) -f bin -Werror -o $@ tests/probe.asm

build/fakeerr.com: tests/fakeerr.asm
	@mkdir -p build
	$(NASM) -f bin -Werror -o $@ tests/fakeerr.asm

test-asm: crcsum.com crcsum.exe build/probe.com build/fakeerr.com
	sh tests/run.sh $(CURDIR)/crcsum.com
	sh tests/compare.sh crcsum.exe crcsum.com build/probe.com build/fakeerr.com

# Keeps the fetched libc16 and Open Watcom (build/libc16, build/tools).
clean:
	rm -rf *.o *.obj *.err crcsum.exe crcsum.com \
	  $(filter-out build/libc16 build/libc16.zip build/tools,$(wildcard build/*))

.PHONY: unit dostest test asm test-asm clean
