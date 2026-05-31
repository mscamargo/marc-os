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
- Symlinks every file under `dotfiles/` into `$HOME` (per-leaf), auto-migrating
  any legacy dir-symlinks, and prunes stale links pointing into the repo
- Sets zsh as the default shell and removes legacy
  `~/.bash{rc,_profile,_logout}` so they don't shadow zsh
- Logs each `install.sh` run to `$XDG_STATE_HOME/marc-os/install-<timestamp>.log`

## Requirements

- Arch Linux
- Internet connection
- Run as a regular user (not root)

## Usage

Three top-level scripts, no flags:

    ./install.sh        # new-machine setup, end-to-end
    ./configure.sh      # re-link dotfiles only (the frequent loop)
    ./doctor.sh         # read-only drift report; exits 1 on drift

`install.sh` runs `check` → `bootstrap` → `install_packages` → `setup_shell` →
`dot::configure` in order. All three scripts are idempotent: every helper
self-skips work that's already done.

`install.sh` tees its output to `$XDG_STATE_HOME/marc-os/install-<timestamp>.log`
(defaults to `~/.local/state/marc-os/`). No rotation; clean up manually.
`configure.sh` and `doctor.sh` print to the terminal only.

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

Layout mirrors `$HOME` literally: `dotfiles/X` is symlinked to `$HOME/X`,
file by file. Examples:

| Repo path | Target |
|-----------|--------|
| `dotfiles/.zshrc` | `~/.zshrc` |
| `dotfiles/.config/nvim/init.lua` | `~/.config/nvim/init.lua` |
| `dotfiles/.config/mise/config.toml` | `~/.config/mise/config.toml` |
| `dotfiles/.config/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` |
| `dotfiles/.ssh/config` | `~/.ssh/config` |
| `dotfiles/.local/bin/screenshot-full` | `~/.local/bin/screenshot-full` |

Adding a new dotfile: drop the file at its mirrored path under `dotfiles/`
and re-run `./configure.sh`. No script edit.

Leaf-level linking means target directories are real, so files an app writes
into `~/.config/<x>/` (plugin lockfiles, sessions, history, …) stay in the
target tree and never dirty the repo. The first run after upgrading from the
old dir-symlink layout transparently replaces ancestor dir-symlinks with
real directories.

`dot::configure` also prunes any symlink that resolves into the repo but
whose target file is gone — so deleting a file from `dotfiles/` is enough;
the next `./configure.sh` run cleans up the orphan link.

## Architecture

```
install.sh ────┐
configure.sh ──┤
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
        │ lib/dotfiles │  ──▶ lib/log.sh
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

- `install.sh` / `configure.sh` / `doctor.sh` — entry points.
- `check.sh` — runs `shellcheck -x` + `shfmt -d -i 4 -ci -sr -bn` over
  every `*.sh`. Self-contained.
- `lib/` — shared modules (`log`, `util`, `sudo`, `lists`, `packages`,
  `dotfiles`). One concept per file. See "Architecture" above.
- `data/` — TAB-separated package lists: `pacman.list`, `aur.list`,
  `git_src.list`.
- `hooks/` — per-package install hooks, discovered by filename convention
  (`<package>.pre.sh`, `<package>.post.sh`). Each is subshell-executed
  with its own preamble.
- `dotfiles/` — mirrors `$HOME`. Every file is leaf-symlinked into place.
- `vm-*.sh` — helper scripts for QEMU VM workflows.

## License

MIT
