# AGENTS.md — marc-os

Personal Arch Linux setup. Shell scripts that install the i3wm stack and
symlink dotfiles. No package manager, no tests, no CI.

## Repository structure

| Path | Purpose |
|------|---------|
| `install.sh` | Entry point. Sources `lib/common.sh`, runs `scripts/*.sh` in glob order. |
| `scripts/NN-*.sh` | Numbered setup steps. Must be `chmod +x` or `install.sh` skips them. |
| `lib/common.sh` | Shared helpers: `info`, `warn`, `die`, `pacman_install`, `link_dotfile`. |
| `packages.csv` | LARBS-style package manifest consumed by `scripts/03-packages.sh`. |
| `hooks/` | Optional pre/post-install scripts referenced from `packages.csv`. |
| `config/` | Dotfiles. Linked into `$HOME` and `$HOME/.config/` by `scripts/04-dotfiles.sh`. |
| `config/bin/` | Custom executable scripts. Linked into `$HOME/.local/bin/`. |
| `vm-*.sh` | QEMU/quickemu helpers for testing in a VM. |

## Script order

| # | Script | Purpose |
|---|--------|---------|
| 00 | `00-check.sh`     | Pre-flight: Arch, non-root, pacman, git, internet. |
| 01 | `01-base.sh`      | `pacman -Syu` and AUR-helper prerequisites (`base-devel`, `git`). |
| 02 | `02-aur-helper.sh`| Bootstrap `yay`. |
| 03 | `03-packages.sh`  | Iterate `packages.csv`: install pacman/AUR/git rows, run per-row hooks. |
| 04 | `04-dotfiles.sh`  | Symlink `config/` into `$HOME` and `$HOME/.config/`. |
| 05 | `05-shell.sh`     | `chsh -s zsh`. |

## packages.csv format

Five columns, no header row, comma-separated, unquoted. **Fields must not
contain commas.** Lines starting with `#` are comments and blanks are
skipped.

    tag,name,description,pre-install-script,post-install-script

| Tag | Meaning | `name` field |
|-----|---------|--------------|
| (blank) | pacman | package name |
| `A` | AUR via `yay` | package name |
| `G` | `git clone` to `~/.local/src/<repo>` | clone URL |

Hook columns are paths relative to repo root (e.g. `hooks/enable-bluetooth.sh`).
Empty cell = no hook. Hooks run as `bash "$REPO_ROOT/<path>"` with these env
vars exported: `PKG_NAME`, `PKG_TAG`, `PKG_DESC`; for `G` rows, `SRC_DIR` is
also set to the clone target. Hooks should source `lib/common.sh` for shared
helpers.

The runner skips rows whose package is already installed (`pacman -Qq`) or
whose `SRC_DIR` already exists. Row failures are collected and reported in a
final summary; the run continues after each failure and exits non-zero if any
row failed.

## Critical workflow details

### Install script behavior
- Runs only on Arch Linux, as a regular user (not root). Uses `sudo` internally.
- Scripts run in glob order (`00-check.sh` → `01-base.sh` …). Numbering matters.
- Any non-executable `.sh` in `scripts/` is skipped with a warning.
- `install.sh` sets `set -euo pipefail`; individual scripts do too.

### Dotfile linking
- `link_dotfile` in `lib/common.sh` symlinks with `ln -sfn`.
- If a real file (not symlink) already exists at the destination, it is backed up to `$dest.backup.<timestamp>`.

### i3 launch flow
- TTY login → `startx` → `~/.xinitrc` (`exec i3`).
- i3 spawns daemons (`picom`, `dunst`, `clipmenud`, `polkit-gnome` agent, `xss-lock -- i3lock`) via `exec`, and re-applies `xsetroot` and `xset s 300` via `exec_always`.

## VM testing

`vm-start.sh`, `vm-shutdown.sh`, `vm-restore.sh` use `quickemu` with a hard-coded VM path (`~/vms/archlinux/archlinux-latest.conf`).

`vm-sync.sh` copies the repo into the VM via `scp -P 22220`.

## Commit style

Plain imperative, e.g. `Add screenshot wrappers`, `Restructure scripts for i3 stack`.

## What this repo does NOT have

- No test suite, linter, or typechecker.
- No CI/CD.
- No dependency lockfile (relies on Arch repos and AUR).
