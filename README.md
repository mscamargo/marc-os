# marc-os

Personal Arch Linux setup. Installs a minimal i3wm environment.

## What it does

- Tunes `/etc/pacman.conf` (`Color`, `ILoveCandy`, `ParallelDownloads`,
  `VerbosePkgLists`, enables `[multilib]`), refreshes `archlinux-keyring`,
  runs `pacman -Syu`, and bootstraps the `yay` AUR helper
- Installs every package listed in `data/pacman.list`, `data/aur.list`, and
  `data/git_src.list` (Xorg, audio, fonts, zsh, neovim, i3 stack, apps,
  browsers, NetworkManager, bluez, plus a dev stack: `mise`, `docker`,
  `openssh`, `fzf`/`ripgrep`/`fd`/`bat`/`eza`/`jq`/`yq`,
  `github-cli`/`git-delta`/`lazygit`, `tmux`/`btop`, `httpie`/`bind`/`nmap`,
  `python-pipx`/`uv`, `shellcheck`/`shfmt`, …) and runs any matching
  `hooks/<package>.{pre,post}.sh` scripts (e.g. enabling
  `NetworkManager.service` / `bluetooth.service` / `docker.service`,
  generating an ed25519 SSH key, materializing `mise` runtimes)
- Keeps the sudo timestamp warm during the install loop so long AUR builds
  don't re-prompt
- Sets zsh as the default shell
- Logs each `install.sh` run to `$XDG_STATE_HOME/marc-os/install-<timestamp>.log`

## Requirements

- Arch Linux
- Internet connection
- Run as a regular user (not root)

## Bare-metal install (replaces archinstall)

For a fresh machine, boot the Arch ISO and run:

    curl -L https://mscamargo.github.io/marc-os/marc-os.sh | bash

`marc-os.sh` is a 10-line entry script that `pacman -Sy git`, clones this
repo to `/root/marc-os`, and execs `./bootstrap.sh`. `bootstrap.sh` prompts
for hostname/disk/CPU (with detected defaults), asks you to retype the disk
path to confirm wipe, then partitions (1G ESP + ext4 root + 8G swapfile),
pacstraps a minimal base, configures locale/keymap/timezone/hostname,
installs systemd-boot, creates the user (password-prompted wheel sudo, root
locked), and clones marc-os into `~$USER/Work/marc-os`. Reboot, log in, run
`./install.sh` by hand for the rest of the setup.

`bootstrap.sh` is single-shot: re-running wipes from scratch. No log file —
output is console-only. UEFI-only, no encryption, no LVM, no btrfs.

## Usage

Two top-level scripts, no flags:

    ./install.sh        # new-machine setup, end-to-end
    ./doctor.sh         # read-only drift report; exits 1 on drift

`install.sh` runs `check` → `bootstrap` → `install_packages` → `setup_shell`
in order. Both scripts are idempotent: every helper self-skips work that's
already done.

`install.sh` tees its output to `$XDG_STATE_HOME/marc-os/install-<timestamp>.log`
(defaults to `~/.local/state/marc-os/`). No rotation; clean up manually.
`doctor.sh` prints to the terminal only.

After installation, restart your shell or run `exec zsh -l`. Log in on a
TTY and run `startx` to launch i3.

The `docker` group is added during install; **log out and back in** before
running `docker` as your user. The `openssh` hook generates `~/.ssh/id_ed25519`
on first run (skipped if it already exists) and prints the public key to the
log so you can paste it into GitHub. `mise` materializes the runtimes pinned
in `~/.config/mise/config.toml` (Node LTS, Python, Go, Ruby) and enables
`corepack`. Zsh history lives under `$XDG_STATE_HOME/zsh/history`.

## Adding a package

Append a TAB-separated row to the file matching the install source:

| File | Source | First field |
|------|--------|-------------|
| `data/pacman.list`  | pacman | package name |
| `data/aur.list`     | AUR (yay) | package name |
| `data/git_src.list` | `git clone` to `~/.local/src/<repo>` | clone URL |

Format is `name<TAB>description`. Blank lines and `#`-comments are skipped.
A malformed row (missing TAB or empty name) aborts the run with a line
number. Hook discovery keys off the first field (or the repo basename for
`data/git_src.list` rows), so names containing `.` would make the suffix
ambiguous — avoid them.

## Hooks

Drop a script at `hooks/<package>.pre.sh` or `hooks/<package>.post.sh` and
it runs around that package's install step — no list plumbing. Both hooks
fire on every `install.sh` run as long as the package is present (or about
to be), so they must be idempotent. For `data/git_src.list` rows,
`<package>` is the repo basename without `.git` (matches `SRC_DIR`).

Hooks run as `bash <path>` in a subshell with `PKG_NAME`, `PKG_KIND` (one
of `pacman`/`aur`/`git`), and `PKG_DESC` exported (and `SRC_DIR` for `git`
rows). Each hook self-sources the lib files it uses (`lib/log.sh`,
`lib/packages.sh`, …) via a 4-line preamble; see existing hooks for the
exact shape. The common "enable + start a unit" pattern is
`pkg::enable_service <unit>`.

## Dotfiles

Dotfiles live in a separate repository and are no longer managed here. This
repo installs packages and configures the system only.

## Architecture

```
install.sh ────┐
doctor.sh ─────┤
hooks/*.sh ────┤   (each script self-sources only what it directly calls)
               ▼
        ┌──────────────┐
        │  lib/log.sh  │  ◀── (no deps)
        ├──────────────┤
        │  lib/util.sh │  ◀── (no deps)
        ├──────────────┤
        │  lib/sudo.sh │  ──▶ lib/log.sh
        │ lib/lists.sh │  ──▶ lib/log.sh
        │ lib/packages │  ──▶ lib/{log,util,lists}.sh
        └──────────────┘
```

Every `lib/*.sh` opens with a sentinel-var guard, so transitive sourcing
is a no-op and files may be sourced in any order. `check.sh` is the
exception — it lints the lib and therefore sources nothing from `lib/`.

Conventions: every public lib function uses `module::function` naming;
functions take their data as explicit arguments (no ambient state); shared
constants (`PKG_SRC_ROOT`, `SUDO_KEEPALIVE_INTERVAL`, colors) live
`readonly` at the top of their owning module. See `AGENTS.md` for the
full style guide.

## Structure

- `marc-os.sh` / `bootstrap.sh` — bare-metal installer; replaces
  archinstall. Run on the Arch ISO, not on an installed system.
- `install.sh` / `doctor.sh` — entry points (run on an installed system as
  your user).
- `check.sh` — runs `shellcheck -x` + `shfmt -d -i 4 -ci -sr -bn` over
  every `*.sh`. Self-contained.
- `lib/` — shared modules (`log`, `util`, `sudo`, `lists`, `packages`).
  One concept per file. See "Architecture" above.
- `data/` — TAB-separated package lists: `pacman.list`, `aur.list`,
  `git_src.list`.
- `hooks/` — per-package install hooks, discovered by filename convention
  (`<package>.pre.sh`, `<package>.post.sh`). Each is subshell-executed
  with its own preamble.
- `vm-*.sh` — helper scripts for QEMU VM workflows.

## License

MIT
