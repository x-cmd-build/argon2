# Security Review — x-cmd-build/argon2

Version-organized per `x-cmd-build/mneme/ORG_CONVENTIONS.md` §5.1. Newest
release first; each section is a self-contained snapshot.

---

# v0.1.0 (2026-09-06) — initial release

Source-level review of the vendored Argon2 reference implementation
before the first build. One pre-existing, upstream-reported memory-safety
bug was reproduced and is documented below. Nothing was patched — this
repository ships upstream verbatim.

## 1. Source-level audit scope

| Item | Value |
|---|---|
| Upstream | `p-h-c/phc-winner-argon2` |
| Commit | `f57e61e19229e23c4445b85494dbf7c07de721cb` (2021-06-25, `master`) |
| Version | tag `20190702`, `ARGON2_VERSION_NUMBER` = `0x13` |
| Licence | CC0-1.0 OR Apache-2.0 |
| Reviewed | `src/*.c`, `src/*.h`, `src/blake2/*`, `include/argon2.h`, `Makefile` |
| Not reviewed | `latex/`, `vs2015/`, `Argon2.sln`, `Package.swift` (not used by our build) |
| Modified by us | **nothing** — `upstream/argon2/` is a verbatim copy |

Files that actually end up in the shipped binary: `src/argon2.c`,
`src/core.c`, `src/blake2/blake2b.c`, `src/thread.c`, `src/encoding.c`,
plus exactly one of `src/opt.c` (x86-64) or `src/ref.c` (aarch64), plus
`src/run.c` (the CLI). `src/bench.c`, `src/genkat.c` and `src/test.c` are
build-time only and are not shipped.

## 2. Vulnerability findings

### F-1 (Low) — unchecked `-l` causes an out-of-bounds write

**Status: pre-existing upstream, reported upstream, unfixed, not patched here.**

`src/run.c` validates `-m`, `-k`, `-t` and `-p` against their documented
maxima, but `-l` (output length) is assigned with no range check:

```c
} else if (!strcmp(a, "-l")) {
    if (i < argc - 1) {
        i++;
        input = strtoul(argv[i], NULL, 10);
        outlen = input;              /* src/run.c:282 — no bounds check */
```

`outlen` is `uint32_t`, so at `outlen == 0xFFFFFFFF` the allocation

```c
out = malloc(outlen + 1);            /* src/run.c:121 */
```

is computed in 32-bit arithmetic, wraps to `malloc(0)`, and
`argon2_hash()` then writes `outlen` bytes into it.

Reproduced under AddressSanitizer (Debian 12, gcc, `-fsanitize=address`,
`src/ref.c` path):

```
==1224==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x602000000011
WRITE of size 4294967295 at 0x602000000011 thread T0
    #0 __interceptor_memcpy
    #1 argon2_hash src/argon2.c:161
    #2 run src/run.c:134
    #3 main src/run.c:332
0x602000000011 is located 0 bytes to the right of 1-byte region
allocated by thread T0 here:
    #1 run src/run.c:121
```

Trigger: `printf pw | argon2 somesalt -l 4294967295`.

**Impact: low.** This is the CLI wrapper, not `libargon2`. Reaching it
requires control over the `-l` argument of an argon2 invocation on the
local machine — an attacker who has that already controls the command
line. It needs a 64-bit host and enough RAM (or Linux overcommit) to get
past the intermediate allocations; on a memory-constrained host the
process is killed first (verified: OOM-kill at `-m 1g` in a container).
No network-reachable path exists — argon2 has no network surface.

