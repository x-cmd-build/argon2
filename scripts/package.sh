#!/bin/sh
#
# Package one built target into a release archive plus its .sha256.
#
#   TARGET    required — matches scripts/build.sh
#   BUILD_DIR optional — default <repo>/build/$TARGET
#   DIST_DIR  optional — default <repo>/dist
#
# Layout inside the archive (x-cmd convention: bin/ so that
# `export PATH=$PWD/bin:$PATH` is all a user needs):
#
#   argon2-<target>/
#   ├── bin/argon2[.exe]
#   ├── share/man/man1/argon2.1
#   ├── README.md, README.cn.md, SECURITY.md
#   ├── LICENSE            our wrapper licence (BSD-3-Clause)
#   ├── LICENSE.argon2     upstream licence (CC0-1.0 OR Apache-2.0)
#   └── NOTICE.md          attribution + provenance
#
# Linux/macOS ship .tar.xz; Windows ships .zip, because Windows' bundled
# tar.exe cannot be relied on to decompress xz.
#
set -eu

: "${TARGET:?TARGET is required}"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="${BUILD_DIR:-$ROOT/build/$TARGET}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"

name="argon2-$TARGET"
stage="$DIST_DIR/$name"

case "$TARGET" in
win-*) exe='.exe'; fmt=zip ;;
*)     exe='';     fmt=tar ;;
esac

[ -f "$BUILD_DIR/bin/argon2$exe" ] || {
    echo "package: missing $BUILD_DIR/bin/argon2$exe — run scripts/build.sh first" >&2
    exit 1
}

rm -rf "$stage"
mkdir -p "$stage/bin" "$stage/share/man/man1"

cp "$BUILD_DIR/bin/argon2$exe" "$stage/bin/"
cp "$ROOT/upstream/argon2/man/argon2.1" "$stage/share/man/man1/"
cp "$ROOT/upstream/argon2/LICENSE"      "$stage/LICENSE.argon2"
for f in README.md README.cn.md LICENSE NOTICE.md SECURITY.md; do
    cp "$ROOT/$f" "$stage/$f"
done

# Fixed timestamps so the same source produces the same archive bytes.
find "$stage" -exec touch -m -t 202311140000.00 {} +

cd "$DIST_DIR"
case "$fmt" in
tar)
    archive="$name.tar.xz"
    # --sort/--owner/--group are GNU tar; skip them on BSD tar (dev machines).
    if tar --sort=name --version >/dev/null 2>&1; then
        tar --sort=name --owner=0 --group=0 --numeric-owner \
            -cJf "$archive" "$name"
    else
        tar -cJf "$archive" "$name"
    fi
    ;;
zip)
    archive="$name.zip"
    rm -f "$archive"
    if command -v zip >/dev/null 2>&1; then
        zip -qr9X "$archive" "$name"
    else
        # No zip(1) on minimal images; python3's zipfile module is equivalent
        # for our purposes and is present on every GitHub Ubuntu image.
        python3 -m zipfile -c "$archive" "$name"
    fi
    ;;
esac

rm -rf "$stage"

if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$archive" > "$archive.sha256"
else
    shasum -a 256 "$archive" > "$archive.sha256"
fi

echo "==> $DIST_DIR/$archive"
cat "$archive.sha256"
