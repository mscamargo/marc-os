# AGENTS.md — marc-os

Personal Arch Linux setup. Shell scripts that install the i3wm stack and
symlink dotfiles. No package manager, no tests, no CI.

## Repository structure

| Path | Purpose |
|------|---------|
| `install.sh` | Entry point. Defines one `stage_<name>` function per stage and a `main` that runs them with optional `--only`/`--skip`/`--dry-run` flags. |
| `functions.sh` | Shared helpers: `info`, `warn`, `error`, `success`, `die`, `check_command`, `pacman_install`, `link_dotfile`, `migrate_ancestor_symlinks`, `prune_stale_links_in`. Sourced by `install.sh` and each hook. |
| `packages.csv` | LARBS-style package manifest consumed by `stage_install`. |
| `hooks/` | Optional pre/post-install scripts. Discovered by filename: `hooks/<package>.pre.sh` and `hooks/<package>.post.sh`. |
| `dotfiles/` | Mirrors `$HOME`. Every file is leaf-symlinked into place by `stage_configure`. |
| `check.sh` | Ad-hoc `shellcheck` runner over all `*.sh`. |
| `vm-*.sh` | QEMU/quickemu helpers for testing in a VM. |

## Stages

`install.sh` defines `STAGES=(check bootstrap install configure)` and runs them
in that order. Each is a function named `stage_<name>`.

| Stage | Purpose |
|-------|---------|
| `check`     | Pre-flight: Arch, non-root, pacman, git, internet. |
| `bootstrap` | `pacman -Syu`, install `base-devel` + `git`, bootstrap `yay`. |
| `install`   | Iterate `packages.csv`: install pacman/AUR/git rows, run per-row hooks. |
| `configure` | Leaf-symlink every file under `dotfiles/` into the mirrored path in `$HOME`, prune stale symlinks resolving into the repo, then `chsh -s zsh`. |

### CLI flags

- `--only STAGE[,STAGE...]` — allow-list.
- `--skip STAGE[,STAGE...]` — deny-list (wins over `--only`).
- `--dry-run` — exported as `DRY_RUN=1`; `link_dotfile`, `prune_stale_links_in`, `migrate_ancestor_symlinks`, and the `chsh` step print intended ops instead of executing.
- `-h` / `--help` — usage.

Unknown flags and unknown stage names exit non-zero. Dependencies between
stages are **not** validated; running `--only configure` on a bare system will
fail with the underlying error.

## packages.csv format

Three columns, comma-separated, unquoted, with a header row on line 1.
**Fields must not contain commas.** Blank lines are skipped.

    tag,name,description

| Tag | Meaning | `name` field |
|-----|---------|--------------|
| (blank) | pacman | package name |
| `A` | AUR via `yay` | package name |
| `G` | `git clone` to `~/.local/src/<repo>` | clone URL |

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
`source ../functions.sh` for shared helpers.

Row failures (install or hook) are collected and reported in a final summary;
the run continues after each failure and the stage exits non-zero if any row
failed. Other stages are fail-fast.

Known limitation: package names containing `.` would make the suffix
ambiguous. No current package has one.

## Critical workflow details

### Install script behavior
- Runs only on Arch Linux, as a regular user (not root). Uses `sudo` internally.
- `install.sh` sets `set -euo pipefail`; `functions.sh` does not (it is a sourced library).
- All four stages are idempotent: re-running is safe.

### Dotfile linking
- `stage_configure` runs `find dotfiles -type f` and translates each repo path `dotfiles/X` to target `$HOME/X`. The set of dotfiles is implicit in the directory tree; there is no list to edit.
- `link_dotfile` calls `migrate_ancestor_symlinks` first to replace any ancestor of the target that is a symlink resolving into `$REPO_ROOT` with a real directory (one-shot migration from the legacy dir-symlink layout). Then it `ln -sfn`s the leaf.
- If a real file (not symlink) already exists at the destination, it is backed up to `$dest.backup.<timestamp>`.
- After linking, `prune_stale_links_in` scans `$HOME` at depth 1 (catches stale top-level dotfiles) and each `$HOME/<name>/` whose `dotfiles/<name>/` is a directory (catches stale leaves). A link is pruned iff its `readlink -f` resolves into `$REPO_ROOT` and the target file is gone.
- All of `link_dotfile`, `migrate_ancestor_symlinks`, and `prune_stale_links_in` honor `DRY_RUN=1`: they `info` the intended op and return without touching the filesystem.

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
