# marc-os

Personal Arch Linux setup. Installs a minimal i3wm environment.

## What it does

- Tunes `/etc/pacman.conf` (`Color`, `ILoveCandy`, `ParallelDownloads`,
  `VerbosePkgLists`, enables `[multilib]`), refreshes `archlinux-keyring`,
  runs `pacman -Syu`, and bootstraps the `yay` AUR helper
- Installs every package listed in `packages.csv` (Xorg, audio, fonts, zsh,
  neovim, i3 stack, apps, browsers, NetworkManager, bluez, plus a dev stack:
  `mise`, `docker`, `openssh`, `fzf`/`ripgrep`/`fd`/`bat`/`eza`/`jq`/`yq`,
  `github-cli`/`git-delta`/`lazygit`, `tmux`/`btop`, `httpie`/`bind`/`nmap`,
  `python-pipx`/`uv`, `shellcheck`, …) and runs any matching
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

`install.sh` runs `check` → `bootstrap` → `install` → `setup_shell` →
`configure_dotfiles` in order. All three scripts are idempotent: every
helper self-skips work that's already done.

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

Edit `packages.csv`. Three columns, comma-separated, with a header row:

    tag,name,description

| Tag | Source | `name` |
|-----|--------|--------|
| (blank) | pacman | package name |
| `A` | AUR (yay) | package name |
| `G` | `git clone` to `~/.local/src/<repo>` | clone URL |

`tag` and `name` must not contain commas. `description` may contain commas
if the field is wrapped in `"..."` (LARBS-style). The runner skips the
header row, blank lines, and any line beginning with `#`. Hook discovery
keys off `name` (or the repo basename for `G` rows), so package names
containing `.` would make the suffix ambiguous — avoid them.

## Hooks

Drop a script at `hooks/<package>.pre.sh` or `hooks/<package>.post.sh` and it
runs around that package's install step — no CSV plumbing. Both hooks fire on
every `install.sh` run as long as the package is present (or about to be), so
they must be idempotent. For `G` rows, `<package>` is the repo basename
without `.git` (matches `SRC_DIR`).

Hooks run as `bash <path>` with `PKG_NAME`, `PKG_TAG`, `PKG_DESC` exported
(and `SRC_DIR` for `G` rows). Source `../functions.sh` for shared helpers
(e.g. `enable_service <unit>` for the common "enable + start" pattern).

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

`configure_dotfiles` also prunes any symlink that resolves into the repo but
whose target file is gone — so deleting a file from `dotfiles/` is enough; the
next `./configure.sh` run cleans up the orphan link.

## Structure

- `install.sh` — new-machine setup entry point.
- `configure.sh` — dotfile re-link entry point.
- `doctor.sh` — drift report entry point.
- `functions.sh` — shared helpers (`info`, `die`, `pacman_install`,
  `enable_service`, `link_dotfile`, `prune_stale_links_in`, `parse_row`,
  `configure_dotfiles`, …) sourced by all three scripts and each hook.
- `packages.csv` — package manifest.
- `hooks/` — per-package install hooks, discovered by filename convention
  (`<package>.pre.sh`, `<package>.post.sh`).
- `dotfiles/` — mirrors `$HOME`. Every file is leaf-symlinked into place.
- `check.sh` — ad-hoc `shellcheck` runner over all `*.sh`.
- `vm-*.sh` — helper scripts for QEMU VM workflows.

## License

MIT
