# Code Review — x-cmd-build/argon2

Version-organized per `x-cmd-build/mneme/ORG_CONVENTIONS.md` §5.1. Newest
release first.

"Code" here means *our* code — the build scripts and workflows. The
vendored argon2 source is reviewed in
[`security-review.md`](security-review.md) and is never modified.

---

# v0.1.0 (2026-09-06) — initial release

## 1. CI matrix health

Two workflows, both defined in terms of the same
`.github/run-matrix.sh`, so build-and-test and release cannot drift.

| Workflow | Trigger | Publishes |
|---|---|---|
| `build-and-test.yml` | `workflow_dispatch` **only** | no |
| `release.yml` | `push` of a `v*` tag, or `workflow_dispatch` | only when the ref is a tag |

**No push trigger on `build-and-test.yml`.** Committing must not start a
run; `gh workflow run build-and-test.yml` is the only way in. A
`workflow_dispatch` of `release.yml` on a branch builds and stops — the
`publish` job is gated on `startsWith(github.ref, 'refs/tags/v')`.

### Job layout

| Job | Runner | Does |
|---|---|---|
| `build` | `ubuntu-slim` (input-selectable) | Upstream test suite ×2 code paths, then build + smoke + package all eight targets |
| `verify-arm64` | `ubuntu-24.04-arm` | Downloads the artifacts the x64 job produced and *executes the shipped aarch64 binaries* |
| `publish` | `ubuntu-latest` | SHA256SUMS, cosign, GitHub Release (release.yml only) |

One job for eight targets rather than an 8-way matrix: every target uses
the same source, toolchain and runner, differing only in a `-target`
string. A matrix would re-download zig eight times to parallelise a few
seconds of compilation. The per-target step-summary table gives the same
pass/fail readout a matrix would.

`ubuntu-slim` is a 1-CPU container with a hard 15-minute cap and no
privileged operations. It fits this build because nothing here needs
docker, `sudo` or `binfmt_misc` — confirmed by inventorying the image in
the first run (`make`, `tar`, `xz`, `zip`, `python3`, `od`, `sha256sum`,
`file` all present; `qemu-aarch64-static` and `wine` absent). The first
green run took 8 m 17 s, so there is ~7 minutes of headroom.
`build-and-test.yml` exposes a `runner` input so a run can be moved to
`ubuntu-latest` without editing YAML if that headroom ever runs out.

## 2. Test coverage

### What runs in CI

1. **Upstream's own test suite, twice.** `make test` runs `kats/test.sh`
   (genkat output compared against the checked-in KAT files for Argon2
   i/d/id at v=16 and v=19) plus `src/test.c` (37 assertions covering
   hash vectors, encoding round-trips, invalid-encoding rejection,
   mismatched-password rejection and the error states). Run once through
   `src/opt.c` and once forced through `src/ref.c` via `OPTTEST=1`, so
   both code paths that ship are exercised.

2. **Per-target format check** — object format and machine field, read
   with `od`/`tr` so no `file(1)` is required. Catches a silently
   mis-targeted build.

3. **Per-target known-answer test, where the binary can execute.** Four
   vectors copied verbatim from `upstream/argon2/src/test.c` (Argon2i and
   Argon2id, `p=1` and `p=2`, all at `m=256` KiB), plus a verify
   round-trip. The `p=2` vectors exercise the threading path.

### Which targets are actually executed

| Executed against KAT vectors | Format-checked only |
|---|---|
| `linux-x64-musl`, `linux-x64-gnu` (build runner) | `darwin-x64`, `darwin-arm64` |
| `linux-arm64-musl`, `linux-arm64-gnu` (`ubuntu-24.04-arm`) | `win-x64-mingw`, `win-arm64-mingw` |

The step summary labels each row "KAT (executed)" or "format only". A
format-checked target is never reported as tested. Rationale and residual
risk: `build-review.md` §4.

### Manual checklist before tagging a release

- [x] `gh workflow run build-and-test.yml` is green, including `verify-arm64`
      — [run 34025974436](https://github.com/x-cmd-build/argon2/actions/runs/34025974436)
- [x] Step summary shows eight ✅ rows
- [x] Run `argon2 -h` and one KAT vector on a real macOS box — done for
      both `darwin-arm64` and `darwin-x64` (see `build-review.md` §4)
- [ ] Run `argon2.exe` and one KAT vector on a real Windows box — **not
      done.** The PE import table was checked (system DLLs only, nothing
      to bundle), but the binary has not been executed on Windows.
- [x] The three review docs have a section for the new version

Items 3 and 4 exist precisely because CI cannot make those claims.

## 3. Code review process

### CODEOWNERS

`*` requires both `@ljh-zs` and `@edwinjhlee`. `release.yml`,
`scripts/package.sh` and everything under `upstream/` are listed
explicitly — a diff under `upstream/` means the vendored tree stopped
being verbatim, which always needs owner eyes.

### Per-PR checklist

- [ ] `upstream/` unchanged, or the commit bump is stated and re-reviewed
- [ ] `scripts/build.sh` remains the only place triples and flags live
- [ ] No `|| true`, no suppressed failures
- [ ] Verification claims in docs still match what CI runs
- [ ] Actions still pinned to full commit SHAs

### Bot review policy

The `reviewer-gh` bot uses `--request-changes` only, never `--approve`.
Final approval is an owner's.

## 4. Known CI issues / workarounds

1. **`while` loop in a pipeline runs in a subshell.**
   `.github/run-matrix.sh` feeds targets to `while read`, so a failure
   flag set inside the loop would not survive. Failures are recorded via
   a sentinel file that the parent shell checks. Tested by injecting a
   bogus target: the script exits 1 and the summary marks the row ❌.

2. **`zig cc` needs an explicit `-target` even for the host.** Without
   one it tries to detect the system libc and fails to link
   (`undefined symbol: _strncmp` and friends on a machine with no SDK
   configured). Every invocation in this repo passes `-target`,
   including the host-native test-suite run.

3. **`-march=x86-64` is rejected by zig** ("unknown CPU: 'x86'"). zig's
   name for the baseline is `x86_64`. This is the flag most likely to be
   "corrected" back to gcc spelling by someone unfamiliar; it would break
   the x86 optimised path silently — the build would still succeed, just
   fall back to `ref.c`.

## 5. Audit sign-off

| Item | Status |
|---|---|
| Both workflows reviewed | ✅ |
| Triggers are explicit; no push-triggered runs | ✅ |
| Failure propagation tested, not assumed | ✅ (§4.1) |
| Test coverage claims match CI reality | ✅ (§2) |
| Actions pinned to commit SHAs | ✅ |
| No suppressed failures (`\|\| true`) | ✅ |

Reviewed for v0.1.0 on 2026-09-06.

---

## Related docs

- [`build-review.md`](build-review.md)
- [`security-review.md`](security-review.md)

## Version

Document version 1.0, for `x-cmd-build/argon2` v0.1.0.
