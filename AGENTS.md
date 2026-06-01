# AGENTS.md — marc-os

Personal Arch Linux setup. Shell scripts that bare-metal install Arch and
then layer the i3wm stack + dotfiles on top. No package manager, no tests,
no CI.

## Repository structure

| Path | Purpose |
|------|---------|
| `iso-bootstrap` | Curl-bash entry on the Arch ISO. `pacman -Sy git`, clone repo to `/root/marc-os`, `exec bootstrap.sh`. Extensionless on purpose (URL endpoint). Not picked up by `check.sh` because its glob is `*.sh`; lint manually if edited. |
| `bootstrap.sh` | Bare-metal Arch installer (replaces archinstall). Runs as root on the Arch ISO. Prompts hostname/disk/microcode (detected defaults), retype-disk-path confirmation, then partitions GPT (1G ESP + ext4 root), 8G swapfile, pacstraps a minimal base, chroot-configures locale/keymap/timezone/hostname/systemd-boot/NetworkManager, creates user (wheel password-prompted, root locked), clones marc-os to `~$USER/Work/marc-os`. Console-only output, no log file. EXIT trap unmounts `/mnt`. UEFI-only. Re-runs wipe from scratch. |
| `install.sh` | New-machine setup entry point. `main` runs `check` → `bootstrap` → `install_packages` → `setup_shell` → `dot::configure` end-to-end. Tees each run to `$XDG_STATE_HOME/marc-os/install-<timestamp>.log`. Only flag is `-h`/`--help`. |
| `configure.sh` | Re-link dotfiles only. `log::assert_non_root` + `dot::configure`. No flags, no log file. |
| `doctor.sh` | Read-only drift report. `log::assert_non_root` + walk `data/*.list` and `dotfiles/`, exit non-zero on drift. No flags, no log file. |
| `check.sh` | Self-contained lint script. Runs `shellcheck -x` + `shfmt -d -i 4 -ci -sr -bn` over every `*.sh`. Sources no lib. |
| `lib/log.sh` | `log::{info,warn,error,success,die,assert_non_root}` + color constants. No deps. |
| `lib/util.sh` | `util::has_command`. No deps. |
| `lib/sudo.sh` | `sudo::{keepalive_start,keepalive_stop}` + `SUDO_KEEPALIVE_INTERVAL`. Depends on log. |
| `lib/lists.sh` | `lists::for_each_row <list> <cb>`. Depends on log. |
| `lib/packages.sh` | `pkg::*` — install (pacman/aur/git), enable services, tune `pacman.conf`, bootstrap yay, dispatch hooks, walk lists. Owns `PKG_SRC_ROOT`. Depends on log, util, lists. |
| `lib/dotfiles.sh` | `dot::*` — readlink wrapper, ancestor migration, leaf-link, prune, top-level configure. Depends on log. |
| `data/pacman.list` | TAB-separated `name<TAB>description` rows. One per pacman package. |
| `data/aur.list` | TAB-separated `name<TAB>description` rows. One per AUR (yay) package. |
| `data/git_src.list` | TAB-separated `url<TAB>description` rows. Each is `git clone`d shallow into `$PKG_SRC_ROOT/<basename-without-.git>`. |
| `hooks/<pkg>.{pre,post}.sh` | Optional pre/post-install scripts. Discovered by filename; `<pkg>` is the row's name (or repo basename for git rows). |
| `dotfiles/` | Mirrors `$HOME`. Every file is leaf-symlinked into place by `dot::configure`. |
| `vm-*.sh` | QEMU/quickemu helpers for testing in a VM. |

## Entry points

Four single-purpose scripts at the root. `bootstrap.sh` is one-shot
(destructive); the rest are idempotent — every helper self-skips work
that's already done, so re-running is safe.