**Upstream status.** Reported 2020-08-16 as
[PR #299](https://github.com/p-h-c/phc-winner-argon2/pull/299)
("Fix OOB write with crazy command line argument", by `stoeckmann`),
which widens `outlen` to `size_t` and rejects out-of-range input. The PR
is **still open and unmerged**; upstream's last commit is 2021-06-25.

**Our decision: do not patch.** Per the org rule that a build repo builds
and does not fork, we ship upstream verbatim. Patching `src/run.c` here
would mean `x-cmd-build/argon2` silently behaves differently from every
other argon2 build, which is a worse failure mode than a documented
low-impact CLI bug. If upstream merges #299 we pick it up with the next
vendored commit bump. Documented here, in `SECURITY.md` and in the
release notes so users are not surprised.

### F-2 (Informational) — `-l` silently truncates above 2^32

`strtoul` returns `unsigned long` (64-bit on LP64) and is assigned to a
`uint32_t`. `-l 4294967296` becomes `outlen == 0`, which is then caught
by the library's `ARGON2_MIN_OUTLEN` check and exits with
"Output is too short" (verified, exit 1). Wrong-but-safe: the user gets
an error rather than a 0-length hash. Same root cause as F-1; the same
upstream PR fixes it.

### Checked and found clean

| Area | Result |
|---|---|
| `src/encoding.c` base64 decode | Length-checked; `decode_string` validates every field and bails on short input. `argon2_encodedlen` fix from issue #162 is present. |
| `src/core.c` memory allocation | `allocate_memory` checks `memory_blocks > UINT32_MAX / sizeof(block)` before multiplying; no integer-overflow path found. |
| Secret wipe | `clear_internal_memory` / `secure_wipe_memory` used on password, salt, secret and the block array; not optimised away (`memset_s`/`SecureZeroMemory`/volatile fallback). |
| Timing safety | `argon2_compare` is a constant-time byte loop; `argon2_verify` uses it. Argon2i/id use data-independent addressing. |
| Parameter validation | `validate_inputs` enforces every `ARGON2_MIN_*`/`ARGON2_MAX_*` bound before any allocation. |
| Threading | `src/thread.c` — pthread on Unix, `_beginthreadex` on Windows; join is checked, no detached threads. |
| Password read | `fread` into a fixed `MAX_PASS_LEN` buffer with an explicit "longer than supported" rejection at the boundary — no overflow. |

No findings in the cryptographic core. The KAT vectors in
`src/test.c` and `kats/` reproduce exactly for both the `opt.c` and
`ref.c` paths (see `code-review.md` §2).

## 3. Static analysis results

- Compiler diagnostics: builds clean with upstream's `-Wall` for all
  eight targets under `zig cc` (clang 19). No new warnings introduced by
  cross-compilation.
- AddressSanitizer: clean on the full upstream test suite; the only
  report is F-1, reached solely through the out-of-range `-l` input.
- No `system()`, `popen()`, `exec*()`, `tmpfile()` or `/tmp` use anywhere
  in the shipped source — argon2 does not shell out or touch the
  filesystem.

## 4. Runtime hardening

| Property | Status |
|---|---|
| Static linking (musl, mingw) | Yes — no loader search path to hijack |
| Debug info stripped | Yes — `-g0` overrides upstream's `-g`; no `.pdb` shipped |
| Network surface | None |
| Filesystem surface | None (reads stdin, writes stdout) |
| Setuid/setgid | Not applicable |

Upstream hardcodes `-O3 -std=c89` and does not offer a
`-D_FORTIFY_SOURCE`/`-fstack-protector` knob outside its CI target. We do
not add flags upstream does not use — see `build-review.md` §8.

## 5. Operational security

- **Provenance**: source is a verbatim `git archive` of a named upstream
  commit. `NOTICE.md` records the commit; a full upstream mirror with all
  branches and tags is at `x-cmd-sourcecode/argon2`.
- **Supply chain**: every GitHub Action is pinned to a full commit SHA,
  never a tag.
- **Release integrity**: per-archive `.sha256`, a top-level `SHA256SUMS`,
  and a cosign/sigstore bundle for each archive and for `SHA256SUMS`
  (keyless, OIDC-bound to this workflow). The bundle is what makes
  `SHA256SUMS` itself trustworthy.
- **Build integrity**: no local builds; CI is the only path that produces
  a published artifact.

## 6. Audit sign-off

| Item | Status |
|---|---|
| Source reviewed at pinned commit | ✅ |
| Findings triaged | ✅ 1 Low (F-1), 1 Informational (F-2) |
| Findings reproduced, not assumed | ✅ ASan trace captured for F-1 |
| Upstream status checked | ✅ PR #299 open since 2020-08-16 |
| Upstream source unmodified | ✅ |
| Findings disclosed to users | ✅ this doc + `SECURITY.md` |

Reviewed for v0.1.0 on 2026-09-06.

---

## Related docs

- [`build-review.md`](build-review.md) — build system and flags
- [`code-review.md`](code-review.md) — CI matrix and test coverage
- [`NOTICE.md`](NOTICE.md) — upstream attribution and pinned commit

## Version

Document version 1.0, for `x-cmd-build/argon2` v0.1.0.
