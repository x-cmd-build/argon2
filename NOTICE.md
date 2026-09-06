# Notice

This product includes software developed by the Argon2 authors:

- **Daniel Dinu**
- **Dmitry Khovratovich**
- **Jean-Philippe Aumasson**
- **Samuel Neves**

Argon2 won the [Password Hashing Competition](https://www.password-hashing.net/)
in July 2015. The source code vendored under `upstream/argon2/` is the
authors' reference C implementation:

```
phc-winner-argon2
Upstream:  https://github.com/p-h-c/phc-winner-argon2
Commit:    f57e61e19229e23c4445b85494dbf7c07de721cb (2021-06-25, master)
Version:   20190702 (most recent upstream tag, ARGON2_VERSION_NUMBER 0x13)
Copyright 2015 Daniel Dinu, Dmitry Khovratovich,
               Jean-Philippe Aumasson, and Samuel Neves
Licence:   CC0-1.0 OR Apache-2.0 (dual, at your option)
```

The full upstream licence text is at `upstream/argon2/LICENSE`, and is
shipped inside every release archive as `LICENSE.argon2`.

## What this repository does

`x-cmd-build/argon2` re-packages the upstream source with cross-compile
build scripts to produce portable binaries. **The vendored source under
`upstream/argon2/` is unmodified** — no patches, no forks, no behaviour
changes. `scripts/build.sh` drives upstream's own `Makefile`; it only
supplies `CC`, `OPTTARGET` and `LDFLAGS`.

A source mirror of upstream (all branches and tags, kept in sync twice
daily) lives at
[`x-cmd-sourcecode/argon2`](https://github.com/x-cmd-sourcecode/argon2).

## Licence of this repository

- **Our wrapper** (build scripts, workflows, docs): BSD-3-Clause, see `LICENSE`
- **Vendored argon2**: CC0-1.0 OR Apache-2.0, see `upstream/argon2/LICENSE`

Both are permissive, so the shipped binaries may be redistributed freely.
