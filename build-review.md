# Build Review — x-cmd-build/argon2

Version-organized per `x-cmd-build/mneme/ORG_CONVENTIONS.md` §5.1. Newest
release first.

---

# v0.1.0 (2026-09-06) — initial release

Eight targets, one runner, one compiler. `zig cc` supplies the libc for
every target, so the Alpine container / macOS runner / MSYS2 triad that
the other `x-cmd-build` repos use is replaced by a single Ubuntu job.

## 1. Build system overview

Upstream ships a plain `Makefile` — no autotools, no CMake, no configure
step. `scripts/build.sh` does not replace it. It selects a target, sets
three variables, and calls upstream's own `make argon2`:

```sh
make argon2 \
    CC="zig cc -target $triple" \
    OPTTARGET="$opt" \
    LDFLAGS="-g0 $ld"
```

Everything else — the source list, `-std=c89 -O3 -Wall`, `-pthread`, the
`src/opt.c` vs `src/ref.c` decision — is upstream's logic, untouched.

The build runs in a `mktemp -d` copy of `upstream/argon2/`, because
upstream's Makefile writes `.o` files next to the sources and the
vendored tree must stay byte-identical to the pinned commit.

## 2. Build flags

| Variable | Value | Why |
|---|---|---|
| `CC` | `zig cc -target <triple>` | One compiler for all eight targets. zig bundles glibc, musl, mingw-w64 and macOS libc headers/stubs, so no target needs its own SDK. |
| `OPTTARGET` | `x86_64` (x86) / `baseline` (arm) | Feeds upstream's probe, which compiles `src/opt.c` with `-march=$OPTTARGET` and falls back to `src/ref.c` on failure. **zig spells the x86-64 baseline CPU `x86_64`; gcc's `x86-64` is rejected with "unknown CPU"** — this is the one non-obvious substitution in the whole build. |
| `LDFLAGS` | `-g0` + `-static` where applicable | Upstream hardcodes `-g` into `CFLAGS`. Its recipe is a single compile-and-link line (`$(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@`), so `-g0` in `LDFLAGS` lands after `-g` and wins. This is why no separate strip step is needed, and why no `.pdb` is emitted for the Windows targets. |

### Why `x86_64` and not something newer

`-march=x86_64` is the SSE2 baseline. That is enough to select upstream's
optimised BLAMKA round — `src/blake2/blamka-round-opt.h` has SSE2, SSSE3,
AVX2 and AVX-512 paths and the SSE2 one is unconditional on x86-64 — while
keeping the binary runnable on every x86-64 CPU ever made. Choosing
`x86_64_v2` or `v3` would buy a faster round on modern hardware at the
cost of `SIGILL` on older, which is the wrong trade for a distributed
binary.

### Why aarch64 gets `src/ref.c`

`blamka-round-opt.h` is x86 SIMD only — there is no NEON path upstream.
The probe compiles `src/opt.c`, fails on missing `<emmintrin.h>`, and
upstream falls back to `src/ref.c`. That is the same code path Debian and
Alpine ship on arm64. Nothing is lost that upstream offers.

### Linkage per target

| Target | Linkage | Note |
|---|---|---|
| `linux-*-musl` | static | No loader, no glibc version floor; runs anywhere |
| `linux-*-gnu` | dynamic, glibc ABI pinned to 2.17 | Smaller (~40 KB); 2.17 is the RHEL 7 floor |
| `darwin-*` | dynamic against `/usr/lib/libSystem.B.dylib` | The only library argon2 needs on macOS; `-static` is not supported by Apple's linker |
| `win-*-mingw` | static | Avoids a `libwinpthread-1.dll` runtime dependency |

## 3. Build matrix

| Target | zig triple | ISA path | Archive |
|---|---|---|---|
| `linux-x64-musl` | `x86_64-linux-musl` | `opt.c` (SSE2) | `.tar.xz` |
| `linux-x64-gnu` | `x86_64-linux-gnu.2.17` | `opt.c` (SSE2) | `.tar.xz` |
| `linux-arm64-musl` | `aarch64-linux-musl` | `ref.c` | `.tar.xz` |
| `linux-arm64-gnu` | `aarch64-linux-gnu.2.17` | `ref.c` | `.tar.xz` |
| `darwin-x64` | `x86_64-macos` | `opt.c` (SSE2) | `.tar.xz` |
| `darwin-arm64` | `aarch64-macos` | `ref.c` | `.tar.xz` |
| `win-x64-mingw` | `x86_64-windows-gnu` | `opt.c` (SSE2) | `.zip` |
| `win-arm64-mingw` | `aarch64-windows-gnu` | `ref.c` | `.zip` |

