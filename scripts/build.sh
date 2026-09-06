#!/bin/sh
#
# Build one argon2 target with `zig cc`.
#
# Every target is built on a plain Linux runner. zig ships the headers and
# libc stubs for glibc, musl, mingw-w64 and macOS, so there is no Alpine
# container, no macOS runner and no MSYS2 anywhere in this pipeline.
# See build-review.md and the variance ADR in x-cmd-build/mneme.
#
# Environment:
#   TARGET   required — one of the names in the case block below
#   ZIG      optional — zig launcher (default: zig)
#   OUT_DIR  optional — where the binary lands (default: <repo>/build/$TARGET)
#
set -eu

: "${TARGET:?TARGET is required — see the case block in this script}"
ZIG="${ZIG:-zig}"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/upstream/argon2"
OUT_DIR="${OUT_DIR:-$ROOT/build/$TARGET}"

# Per-target zig triple, baseline ISA, and extra link flags.
#
# OPTTARGET drives upstream's Makefile probe: it compiles src/opt.c with
# -march=$OPTTARGET and falls back to the portable src/ref.c if that fails.
# argon2's optimised BLAMKA round (src/blake2/blamka-round-opt.h) is
# SSE2/SSSE3/AVX2/AVX-512 only, so x86_64 gets opt.c at the SSE2 baseline
# and aarch64 correctly falls back to ref.c — there is no NEON path to miss.
#
# Note zig spells the x86-64 baseline CPU `x86_64`; gcc's `x86-64` is
# rejected with "unknown CPU".
#
# glibc targets are pinned to 2.17 (RHEL 7 era) so the .so-linked builds
# run on every currently supported distro.
case "$TARGET" in
linux-x64-musl)   triple=x86_64-linux-musl;       opt=x86_64;   ld='-static'; exe='' ;;
linux-x64-gnu)    triple=x86_64-linux-gnu.2.17;   opt=x86_64;   ld='';        exe='' ;;
linux-arm64-musl) triple=aarch64-linux-musl;      opt=baseline; ld='-static'; exe='' ;;
linux-arm64-gnu)  triple=aarch64-linux-gnu.2.17;  opt=baseline; ld='';        exe='' ;;
darwin-x64)       triple=x86_64-macos;            opt=x86_64;   ld='';        exe='' ;;
darwin-arm64)     triple=aarch64-macos;           opt=baseline; ld='';        exe='' ;;
win-x64-mingw)    triple=x86_64-windows-gnu;      opt=x86_64;   ld='-static'; exe='.exe' ;;
win-arm64-mingw)  triple=aarch64-windows-gnu;     opt=baseline; ld='-static'; exe='.exe' ;;
*)
    echo "build.sh: unknown TARGET '$TARGET'" >&2
    exit 2
    ;;
esac

# Build in a scratch copy so the vendored tree stays pristine (upstream's
# Makefile writes .o files next to the sources).
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$SRC/." "$work/"
cd "$work"

# LDFLAGS lands after CFLAGS on upstream's single-step compile+link line
# ($(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@), so -g0 there overrides the -g that
# upstream hardcodes into CFLAGS. That keeps debug info — and the stray
# .pdb that zig emits for Windows targets — out of the shipped binary.
echo "==> $TARGET  (zig cc -target $triple, OPTTARGET=$opt)"
make argon2 \
    CC="$ZIG cc -target $triple" \
    OPTTARGET="$opt" \
    LDFLAGS="-g0 $ld"

mkdir -p "$OUT_DIR/bin"
cp argon2 "$OUT_DIR/bin/argon2$exe"

echo "==> $OUT_DIR/bin/argon2$exe"
ls -l "$OUT_DIR/bin/argon2$exe"
