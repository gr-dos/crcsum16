# Build crcsum.exe for 16-bit MS-DOS with Open Watcom.
#   make WATCOM=~/opt/watcom
#   make test        host unit tests, then DOS tests under DOSBox-X

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

clean:
	rm -rf *.o *.obj *.err crcsum.exe build

.PHONY: unit dostest test clean