No target is `continue-on-error`. All eight build; if one stops building,
the job fails.

**Not shipped: the BSDs.** zig 0.14 does not bundle a FreeBSD, NetBSD or
OpenBSD libc — `zig cc -target x86_64-freebsd-none` fails with "unable to
find or provide libc for target". Shipping them would require a sysroot
per BSD, which is a different build model. Verified, not assumed.

Windows ships `.zip` rather than `.tar.xz` because the `tar.exe` bundled
with Windows cannot be relied on to decompress xz.

## 4. Verification — what CI proves, and what it does not

This is the honest accounting the org conventions ask for. The build
runner is x86-64 Linux; it cannot execute a Mach-O or a PE.

| Target | Compiled | Object format checked | Binary executed + KAT |
|---|---|---|---|
| `linux-x64-musl` | ✅ | ✅ | ✅ natively on the build runner |
| `linux-x64-gnu` | ✅ | ✅ | ✅ natively on the build runner |
| `linux-arm64-musl` | ✅ | ✅ | ✅ natively on `ubuntu-24.04-arm` |
| `linux-arm64-gnu` | ✅ | ✅ | ✅ natively on `ubuntu-24.04-arm` |
| `darwin-x64` | ✅ | ✅ | ❌ no macOS runner |
| `darwin-arm64` | ✅ | ✅ | ❌ no macOS runner |
| `win-x64-mingw` | ✅ | ✅ | ❌ no Windows runner |
| `win-arm64-mingw` | ✅ | ✅ | ❌ no Windows runner |

Four of eight are executed against upstream's own known-answer vectors.
The other four are compiled and format-checked, and are reported in the
job summary as "format only" — never as tested.

What partially covers the four unexecuted targets: before any target is
packaged, CI runs upstream's full test suite on the build runner twice —
once through `src/opt.c` and once forced through `src/ref.c`
(`make test OPTTEST=1`). Every shipped binary uses one of those two code
paths, so the *source and toolchain* combination behind each target is
exercised even where the artifact itself cannot run. What remains
unverified for macOS and Windows is code generation and platform glue,
not algorithm correctness.

`scripts/smoke.sh` identifies object format and machine using `od` and
`tr` only — no `file(1)` dependency, so it works unchanged on a minimal
container image.

### Verified outside CI, for v0.1.0