| Script | Steps | Pre-flight | Re-runnable? |
|--------|-------|-----------|--------------|
| `bootstrap.sh` | prompts → `partition` → `format_and_mount` → `pacstrap_base` → `write_fstab_and_swap` → `configure_chroot` → `create_user` → `clone_repo` → `handoff` | root + Arch ISO + UEFI + tools (`pacstrap`, `arch-chroot`, `sgdisk`, `wipefs`, `genfstab`, `blkid`, `mkfs.*`, `mkswap`, `partprobe`, `udevadm`, `lsblk`) + internet | One-shot; re-runs wipe from scratch via `sgdisk --zap-all && wipefs -af` |
| `install.sh` | `check`, `bootstrap`, `install_packages`, `setup_shell`, `dot::configure` | Arch + non-root + pacman + internet | Yes |
| `configure.sh` | `dot::configure` | non-root | Yes |
| `doctor.sh` | walk `data/*.list` + `dotfiles/`; report missing pkgs, wrong/missing/shadowed links, orphan in-repo links | non-root | Yes |

### `install.sh` step breakdown

| Step | Purpose |
|------|---------|
| `check`            | Pre-flight: Arch, non-root, pacman, internet. |
| `bootstrap`        | `pkg::tune_pacman_conf /etc/pacman.conf` (Color, ILoveCandy, ParallelDownloads, VerbosePkgLists, `[multilib]`), `pkg::refresh_keyring`, `pacman -Syu`, `pkg::install_pacman base-devel git`, `pkg::bootstrap_aur_helper`. |
| `install_packages` | `sudo::keepalive_start`, then `pkg::install_list` for `data/pacman.list`, `data/aur.list`, `data/git_src.list` (each runs per-row hooks); `sudo::keepalive_stop`. |
| `setup_shell`      | `chsh -s zsh` if not already default. |
| `dot::configure`   | Shared with `configure.sh`. Leaf-symlink every file under `dotfiles/` into `$HOME`, prune stale symlinks resolving into the repo, unconditionally `rm` `~/.bash{rc,_profile,_logout}` (skipping symlinks). |

`-h` / `--help` prints usage. Any other flag exits non-zero.

### `bootstrap.sh` constants and config

Hardcoded `readonly` block at the top:

| Constant | Value |
|----------|-------|
| `USERNAME` | `mscamargo` |
| `USER_SHELL` | `/bin/bash` (marc-os `setup_shell` `chsh`s to zsh later) |
| `LOCALE` / `EXTRA_LOCALES` | `en_US.UTF-8` / `(pt_BR.UTF-8)` — both uncommented in `/etc/locale.gen`, `LANG=$LOCALE` in `/etc/locale.conf` |
| `TIMEZONE` | `America/Sao_Paulo` |
| `KEYMAP` | `us` (console `vconsole.conf`) |
| `REPO_URL` | `https://github.com/mscamargo/marc-os.git` (HTTPS — no SSH key on the new system yet) |
| `REPO_DEST_REL` | `Work/marc-os` (relative to `~$USERNAME`) |
| `ESP_SIZE` / `SWAP_SIZE` | `1G` / `8G` |
| `PACSTRAP_PKGS` | `base linux linux-firmware sudo networkmanager git neovim openssh` (microcode appended after CPU prompt) |

Per-machine variables (`hostname`, `disk`, `ucode`) are prompted in `main`
with detected defaults from `lsblk -ndb` (largest non-USB disk) and
`/proc/cpuinfo` (`vendor_id` → `intel-ucode`/`amd-ucode`). The destructive
wipe is gated by retyping the full disk path verbatim; mismatched input
calls `log::die`. The `bootstrap::*` namespace is reserved for any future
helpers; current internal helpers use a single-underscore prefix
(`_prompt`, `_detect_disk`, `_detect_ucode`, `_partition_path`,
`_disk_info_line`, `_confirm_wipe`).

### Logging

