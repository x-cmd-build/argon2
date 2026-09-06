# Security Policy

## Reporting a vulnerability

**Vulnerabilities in Argon2 itself** (the algorithm or the reference C
implementation) belong upstream:
<https://github.com/p-h-c/phc-winner-argon2/issues>.

**Vulnerabilities in this distribution** — the build scripts, the
workflows, or a released binary that does not match the source we
vendor:

- GitHub Security Advisories: <https://github.com/x-cmd-build/argon2/security/advisories/new>
- GitHub Issue: <https://github.com/x-cmd-build/argon2/issues>

Please allow 90 days before public disclosure, or coordinate a faster
timeline if the issue is being actively exploited.

## What we do and do not change

We do not patch the vendored source. Every released binary is built from
`upstream/argon2/` exactly as it appears in this repository, which is a
verbatim copy of upstream commit
`f57e61e19229e23c4445b85494dbf7c07de721cb`. If you find a difference
between a released binary's behaviour and upstream's, that is a bug in
this repository and we want to hear about it.

## Verifying a release

Every archive ships with a `.sha256` next to it, and each release has a
top-level `SHA256SUMS`:

```sh
sha256sum -c argon2-linux-x64-musl.tar.xz.sha256
```

Each released binary also passes the known-answer vectors taken verbatim
from upstream's own test suite (`upstream/argon2/src/test.c`) before it
is published — see `scripts/smoke.sh` and `code-review.md` for which
targets are executed in CI and which are only format-checked.

## Audit status

See [`security-review.md`](security-review.md) for the version-organized
audit history.