Run against the archives CI actually produced
([run 34025974436](https://github.com/x-cmd-build/argon2/actions/runs/34025974436)),
after `sha256sum -c` on all eight:

| Check | Result |
|---|---|
| `darwin-arm64` on Apple Silicon macOS | Runs; KAT vector matches; `otool -L` shows only `/usr/lib/libSystem.B.dylib` |
| `darwin-x64` on the same host (Rosetta) | Runs; KAT vector matches; only libSystem |
| `linux-x64-musl` on clean `alpine:3.20` | Runs; KAT matches; `ldd` reports "not a valid dynamic program" — i.e. genuinely static |
| `linux-x64-musl` on clean `debian:12-slim` | Runs; KAT matches — the musl-static binary is glibc-distro portable, which is the whole point |
| `linux-x64-gnu` on clean `debian:12-slim` | Runs; KAT matches; links only `libpthread.so.0`, `libc.so.6`, loader |
| `win-x64-mingw` import table | `KERNEL32.dll` + `api-ms-win-crt-*` (Universal CRT) only. **No `libwinpthread-1.dll`, no `msys-2.0.dll`** — nothing to bundle. |

The Windows binaries have **not** been executed on Windows. The import
table is a checkable fact; "it runs" is not, until someone runs it. That
stays on the pre-release checklist in `code-review.md` §2.

### Runner ground truth (`ubuntu-slim`, measured)

`ubuntu-slim` is a 1-CPU unprivileged container. Its tool set was
inventoried in the first run rather than assumed:

- Present: `make`, `tar`, `xz`, `zip`, `python3`, `od`, `tr`,
  `sha256sum`, `file`. Runs as uid 1001.
- Absent: `qemu-aarch64-static`, `wine` — which is why the arm64
  binaries are executed on `ubuntu-24.04-arm` instead of under emulation.

Timing on `ubuntu-slim`: upstream test suite 55 s, eight-target
build + smoke + package 6 m 49 s, total 8 m 17 s against the hard
15-minute cap. Roughly 7 minutes of headroom; if upstream grows or
targets are added, the test suite and the build loop are the two things
to watch.

## 5. Reproducibility

- Source is pinned to an upstream commit, vendored in-tree.
- Toolchain is pinned: `ZIG_VERSION: 0.14.0` in both workflows.
- `-g0` removes debug paths, which are the usual source of host-dependent
  bytes.
- `scripts/package.sh` normalises all mtimes to a fixed timestamp and uses
  `tar --sort=name --owner=0 --group=0 --numeric-owner` where GNU tar is
  available.

Not yet verified bit-for-bit across two independent runs; that check is
planned rather than claimed.

## 6. Variance from ORG_CONVENTIONS.md

| Rule | Convention | Here | Reason |
|---|---|---|---|
| §2.1 | Alpine docker for Linux musl | `zig cc -target *-linux-musl` | Same static musl result, no container. ubuntu-slim cannot run docker anyway (unprivileged). |
| §2.2 | macOS runner + `-Wl,-force_load` + sed-strip | `zig cc -target *-macos` | argon2 links only libSystem — there is no OpenSSL to force-load. A macOS runner would add cost and buy nothing at build time. |
| §2.3 | MSYS2, never MinGW | `zig cc -target *-windows-gnu` | §2.3's ban on MinGW exists because MinGW-w64 lacks `sys/socket.h`/`netdb.h`. argon2 includes no POSIX networking headers; its Windows path is `<process.h>` + `_beginthreadex`, which mingw-w64 provides. Verified by compiling, not assumed. |
| §1 | `build-alpine.sh` + `package.ps1` | neither exists | Nothing runs on Alpine or PowerShell. |

ADR: `x-cmd-build/mneme/adr/0001-argon2-zig-cross-compile.md`.

## 7. Known limitations

1. **macOS and Windows binaries are not executed in CI** (§4). The macOS
   binaries were executed on real hardware outside CI for v0.1.0; the
   Windows binaries were not executed anywhere, only import-checked.
2. **No BSD targets** — zig has no bundled BSD libc (§3).
3. **`libargon2` is not shipped.** Only the CLI. Upstream's `make install`
   also installs `libargon2.a`, `libargon2.so`/`.dylib`, `argon2.h` and a
   `.pc` file; packaging those is a distinct decision (ABI, soname,
   per-platform link rules) and is deliberately out of scope for v0.1.0.
4. **Reproducibility not yet proven** (§5).

## 8. What we deliberately do not do

No added compiler flags, no patches, no wrapper scripts around the
binary. `-D_FORTIFY_SOURCE=2` and `-fsanitize=*` appear in upstream's
`CI_CFLAGS` for its own CI target and are not part of the flags upstream
uses to build a release; adding them here would make this build behave
differently from every other argon2 and would cross the line from
"building upstream" into "forking upstream".

## 9. Build script inventory

| Script | Role |
|---|---|
| `scripts/build.sh` | Target table + one `make` invocation. The single source of truth for triples and flags. |
| `scripts/smoke.sh` | Format/arch check for every target; upstream KAT vectors where the binary can run. |
| `scripts/package.sh` | Stages `bin/` + man page + licences, produces `.tar.xz`/`.zip` and `.sha256`. |
| `.github/run-matrix.sh` | Loops the eight targets, writes the job summary, fails if any target fails. Shared by both workflows so they cannot drift. |

## 10. Audit sign-off

| Item | Status |
|---|---|
| All eight targets build | ✅ |
| Flags reviewed and justified | ✅ |
| Verification claims match what CI actually runs | ✅ (§4) |
| Variance from org conventions documented | ✅ (§6) + ADR |
| Limitations stated rather than glossed | ✅ (§7) |

Reviewed for v0.1.0 on 2026-09-06.

---

## Related docs

- [`security-review.md`](security-review.md)
- [`code-review.md`](code-review.md)

## Version

Document version 1.0, for `x-cmd-build/argon2` v0.1.0.