`install.sh` opens `$XDG_STATE_HOME/marc-os/install-<timestamp>.log` and
`tee`s stdout and stderr to it via `exec > >(tee -a ...) 2> >(tee -a ... >&2)`.
ANSI codes are preserved in the log; read with `less -R`. No rotation. The
last 1–2 lines may not flush on `set -e` crashes (process-substitution
limitation). `bootstrap.sh`, `configure.sh`, and `doctor.sh` do not log to
a file — console only.

## data/*.list format

Three TAB-separated files, one per install source:

    name<TAB>description

Blank lines and lines beginning with `#` are skipped. The parser
(`lists::for_each_row`) aborts via `log::die` on a malformed row (missing
TAB or empty name).

| File | Source | First field |
|------|--------|-------------|
| `data/pacman.list`  | `sudo pacman -S --needed --noconfirm` | package name |
| `data/aur.list`     | `yay -S --needed --noconfirm`         | AUR package name |
| `data/git_src.list` | `git clone --depth 1` into `$PKG_SRC_ROOT/<key>` | clone URL |

Package names containing `.` make the hook-suffix derivation ambiguous
(`hooks/<name>.{pre,post}.sh`) and are unsupported.

## Hooks

Hooks are discovered by filename convention, not declared in the list. For a
row keyed `<pkg>`, `pkg::run_pre_hook` / `pkg::run_post_hook` look for
`hooks/<pkg>.pre.sh` and `hooks/<pkg>.post.sh` and run whichever exists,
before and after the install step respectively. The key is the row's first
field for pacman/AUR, and the repo basename (without `.git`) for git rows —
same derivation as `SRC_DIR`.

Both hooks fire **every run** as long as the package is present (or about to
be installed). The install step itself is skipped when already installed
(`pacman -Qq` / `SRC_DIR` check), but the hooks still run. They must
therefore be idempotent. Hooks run as `bash <path>` in a subshell with
`PKG_NAME`, `PKG_KIND` (one of `pacman`/`aur`/`git`), and `PKG_DESC`
exported (and `SRC_DIR` for `git` rows).

Hooks open with the canonical self-sourcing preamble — no positional args,
no shared ambient state, one `source` line per direct lib dependency:

```bash
#!/usr/bin/env bash
set -euo pipefail
__HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/packages.sh
source "$__HOOK_DIR/../lib/packages.sh"
```

Row failures (install or hook) are collected per list and reported in a
final summary; `pkg::install_list` continues after each failure and exits
non-zero if any row failed. `install_packages` runs all three lists
independently and returns non-zero if any one of them failed. The other
steps are fail-fast.

Current hooks: `hooks/networkmanager.post.sh`, `hooks/bluez.post.sh`,
`hooks/docker.post.sh` (enable `docker.service`, add `$USER` to `docker`
group, warn about re-login), `hooks/openssh.post.sh` (idempotent
`ssh-keygen -t ed25519`, enable user `ssh-agent.service`, echo pubkey),
`hooks/mise.post.sh` (`mise install` from `~/.config/mise/config.toml`,
then `corepack enable`).

## Style

Conventions every script in this repo follows. New code should match.

- **Modules**: shared code lives in `lib/<name>.sh`, one concept per file.
  Entry points (`install.sh`, `configure.sh`, `doctor.sh`) stay at the
  repo root. `check.sh` is self-contained (it lints the lib).
- **Naming**: every public lib function uses `module::function` form
  (`log::info`, `pkg::install_pacman`, `dot::link`, …). Helpers internal to
  one module use `module::_name`. Entry-point top-level functions stay
  un-namespaced (`check`, `bootstrap`, `install_packages`, `setup_shell`).
- **Self-sourcing**: every `lib/*.sh` opens with a sentinel-var guard and
  sources its own deps:
  ```bash
  [[ -n ${__LIB_<NAME>_SOURCED:-} ]] && return 0
  __LIB_<NAME>_SOURCED=1
  __LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$__LIB_DIR/<dep>.sh"
  unset __LIB_DIR
  ```
  Files may be sourced in any order; double-sourcing is a no-op.
