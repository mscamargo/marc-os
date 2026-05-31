# marc-os

Personal Arch Linux setup. Installs a minimal i3wm environment.

## What it does

- Updates the system and bootstraps `yay` AUR helper
- Installs every package listed in `packages.csv` (Xorg, audio, fonts, zsh,
  neovim, i3 stack, apps, browsers, NetworkManager, bluez, …) and runs any
  matching `hooks/<package>.{pre,post}.sh` scripts (e.g. enabling
  `NetworkManager.service` and `bluetooth.service`)
- Links dotfiles into `$HOME`
- Sets zsh as the default shell

## Requirements

- Arch Linux
- Internet connection
- Run as a regular user (not root)

## Usage

    ./install.sh                       # everything, in order
    ./install.sh --only configure      # only re-link dotfiles + set shell
    ./install.sh --skip check          # skip the pre-flight check
    ./install.sh -h                    # usage

Stages (run in this order): `check`, `bootstrap`, `install`, `configure`.
`--only` and `--skip` take a comma-separated list of stage names. They can be
combined; `--skip` wins on conflicts. No dependency validation — if you
`--only configure` on a bare system, you'll see the underlying errors.

After installation, restart your shell or run `exec zsh -l`. Log in on a
TTY and run `startx` to launch i3.

## Adding a package

Edit `packages.csv`. Three columns, comma-separated, with a header row:

    tag,name,description

| Tag | Source | `name` |
|-----|--------|--------|
| (blank) | pacman | package name |
| `A` | AUR (yay) | package name |
| `G` | `git clone` to `~/.local/src/<repo>` | clone URL |

Fields must not contain commas. The runner skips the header row and blank
lines.

## Hooks

Drop a script at `hooks/<package>.pre.sh` or `hooks/<package>.post.sh` and it
runs around that package's install step — no CSV plumbing. Both hooks fire on
every `install.sh` run as long as the package is present (or about to be), so
they must be idempotent. For `G` rows, `<package>` is the repo basename
without `.git` (matches `SRC_DIR`).

Hooks run as `bash <path>` with `PKG_NAME`, `PKG_TAG`, `PKG_DESC` exported
(and `SRC_DIR` for `G` rows). Source `../functions.sh` for shared helpers.

## Structure

- `install.sh` — entry point. All stage logic lives here as functions.
- `functions.sh` — shared helpers (`info`, `die`, `pacman_install`,
  `link_dotfile`, …) sourced by `install.sh` and each hook.
- `packages.csv` — package manifest.
- `hooks/` — per-package install hooks, discovered by filename convention
  (`<package>.pre.sh`, `<package>.post.sh`).
- `config/` — dotfiles.
- `vm-*.sh` — helper scripts for QEMU VM workflows.

## License

MIT
