# x-cmd-build/argon2 — agent notes

> Public-facing agent note for `x-cmd-build/argon2`.
>
> Design / audit / decision docs live in the private
> [`x-cmd-build/mneme`](https://github.com/x-cmd-build/mneme) design HQ.
> Public repos stay clean (code + release artifacts); mneme holds the
> messy iteration.

## TL;DR for AI agents

- **What**: portable Argon2 CLI binaries, 8 targets, one build path.
- **Source**: vendored verbatim at `upstream/argon2/`, upstream commit
  `f57e61e19229e23c4445b85494dbf7c07de721cb`. **Do not modify it.**
- **Build**: `zig cc` cross-compile, every target from one Linux runner.
  `scripts/build.sh` holds the entire target table and shells out to
  upstream's own `Makefile` — it never patches sources.
- **CI triggers are explicit.** `build-and-test.yml` is
  `workflow_dispatch` only; pushing a commit must not start a run. Use
  `gh workflow run build-and-test.yml`.
- **All build flags and their rationale**: `build-review.md` §2.

## Org-convention variance

`x-cmd-build/mneme/ORG_CONVENTIONS.md` §2.1–§2.3 prescribe Alpine docker
for Linux, `-Wl,-force_load` on a macOS runner, and MSYS2 for Windows.
This repo overrides all three with a single `zig cc` cross-compile path.
The reasoning is recorded in the ADR at
`x-cmd-build/mneme/adr/0001-argon2-zig-cross-compile.md`; the practical
consequences (what CI can and cannot verify) are in `build-review.md` §4
and `code-review.md` §3.

## Issue & PR conventions

- **Public issues**: end-user bug reports, install problems.
- **Design / audit / roadmap**: issues on `x-cmd-build/mneme` (private).

## License

- Wrapper code (scripts, workflows, docs): BSD-3-Clause
- Vendored argon2: CC0-1.0 OR Apache-2.0 — see `NOTICE.md`
