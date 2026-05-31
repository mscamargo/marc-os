# AGENTS.md — marc-os

Personal Arch Linux setup. Shell scripts that install the i3wm stack and
symlink dotfiles. No package manager, no tests, no CI.

## Repository structure

| Path | Purpose |
|------|---------|
| `install.sh` | Entry point. Defines one `stage_<name>` function per stage and a `main` that runs them with optional `--only`/`--skip`/`--clean-bash` flags. Tees each run to `$XDG_STATE_HOME/marc-os/install-<timestamp>.log`. |
| `functions.sh` | Shared helpers: `info`, `warn`, `error`, `success`, `die`, `check_command`, `pacman_install`, `enable_service`, `link_dotfile`, `migrate_ancestor_symlinks`, `prune_stale_links_in`. Sourced by `install.sh` and each hook. |
| `packages.csv` | LARBS-style package manifest consumed by `stage_install`. |
| `hooks/` | Optional pre/post-install scripts. Discovered by filename: `hooks/<package>.pre.sh` and `hooks/<package>.post.sh`. |
| `dotfiles/` | Mirrors `$HOME`. Every file is leaf-symlinked into place by `stage_configure`. |
| `check.sh` | Ad-hoc `shellcheck` runner over all `*.sh`. |
| `vm-*.sh` | QEMU/quickemu helpers for testing in a VM. |

## Stages

`install.sh` defines `STAGES=(check bootstrap install configure doctor)` for
validation and `DEFAULT_STAGES=(check bootstrap install configure)` for the
default loop. Each is a function named `stage_<name>`. `doctor` is opt-in
(only runs when listed in `--only`).

| Stage | Purpose |
|-------|---------|
| `check`     | Pre-flight: Arch, non-root, pacman, git, internet. |
| `bootstrap` | `tune_pacman_conf` (Color, ILoveCandy, ParallelDownloads, VerbosePkgLists, `[multilib]`), `refresh_keyring` (`pacman -S archlinux-keyring`), `pacman -Syu`, install `base-devel` + `git`, bootstrap `yay`. |
| `install`   | Start a background `sudo -v` keep-alive (trapped on EXIT), iterate `packages.csv`: install pacman/AUR/git rows, run per-row hooks. |
| `configure` | Leaf-symlink every file under `dotfiles/` into the mirrored path in `$HOME`, prune stale symlinks resolving into the repo, `chsh -s zsh`, and (when `--clean-bash`) `rm` `~/.bash{rc,_profile,_logout}`. |
| `doctor`    | Read-only drift report: missing pacman/AUR/G packages, dotfiles whose link is wrong/missing/shadowed, orphan in-repo links. Exits non-zero on drift. |

### CLI flags

- `--only STAGE[,STAGE...]` — allow-list. Validated against `STAGES`. Only mechanism that lets `doctor` run.
- `--skip STAGE[,STAGE...]` — deny-list (wins over `--only`).
- `--clean-bash` — exported as `CLEAN_BASH=1`; in `configure`, `rm` `~/.bash{rc,_profile,_logout}`.
- `-h` / `--help` — usage.

Unknown flags and unknown stage names exit non-zero. Dependencies between
stages are **not** validated; running `--only configure` on a bare system will
fail with the underlying error.

### Logging

`main` opens `$XDG_STATE_HOME/marc-os/install-<timestamp>.log` and `tee`s
stdout and stderr to it via `exec > >(tee -a ...) 2> >(tee -a ... >&2)`.
ANSI codes are preserved in the log; read with `less -R`. No rotation. The
last 1–2 lines may not flush on `set -e` crashes (process-substitution
limitation).

## packages.csv format

Three columns, comma-separated, with a header row on line 1. Blank lines are
skipped.

    tag,name,description

| Tag | Meaning | `name` field |
|-----|---------|--------------|
| (blank) | pacman | package name |
| `A` | AUR via `yay` | package name |
| `G` | `git clone` to `~/.local/src/<repo>` | clone URL |

`tag` and `name` must not contain commas. `description` may contain commas
if the field is wrapped in `"..."` (LARBS-style). `parse_row` handles both
the unquoted and `"..."`-quoted forms; the surrounding quotes are stripped.

## Hooks

Hooks are discovered by filename convention, not declared in the CSV. For a
package keyed `<pkg>`, `install_row` looks for `hooks/<pkg>.pre.sh` and
`hooks/<pkg>.post.sh` and runs whichever exists, before and after the install
step respectively. The key is the package name for pacman/AUR rows, and the
repo basename (without `.git`) for `G` rows — same derivation as `SRC_DIR`.

Both hooks fire **every run** as long as the package is present (or about to
be installed). The install step itself is skipped when already installed
(`pacman -Qq` / `SRC_DIR` check), but the hooks still run. They must
therefore be idempotent. Hooks run as `bash <path>` with `PKG_NAME`,
`PKG_TAG`, `PKG_DESC` exported (and `SRC_DIR` for `G` rows). Hooks should
`source ../functions.sh` for shared helpers. For the common "enable + start
a unit" pattern, use `enable_service <unit>` from `functions.sh`; it is
idempotent.

Row failures (install or hook) are collected and reported in a final summary;
the run continues after each failure and the stage exits non-zero if any row
failed. Other stages are fail-fast.

Known limitation: package names containing `.` would make the suffix
ambiguous. No current package has one.

## Critical workflow details

### Install script behavior
- Runs only on Arch Linux, as a regular user (not root). Uses `sudo` internally.
- `install.sh` sets `set -euo pipefail`; `functions.sh` does not (it is a sourced library).
- All stages are idempotent: re-running is safe. `tune_pacman_conf` and `enable_service` self-skip when the change is already in place; `link_dotfile` no-ops when the link is correct.
- `stage_install` keeps the sudo timestamp warm via a background `while true; do sudo -n true; sleep 60; done` started by `start_sudo_keepalive` and killed by `stop_sudo_keepalive` (also wired to an `EXIT` trap so a crash mid-install doesn't leak the loop).

### Dotfile linking
- `stage_configure` runs `find dotfiles -type f` and translates each repo path `dotfiles/X` to target `$HOME/X`. The set of dotfiles is implicit in the directory tree; there is no list to edit.
- `link_dotfile` calls `migrate_ancestor_symlinks` first to replace any ancestor of the target that is a symlink resolving into `$REPO_ROOT` with a real directory (one-shot migration from the legacy dir-symlink layout). Then it `ln -sfn`s the leaf.
- If a real file (not symlink) already exists at the destination, it is backed up to `$dest.backup.<timestamp>`.
- After linking, `prune_stale_links_in` scans `$HOME` at depth 1 (catches stale top-level dotfiles) and each `$HOME/<name>/` whose `dotfiles/<name>/` is a directory (catches stale leaves). A link is pruned iff its `readlink -f` resolves into `$REPO_ROOT` and the target file is gone.

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

- No test suite or typechecker (shellcheck via `check.sh` is the only static analysis).
- No CI/CD.
- No dependency lockfile (relies on Arch repos and AUR).
- No multi-machine config: single `packages.csv` for one host. If/when a second machine appears, an overlay scheme would be the next addition.
- No log rotation: `$XDG_STATE_HOME/marc-os/` will grow forever; clean up manually.
