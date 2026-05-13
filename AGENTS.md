# AGENTS.md — marc-os

Personal Arch Linux setup. Shell scripts + suckless C forks. No package manager, no tests, no CI.

## Repository structure

| Path | Purpose |
|------|---------|
| `install.sh` | Entry point. Sources `lib/common.sh`, runs `scripts/*.sh` in glob order. |
| `scripts/NN-*.sh` | Numbered setup steps. Must be `chmod +x` or `install.sh` skips them. |
| `lib/common.sh` | Shared helpers: `info`, `warn`, `die`, `pacman_install`, `link_dotfile`. |
| `config/` | Dotfiles (zsh, nvim, X11) linked into `$HOME` by `scripts/05-dotfiles.sh`. |
| `packages/` | **Personal forks** of dwm, dmenu, st, surf. Not used by `install.sh` directly. |
| `src/` | Created at runtime by `scripts/04-suckless.sh`; clones upstream suckless repos here. |
| `vm-*.sh` | QEMU/quickemu helpers for testing in a VM. |

## Critical workflow details

### Install script behavior
- Runs only on Arch Linux, as a regular user (not root). Uses `sudo` internally.
- Scripts run in glob order (`00-check.sh` → `01-base.sh` …). Numbering matters.
- Any non-executable `.sh` in `scripts/` is skipped with a warning.
- `install.sh` sets `set -euo pipefail`; individual scripts do too.

### Suckless build flow
- `scripts/04-suckless.sh` clones **upstream** repos (`git.suckless.org`) into `src/`, then `make && sudo make install`.
- It only builds **dwm, dmenu, st**. It does **not** build `surf`, even though `packages/surf/` exists in the repo.
- `packages/` contains the real custom forks. If you edit suckless config, edit files under `packages/`, then either:
  - copy changes into a running `src/` build tree, or
  - modify `04-suckless.sh` to build from `packages/` instead.
- Suckless Makefiles copy `config.def.h` → `config.h` at build time. `config.h` is gitignored in `src/`, and build artifacts live there.

### Dotfile linking
- `link_dotfile` in `lib/common.sh` symlinks with `ln -sfn`.
- If a real file (not symlink) already exists at the destination, it is backed up to `$dest.backup.<timestamp>`.

### `.gitignore` notes
- Ignores object files and binaries under `src/dwm/`, `src/dmenu/`, `src/st/`.
- Ignores `*.backup.*`.
- Does **not** ignore `src/surf/` build artifacts.

## VM testing

`vm-start.sh`, `vm-shutdown.sh`, `vm-restore.sh` use `quickemu` with a hard-coded VM path (`~/vms/archlinux/archlinux-latest.conf`).

`vm-sync.sh` copies the repo into the VM via `scp -P 22220`.

## Commit style

Plain imperative, e.g. `add personal surf fork`, `add install.sh script`.

## What this repo does NOT have

- No test suite, linter, or typechecker.
- No CI/CD.
- No dependency lockfile (relies on Arch repos and AUR).
