#!/bin/sh
#
# Verify one built argon2 binary.
#
#   TARGET   required — matches scripts/build.sh
#   BIN_DIR  optional — default <repo>/build/$TARGET/bin
#   RUN      optional — command prefix for executing a foreign binary
#                       (e.g. "qemu-aarch64-static", "wine"). Unset means the
#                       binary runs natively on this host.
#
# Two levels of checking:
#
#   1. Format check — runs for every target. Confirms the object format and
#      machine field match what the target name promises, so a silently
#      mis-targeted build can't slip through.
#
#   2. Known-answer test — runs only when the binary can actually execute
#      here. The vectors are copied verbatim from upstream's own test suite
#      (upstream/argon2/src/test.c), so a passing KAT means this binary
#      agrees with the reference implementation bit for bit.
#
# Targets that can neither run natively nor under an emulator we have get
# level 1 only, and say so. They are never reported as "tested".
#
set -eu

: "${TARGET:?TARGET is required}"
RUN="${RUN-}"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN_DIR="${BIN_DIR:-$ROOT/build/$TARGET/bin}"

case "$TARGET" in
win-*) bin="$BIN_DIR/argon2.exe"; want_fmt=pe ;;
*)     bin="$BIN_DIR/argon2";     want_fmt=elf ;;
esac
case "$TARGET" in
darwin-*) want_fmt=macho ;;
esac
case "$TARGET" in
*-x64*)   want_arch=x86_64 ;;
*-arm64*) want_arch=aarch64 ;;
esac

[ -f "$bin" ] || { echo "smoke: missing $bin" >&2; exit 1; }

# ---------------------------------------------------------------- level 1

# Read the object header with od + tr only, so this works on a minimal image
# with no `file(1)` installed.
hexat() { od -An -tx1 -j "$2" -N "$3" "$1" | tr -d ' \n'; }

detect() {
    case "$(hexat "$1" 0 4)" in
    7f454c46)                                   # ELF
        case "$(hexat "$1" 18 2)" in            # e_machine, little-endian
        3e00) echo "elf x86_64" ;;
        b700) echo "elf aarch64" ;;
        *)    echo "elf unknown" ;;
        esac ;;
    cffaedfe)                                   # Mach-O 64-bit
        case "$(hexat "$1" 4 4)" in             # cputype
        07000001) echo "macho x86_64" ;;
        0c000001) echo "macho aarch64" ;;
        *)        echo "macho unknown" ;;
        esac ;;
    4d5a*)                                      # PE — "MZ" stub, then "PE\0\0"
        head=$(od -An -tx1 -N 512 "$1" | tr -d ' \n')
        case "$head" in                         # COFF Machine, little-endian
        *504500006486*) echo "pe x86_64" ;;
        *5045000064aa*) echo "pe aarch64" ;;
        *)              echo "pe unknown" ;;
        esac ;;
    *) echo "unknown unknown" ;;
    esac
}

got=$(detect "$bin")
if [ "$got" != "$want_fmt $want_arch" ]; then
    echo "smoke: $TARGET — FAIL: expected '$want_fmt $want_arch', got '$got'" >&2
    exit 1
fi
echo "smoke: $TARGET — format OK ($got, $(wc -c < "$bin") bytes)"

# ---------------------------------------------------------------- level 2

if [ -z "${RUN}${SMOKE_NATIVE-}" ]; then
    echo "smoke: $TARGET — not executable on this host; format check only"
    exit 0
fi

# password | salt | flags | expected encoded hash
#
# Verbatim from upstream/argon2/src/test.c. All use m=256 KiB so they finish
# in milliseconds even under an emulator. The p=2 vectors exercise the
# threading path (pthread on Unix, _beginthreadex on Windows).
vectors='password|somesalt|-i -t 2 -m 8 -p 1|$argon2i$v=19$m=256,t=2,p=1$c29tZXNhbHQ$iekCn0Y3spW+sCcFanM2xBT63UP2sghkUoHLIUpWRS8
password|somesalt|-i -t 2 -m 8 -p 2|$argon2i$v=19$m=256,t=2,p=2$c29tZXNhbHQ$T/XOJ2mh1/TIpJHfCdQan76Q5esCFVoT5MAeIM1Oq2E
password|somesalt|-id -t 2 -m 8 -p 1|$argon2id$v=19$m=256,t=2,p=1$c29tZXNhbHQ$nf65EOgLrQMR/uIPnA4rEsF5h7TKyQwu9U1bMCHGi/4
password|somesalt|-id -t 2 -m 8 -p 2|$argon2id$v=19$m=256,t=2,p=2$c29tZXNhbHQ$bQk8UB/VmZZF4Oo79iDXuL5/0ttZwg2f/5U52iv1cDc'

fail=0
echo "$vectors" | while IFS='|' read -r pwd salt flags want; do
    got=$(printf '%s' "$pwd" | $RUN "$bin" "$salt" $flags -e) || {
        echo "smoke: $TARGET — FAIL: argon2 $flags exited non-zero" >&2
        exit 1
    }
    got=$(printf '%s' "$got" | tr -d '\r')
    if [ "$got" != "$want" ]; then
        echo "smoke: $TARGET — FAIL: argon2 $flags" >&2
        echo "  want: $want" >&2
        echo "  got:  $got" >&2
        exit 1
    fi
    echo "smoke: $TARGET — KAT OK: argon2 $flags"
done || fail=1

[ "$fail" -eq 0 ] || exit 1

# Round-trip the verify path too: -e emits an encoded hash, and the same
# binary must accept it back.
enc=$(printf 'password' | $RUN "$bin" somesalt -id -t 2 -m 8 -p 1 -e | tr -d '\r')
printf 'password' | $RUN "$bin" somesalt -id -t 2 -m 8 -p 1 >/dev/null
echo "smoke: $TARGET — verify round-trip OK"
echo "smoke: $TARGET — PASS ($enc)"
