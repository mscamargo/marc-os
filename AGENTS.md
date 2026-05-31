# AGENTS.md — marc-os

Personal Arch Linux setup. Shell scripts that install the i3wm stack and
symlink dotfiles. No package manager, no tests, no CI.

## Repository structure

| Path | Purpose |
|------|---------|
| `install.sh` | Entry point. Defines one `stage_<name>` function per stage and a `main` that runs them with optional `--only`/`--skip` filters. |
| `functions.sh` | Shared helpers: `info`, `warn`, `error`, `success`, `die`, `check_command`, `pacman_install`, `link_dotfile`, `run_hook`. Sourced by `install.sh` and each hook. |
| `packages.csv` | LARBS-style package manifest consumed by `stage_install`. |
| `hooks/` | Optional pre/post-install scripts referenced from `packages.csv`. |
| `config/` | Dotfiles. Linked into `$HOME` and `$HOME/.config/` by `stage_configure`. |
| `config/bin/` | Custom executable scripts. Linked into `$HOME/.local/bin/`. |
| `vm-*.sh` | QEMU/quickemu helpers for testing in a VM. |

## Stages

`install.sh` defines `STAGES=(check bootstrap install configure)` and runs them
in that order. Each is a function named `stage_<name>`.

| Stage | Purpose |
|-------|---------|
| `check`     | Pre-flight: Arch, non-root, pacman, git, internet. |
| `bootstrap` | `pacman -Syu`, install `base-devel` + `git`, bootstrap `yay`. |
| `install`   | Iterate `packages.csv`: install pacman/AUR/git rows, run per-row hooks. |
| `configure` | Symlink `config/` into `$HOME` / `$HOME/.config/`, then `chsh -s zsh`. |

### CLI flags

- `--only STAGE[,STAGE...]` — allow-list.
- `--skip STAGE[,STAGE...]` — deny-list (wins over `--only`).
- `-h` / `--help` — usage.

Unknown flags and unknown stage names exit non-zero. Dependencies between
stages are **not** validated; running `--only configure` on a bare system will
fail with the underlying error.

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
also set to the clone target. Hooks should `source ../functions.sh` for shared
helpers.

`stage_install` skips rows whose package is already installed (`pacman -Qq`) or
whose `SRC_DIR` already exists. Row failures are collected and reported in a
final summary; the run continues after each failure and the stage exits
non-zero if any row failed. Other stages are fail-fast.

## Critical workflow details

### Install script behavior
- Runs only on Arch Linux, as a regular user (not root). Uses `sudo` internally.
- `install.sh` sets `set -euo pipefail`; `functions.sh` does not (it is a sourced library).
- All four stages are idempotent: re-running is safe.

### Dotfile linking
- `link_dotfile` in `functions.sh` symlinks with `ln -sfn`.
- If a real file (not symlink) already exists at the destination, it is backed up to `$dest.backup.<timestamp>`.

### i3 launch flow
- TTY login → `startx` → `~/.xinitrc` (`exec i3`).
- i3 spawns daemons (`picom`, `dunst`, `clipmenud`, `polkit-gnome` agent, `xss-lock -- i3lock`) via `exec`, and re-applies `xsetroot` and `xset s 300` via `exec_always`.

### Adding helpers
- Put reusable helpers in `functions.sh` so both `install.sh` and hooks see them.
- Stage-local helpers live in `install.sh` next to the stage function that calls them (e.g. `install_row` next to `stage_install`).

## VM testing

`vm-start.sh`, `vm-shutdown.sh`, `vm-restore.sh` use `quickemu` with a hard-coded VM path (`~/vms/archlinux/archlinux-latest.conf`).

`vm-sync.sh` copies the repo into the VM via `scp -P 22220`.

## Commit style

Plain imperative, e.g. `Add screenshot wrappers`, `Restructure scripts for i3 stack`.

## What this repo does NOT have

- No test suite, linter, or typechecker.
- No CI/CD.
- No dependency lockfile (relies on Arch repos and AUR).
