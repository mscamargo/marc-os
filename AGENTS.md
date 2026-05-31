# AGENTS.md — marc-os

Personal Arch Linux setup. Shell scripts that install the i3wm stack and
symlink dotfiles. No package manager, no tests, no CI.

## Repository structure

| Path | Purpose |
|------|---------|
| `install.sh` | New-machine setup entry point. `main` runs `check` → `bootstrap` → `install_packages` → `setup_shell` → `configure_dotfiles` end-to-end. Tees each run to `$XDG_STATE_HOME/marc-os/install-<timestamp>.log`. Only flag is `-h`/`--help`. |
| `configure.sh` | Re-link dotfiles only. `assert_non_root` + `configure_dotfiles`. No flags, no log file. |
| `doctor.sh` | Read-only drift report. `assert_non_root` + walk `packages.csv` and `dotfiles/`, exit non-zero on drift. No flags, no log file. |
| `functions.sh` | Shared helpers: `info`, `warn`, `error`, `success`, `die`, `check_command`, `assert_non_root`, `pacman_install`, `enable_service`, `link_dotfile`, `migrate_ancestor_symlinks`, `prune_stale_links_in`, `parse_row`, `configure_dotfiles`. Sourced by the three entry-point scripts and each hook. |
| `packages.csv` | LARBS-style package manifest consumed by `install_packages` and `doctor.sh`. |
| `hooks/` | Optional pre/post-install scripts. Discovered by filename: `hooks/<package>.pre.sh` and `hooks/<package>.post.sh`. |
| `dotfiles/` | Mirrors `$HOME`. Every file is leaf-symlinked into place by `configure_dotfiles`. |
| `check.sh` | Ad-hoc `shellcheck` runner over all `*.sh`. |
| `vm-*.sh` | QEMU/quickemu helpers for testing in a VM. |

## Entry points

Three single-purpose scripts. No flag dispatcher, no `--only`/`--skip`.
Idempotency holds across all of them: every helper self-skips work that's
already done, so re-running is safe.

| Script | Steps | Pre-flight |
|--------|-------|-----------|
| `install.sh` | `check`, `bootstrap`, `install_packages`, `setup_shell`, `configure_dotfiles` | Arch + non-root + pacman/git + internet |
| `configure.sh` | `configure_dotfiles` | non-root |
| `doctor.sh` | walk `packages.csv` + `dotfiles/`; report missing pkgs, wrong/missing/shadowed links, orphan in-repo links | non-root |

### `install.sh` step breakdown

| Step | Purpose |
|------|---------|
| `check`     | Pre-flight: Arch, non-root, pacman, git, internet. |
| `bootstrap` | `tune_pacman_conf` (Color, ILoveCandy, ParallelDownloads, VerbosePkgLists, `[multilib]`), `refresh_keyring` (`pacman -S archlinux-keyring`), `pacman -Syu`, install `base-devel` + `git`, bootstrap `yay`. |
| `install_packages` | Start a background `sudo -v` keep-alive (trapped on EXIT), iterate `packages.csv`: install pacman/AUR/git rows, run per-row hooks. |
| `setup_shell` | `chsh -s zsh` if not already default. |
| `configure_dotfiles` | Shared with `configure.sh`. Leaf-symlink every file under `dotfiles/` into `$HOME`, prune stale symlinks resolving into the repo, unconditionally `rm` `~/.bash{rc,_profile,_logout}` (skipping symlinks). |

`-h` / `--help` prints usage. Any other flag exits non-zero.

### Logging

`install.sh` opens `$XDG_STATE_HOME/marc-os/install-<timestamp>.log` and
`tee`s stdout and stderr to it via `exec > >(tee -a ...) 2> >(tee -a ... >&2)`.
ANSI codes are preserved in the log; read with `less -R`. No rotation. The
last 1–2 lines may not flush on `set -e` crashes (process-substitution
limitation). `configure.sh` and `doctor.sh` do not log.

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
`install_packages` continues after each failure and exits non-zero if any row
failed. The other steps are fail-fast.

Known limitation: package names containing `.` would make the suffix
ambiguous. No current package has one.

## Critical workflow details

### Script behavior
- All three entry points run only as a regular user (not root); `install.sh` additionally requires Arch Linux and internet. Uses `sudo` internally where needed.
- Entry-point scripts set `set -euo pipefail`; `functions.sh` does not (it is a sourced library).
- Re-running is safe: `tune_pacman_conf` and `enable_service` self-skip when the change is already in place; `link_dotfile` no-ops when the link is correct; `setup_shell` self-skips when `$SHELL` already matches `command -v zsh`; the bash cleanup skips symlinks and absent files.
- `install_packages` keeps the sudo timestamp warm via a background `while true; do sudo -n true; sleep 60; done` started by `start_sudo_keepalive` and killed by `stop_sudo_keepalive` (also wired to an `EXIT` trap so a crash mid-install doesn't leak the loop).

### Dotfile linking
- `configure_dotfiles` (in `functions.sh`, called by both `install.sh` and `configure.sh`) runs `find dotfiles -type f` and translates each repo path `dotfiles/X` to target `$HOME/X`. The set of dotfiles is implicit in the directory tree; there is no list to edit.
- `link_dotfile` calls `migrate_ancestor_symlinks` first to replace any ancestor of the target that is a symlink resolving into `$REPO_ROOT` with a real directory (one-shot migration from the legacy dir-symlink layout). Then it `ln -sfn`s the leaf.
- If a real file (not symlink) already exists at the destination, it is backed up to `$dest.backup.<timestamp>`.
- After linking, `prune_stale_links_in` scans `$HOME` at depth 1 (catches stale top-level dotfiles) and each `$HOME/<name>/` whose `dotfiles/<name>/` is a directory (catches stale leaves). A link is pruned iff its `readlink -f` resolves into `$REPO_ROOT` and the target file is gone.
- `configure_dotfiles` finishes by `rm`-ing `~/.bash{rc,_profile,_logout}` if present (symlinks skipped) so they don't shadow zsh's init files.

### i3 launch flow
- TTY login → `startx` → `~/.xinitrc` (`exec i3`).
- i3 spawns daemons (`picom`, `dunst`, `clipmenud`, `polkit-gnome` agent, `xss-lock -- i3lock`) via `exec`, and re-applies `xsetroot` and `xset s 300` via `exec_always`.

### Adding helpers
- Put reusable helpers in `functions.sh` so all three entry-point scripts and the hooks see them. `parse_row` and `configure_dotfiles` live there for exactly this reason.
- Script-local helpers live in `install.sh` next to the function that calls them (e.g. `install_row` next to `install_packages`).

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
