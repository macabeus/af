#!/bin/sh
# Build asmlift's symbol-source ELF: build/animalforest-jp-syms.elf — a copy of the built
# ELF with the DWARF of the declarations-only sidecar TU (build/asmlift-ctx.c) merged in.
# asmlift reads names/addresses from its .symtab and declaration shapes (arrays, struct
# layouts, …) from the merged DWARF. The real build outputs are untouched.
#
# Needs a BIG-ENDIAN MIPS cross toolchain: the merged DWARF is parsed in the ELF's byte
# order, and BE also changes struct bitfield layout — hence mips-linux-gnu-gcc (any modern
# version; it only emits debug info, never code, so it needn't match the game's IDO).
# Uses the host toolchain when installed (Linux: apt install gcc-mips-linux-gnu
# binutils-mips-linux-gnu), otherwise re-runs itself in Docker.
#
# Usage: make asmlift-elf
set -eu

cd "$(dirname "$0")/.."

[ -f build/animalforest-jp.elf ] || { echo "build/animalforest-jp.elf missing — run make first" >&2; exit 1; }
[ -f build/asmlift-ctx.c ] || { echo "build/asmlift-ctx.c missing — run 'make asmlift-elf'" >&2; exit 1; }

if ! command -v mips-linux-gnu-gcc >/dev/null 2>&1 || ! command -v mips-linux-gnu-objcopy >/dev/null 2>&1; then
  exec docker run --rm --platform linux/amd64 -v "$PWD":/w -w /w debian:bookworm sh -ec '
    apt-get update -qq >/dev/null
    apt-get install -y -qq gcc-mips-linux-gnu binutils-mips-linux-gnu >/dev/null
    /w/tools/asmlift-sidecar.sh'
fi

# Flags mirror the project Makefile for VERSION=jp. -fno-eliminate-unused-debug-types makes
# GCC emit a typed DIE for EVERY declared global/struct, used or not.
mips-linux-gnu-gcc \
  -nostdinc -I include -I src -I assets/jp -I . -I build \
  -I lib/ultralib/include -I lib/ultralib/include/PR -I lib/ultralib/include/compiler/ido \
  -DVERSION_JP=1 -DLANGUAGE_C -D_LANGUAGE_C -D_MIPS_SZLONG=32 -DF3DEX_GBI_2 \
  -DNDEBUG -D_FINALROM -DBUILD_VERSION=VERSION_L \
  -DMIPSEB -D_MIPS_FPSET=16 -D_MIPS_ISA=2 -D_ABIO32=1 -D_MIPS_SIM=_ABIO32 \
  -D_MIPS_SZINT=32 -D_MIPS_SZPTR=32 \
  -std=gnu89 -funsigned-char -fno-builtin -w \
  -g -fno-eliminate-unused-debug-types \
  -c build/asmlift-ctx.c -o build/asmlift-ctx.o

cp build/animalforest-jp.elf build/animalforest-jp-syms.elf
for sec in .debug_info .debug_abbrev .debug_str .debug_line .debug_aranges; do
  # debug sections are non-alloc; objcopy -O binary dumps only alloc sections, so flag first
  mips-linux-gnu-objcopy -O binary --only-section=$sec \
    --set-section-flags $sec=alloc build/asmlift-ctx.o build/asmlift-ctx$sec.bin
  mips-linux-gnu-objcopy --add-section $sec=build/asmlift-ctx$sec.bin build/animalforest-jp-syms.elf
  rm -f build/asmlift-ctx$sec.bin
done

echo "built build/animalforest-jp-syms.elf"