- **Pure-as-practical**: lib functions take data (paths, names) as explicit
  args. Config-like constants (`PKG_SRC_ROOT`, `SUDO_KEEPALIVE_INTERVAL`,
  colors) live `readonly` at the top of the owning module.
- **Function size**: ~50-line ceiling, one verb at one level of abstraction.
  Extract a helper when a block reaches the rule of three.
- **Bash discipline**: every entry point and hook starts with
  `set -euo pipefail`. `lib/*.sh` files do not — they are sourced libraries.
  Quote all expansions, prefer `[[ ]]` over `[ ]`, use `local` for all
  function-scoped variables.
- **Logging**: never `echo` user-facing output. Use `log::{info,warn,error,
  success,die}`. Errors go to stderr; everything else to stdout.
- **Lint/format**: `./check.sh` runs `shellcheck -x` and
  `shfmt -d -i 4 -ci -sr -bn` over every `*.sh`. Both must be clean before
  committing.

## Verification

After any change, run:

```
./check.sh        # shellcheck + shfmt -d clean
./doctor.sh       # zero drift (on a marc-os host)
```

`check.sh` globs `*.sh`, so `iso-bootstrap` (extensionless) is skipped — if
you edit it, manually run `shellcheck --shell=bash iso-bootstrap` and
`shfmt -d -i 4 -ci -sr -bn iso-bootstrap`.

For an end-to-end test of marc-os, restore a fresh VM, sync the repo, then
inside the VM: `./install.sh && ./doctor.sh && ./check.sh`.

For an end-to-end test of `bootstrap.sh`, boot a blank-disk VM from the
Arch ISO and run the curl-bash one-liner; after first reboot, log in and
run `./install.sh && ./doctor.sh && ./check.sh`.

## VM testing

All `vm-*.sh` wrappers use `quickemu` with a hard-coded VM path
(`~/vms/archlinux/archlinux-latest.conf`).

| Script | Purpose |
|--------|---------|
| `vm-start.sh` | `quickemu --vm …` — start the VM with whatever the conf currently says. |
| `vm-shutdown.sh` | `monitor-cmd system_powerdown` — graceful shutdown. |
| `vm-snapshot.sh [tag]` | Create a snapshot (default tag `clean-base`). |
| `vm-restore.sh` | Apply the `clean-base` snapshot. |
| `vm-sync.sh` | `scp -P 22220` the repo into the running VM. |
| `vm-recreate.sh` | Shutdown, `rm` `disk.qcow2`, uncomment `iso=`, start. Fresh ISO boot for testing `bootstrap.sh`. |
| `vm-boot-disk.sh` | Shutdown, comment `iso=`, start. Boot from the installed disk (no CDROM attached). |

Typical bootstrap-test loop:

```
./vm-recreate.sh                                              # fresh ISO boot
# in guest: curl -L .../iso-bootstrap | bash                  # run bootstrap.sh
# in guest: poweroff                                          # after handoff message
./vm-boot-disk.sh                                             # reboot off the new disk
# in guest: log in, cd ~/Work/marc-os && ./install.sh
./vm-snapshot.sh clean-base                                   # save the post-install state
```

`vm-recreate.sh` and `vm-boot-disk.sh` `sed` the `iso=` line in
`archlinux-latest.conf` in-place, so the conf file is the source of truth
for whether the CDROM is attached.

## Commit style

Plain imperative, e.g. `Add screenshot wrappers`, `Extract lib/log.sh`.

## What this repo does NOT have

- No test suite or typechecker (shellcheck + shfmt via `./check.sh` is the
  only static analysis).
- No CI/CD.
- No dependency lockfile (relies on Arch repos and AUR).
- No multi-machine config: single set of lists for one host.
- No log rotation: `$XDG_STATE_HOME/marc-os/` will grow forever; clean up
  manually.
