# Build crcsum.exe for 16-bit MS-DOS with Open Watcom.
#   make WATCOM=~/opt/watcom
#   make test        host unit tests, then DOS tests under DOSBox-X
#
# Optionally, build crcsum.com from 8086 assembly (see docs/ASM.md).
#   make asm
#   make test-asm    DOS tests on crcsum.com, then compare it with crcsum.exe

WATCOM ?= $(HOME)/opt/watcom
export WATCOM
export INCLUDE := $(WATCOM)/h
export PATH := $(WATCOM)/binl64:$(WATCOM)/binl:$(PATH)

VERSION := $(shell cat VERSION)

CC     = wcl
CFLAGS = -q -bt=dos -ms -0 -os -s -wx -we -zq '-DVERSION="$(VERSION)"'

HOSTCC     ?= cc
HOSTCFLAGS ?= -std=c89 -pedantic -Wall -Wextra -Werror -O2

SRCS = src/main.c src/crc32.c src/manifest.c src/dosglob.c
HDRS = src/crc32.h src/manifest.h src/dosglob.h

UNIT = build/test_crc32 build/test_manifest

crcsum.exe: $(SRCS) $(HDRS) VERSION
	$(CC) $(CFLAGS) -fe=$@ $(SRCS)

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

test-asm: crcsum.com crcsum.exe build/probe.com
	sh tests/run.sh $(CURDIR)/crcsum.com
	sh tests/compare.sh crcsum.exe crcsum.com build/probe.com

clean:
	rm -rf *.o *.obj *.err crcsum.exe crcsum.com build

.PHONY: unit dostest test asm test-asm clean
