# argon2 — portable binaries

[![build-and-test](https://github.com/x-cmd-build/argon2/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/x-cmd-build/argon2/actions/workflows/build-and-test.yml)

Portable, self-contained builds of the [Argon2][upstream] reference CLI —
the password-hashing function that won the
[Password Hashing Competition][phc] in 2015.

Eight targets, all cross-compiled from a single Linux runner with
`zig cc`. No Alpine container, no macOS runner, no MSYS2.

*[中文](README.cn.md)*

## Install

```sh
x eget x-cmd-build/argon2
```

Or grab an archive from [Releases][releases] and put `bin/` on your PATH:

```sh
tar -xJf argon2-linux-x64-musl.tar.xz
export PATH="$PWD/argon2-linux-x64-musl/bin:$PATH"
argon2 --help
```

## Use

Argon2 reads the password from stdin and takes the salt as its first
argument:

```sh
# hash a password (Argon2id, 2 passes, 2^16 KiB = 64 MiB, 1 lane)
printf 'password' | argon2 somesalt -id -t 2 -m 16 -p 1

# encoded hash only — the form you store in a database
printf 'password' | argon2 somesalt -id -t 2 -m 16 -p 1 -e
$argon2id$v=19$m=65536,t=2,p=1$c29tZXNhbHQ$CTFhFdXPJO1aFaMaO6Mm5c8y7cJHAph8ArZWb2GRPPc

# raw hash only
printf 'password' | argon2 somesalt -id -t 2 -m 16 -p 1 -r
```

`-i` selects Argon2i (data-independent, the default), `-d` Argon2d
(data-dependent), `-id` Argon2id (hybrid — what you want unless you know
otherwise). Full flag list: `argon2 -h`, or `man argon2` using the page
shipped at `share/man/man1/argon2.1`.

## Targets

| Asset | OS / arch | libc | Linkage |
|---|---|---|---|
| `argon2-linux-x64-musl.tar.xz` | Linux x86-64 | musl | static |
| `argon2-linux-x64-gnu.tar.xz` | Linux x86-64 | glibc ≥ 2.17 | dynamic |
| `argon2-linux-arm64-musl.tar.xz` | Linux aarch64 | musl | static |
| `argon2-linux-arm64-gnu.tar.xz` | Linux aarch64 | glibc ≥ 2.17 | dynamic |
| `argon2-darwin-x64.tar.xz` | macOS x86-64 | libSystem | dynamic |
| `argon2-darwin-arm64.tar.xz` | macOS aarch64 | libSystem | dynamic |
| `argon2-win-x64-mingw.zip` | Windows x86-64 | mingw-w64 | static |
| `argon2-win-arm64-mingw.zip` | Windows aarch64 | mingw-w64 | static |

The musl builds are fully static — they run on any Linux distribution
regardless of its glibc version. The glibc builds are pinned to the 2.17
ABI (RHEL 7 era) and are smaller.

Windows ships `.zip` rather than `.tar.xz` because the `tar.exe` bundled
with Windows cannot be relied on to decompress xz.

x86-64 builds use upstream's SSE2-optimised BLAMKA round (`src/opt.c`) at
the baseline ISA, so they run on any x86-64 CPU. aarch64 builds use the
portable reference round (`src/ref.c`) — upstream has no NEON path.

## Build

CI is the build path; there is nothing to configure locally. To reproduce
a target by hand you need only `zig` and `make`:

```sh
TARGET=linux-x64-musl sh scripts/build.sh     # -> build/linux-x64-musl/bin/argon2
TARGET=linux-x64-musl sh scripts/smoke.sh     # format check + upstream KAT vectors
TARGET=linux-x64-musl sh scripts/package.sh   # -> dist/argon2-linux-x64-musl.tar.xz
```

`scripts/build.sh` holds the whole target table and calls upstream's own
`Makefile`. See [`build-review.md`](build-review.md) for the flag-by-flag
rationale.

## Provenance

The source under `upstream/argon2/` is upstream commit
[`f57e61e`][pin], unmodified. A full mirror of upstream (all branches and
tags) is kept at
[`x-cmd-sourcecode/argon2`](https://github.com/x-cmd-sourcecode/argon2).

## Licence

- Our wrapper (scripts, workflows, docs): BSD-3-Clause — see `LICENSE`
- Argon2 itself: CC0-1.0 OR Apache-2.0 — see `NOTICE.md`

[upstream]: https://github.com/p-h-c/phc-winner-argon2
[phc]: https://www.password-hashing.net/
[releases]: https://github.com/x-cmd-build/argon2/releases
[pin]: https://github.com/p-h-c/phc-winner-argon2/commit/f57e61e19229e23c4445b85494dbf7c07de721cb
