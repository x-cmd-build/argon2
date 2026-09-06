#!/bin/sh
#
# Build, smoke-test and package every target, then write a per-target
# summary table. Used by both build-and-test.yml and release.yml so the
# two workflows cannot drift apart.
#
# Exits non-zero if any target fails. Nothing here suppresses an error.
#
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

TARGETS='linux-x64-musl
linux-x64-gnu
linux-arm64-musl
linux-arm64-gnu
darwin-x64
darwin-arm64
win-x64-mingw
win-arm64-mingw'

host=$(uname -m)
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
failed=0

# How, if at all, this host can execute a given target's binary.
#
# Only native execution is used. qemu-user could cover linux-arm64-musl,
# but it is absent from the Ubuntu runner images and installing it needs
# privileges that ubuntu-slim does not grant — so the arm64 binaries are
# executed by the separate arm64 job instead (see build-and-test.yml), and
# anything we cannot run is reported as format-checked, never as tested.
how_to_run() {
    case "$1:$host" in
    linux-x64-*:x86_64)   echo native ;;
    linux-arm64-*:aarch64) echo native ;;
    *)                    echo none ;;
    esac
}

{
    echo "## argon2 build matrix"
    echo
    echo "Host: \`$(uname -srm)\` · zig \`$(zig version 2>/dev/null || echo '?')\`"
    echo
    echo "| Target | Result | Size | Verification |"
    echo "|---|---|---|---|"
} >> "$summary"

echo "$TARGETS" | while read -r target; do
    [ -n "$target" ] || continue

    echo "::group::$target"
    status=ok
    detail=

    if ! TARGET="$target" sh scripts/build.sh; then
        status=build-failed
    fi

    if [ "$status" = ok ]; then
        run=$(how_to_run "$target")
        case "$run" in
        native) detail='KAT (executed)'; export SMOKE_NATIVE=1; unset RUN 2>/dev/null || : ;;
        none)   detail='format only';    unset SMOKE_NATIVE 2>/dev/null || : ;;
        esac
        if ! TARGET="$target" sh scripts/smoke.sh; then
            status=smoke-failed
        fi
        unset SMOKE_NATIVE 2>/dev/null || :
    fi

    if [ "$status" = ok ] && ! TARGET="$target" sh scripts/package.sh; then
        status=package-failed
    fi
    echo "::endgroup::"

    case "$target" in
    win-*) archive="dist/argon2-$target.zip" ;;
    *)     archive="dist/argon2-$target.tar.xz" ;;
    esac
    if [ -f "$archive" ]; then
        size=$(wc -c < "$archive" | tr -d ' ')
        size="$((size / 1024)) KiB"
    else
        size='—'
    fi

    if [ "$status" = ok ]; then
        echo "| \`$target\` | ✅ pass | $size | $detail |" >> "$summary"
    else
        echo "| \`$target\` | ❌ $status | $size | $detail |" >> "$summary"
        echo "run-matrix: $target FAILED ($status)" >&2
        # Record the failure for the parent shell — `while` runs in a
        # subshell when fed by a pipe, so a variable would not survive.
        : > "$ROOT/.matrix-failed"
    fi
done

if [ -f "$ROOT/.matrix-failed" ]; then
    rm -f "$ROOT/.matrix-failed"
    failed=1
fi

{
    echo
    if [ "$failed" -eq 0 ]; then
        echo "All targets built. Targets marked *format only* were compiled and"
        echo "their object format verified, but could not be executed on this"
        echo "runner — they are not claimed as tested."
    else
        echo "**One or more targets failed.**"
    fi
} >> "$summary"

exit "$failed"
