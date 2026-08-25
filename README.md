# pkg-maint

Linux-native updater for non-APT global packages (`pip` + `uv tool` + `npm`) with an APT-style interactive confirmation flow.

## Project Status

`pkg-maint` is stable for small personal and workstation use. The project is intentionally small, shell-based, and conservative in scope.

## Features

- Lists global outdated packages from `pip`, `uv tool`, and `npm`
- Prompts before install by default (`Proceed with install? [y/N]`)
- Supports non-interactive mode with `--yes`
- Supports check-only mode with exit code `2` when updates are available
- Supports package hold/exclude lists
- Shows scan commands, active npm prefix, and package counts with `--verbose`
- Warns when inactive NVM prefixes contain global packages missing from the active prefix
- Migrates missing global packages from inactive NVM versions into the active version with preview and confirmation
- Logs run start, per-manager scan results, installs, failures, and run completion
- Treats unavailable managers and partial scans as errors instead of reporting a clean result

## Files in this repo

- `bin/pkg-maint`: executable script
- `config/config.env.example`: config template
- `man/pkg-maint.1`: manual page

## Install

Using make:

```sh
make install
```

After changing or pulling new versions of this repo, rerun:

```sh
make install
```

This refreshes the installed binary and man page. Your existing `~/.config/pkg-maint/config.env` is kept in place.

If `~/.local/bin` is not in your `PATH`:

```sh
make setup-path
```

Alternative (system-wide binary location already on PATH):

```sh
sudo make install BINDIR=/usr/local/bin
```

Manual install:

```sh
mkdir -p ~/.local/bin ~/.config/pkg-maint ~/.local/share/man/man1
install -m 0755 bin/pkg-maint ~/.local/bin/pkg-maint
install -m 0644 config/config.env.example ~/.config/pkg-maint/config.env
install -m 0644 man/pkg-maint.1 ~/.local/share/man/man1/pkg-maint.1
```

Optional if you already have a config:

```sh
install -m 0644 config/config.env.example ~/.config/pkg-maint/config.env.new
```

## Tests

Run the local regression suite:

```sh
make test
```

## Usage

```sh
pkg-maint --check
pkg-maint
pkg-maint --yes
pkg-maint --manager pip --check
pkg-maint --manager uv --check
pkg-maint --manager npm --check --verbose
pkg-maint --migrate-nvm --check
pkg-maint --migrate-nvm
pkg-maint --migrate-nvm --yes
pkg-maint --migrate-nvm-from v24.12.0 --check
pkg-maint --config /path/to/config.env --yes
```

## NVM package migration

`pkg-maint --migrate-nvm` discovers the active npm prefix and inactive NVM versions automatically. If exactly one inactive version contains packages missing from the active prefix, it is selected automatically. Multiple possible sources are shown in a numbered menu.

Use `--check` for a non-mutating preview. It returns exit code `2` when migration is available. Use `--yes` for unattended migration only when the source is unambiguous; otherwise select it explicitly with `--migrate-nvm-from <version>`. Because the normal update scan follows a successful migration, `--yes` also approves any subsequently detected package updates.

Only packages absent from the active prefix are installed, using the exact source version. Existing target packages are never downgraded. After successful migration, the normal scan can offer newer package versions. The inactive source environment is retained, and linked global packages cause migration to stop before changes are made.

## Example config

```sh
PIP_EXCLUDE="awscli"
UV_EXCLUDE="ruff"
NPM_EXCLUDE="npm"
PIP_CMD="python3 -m pip"
UV_CMD="uv"
NPM_CMD="npm"
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/pkg-maint/history.log"
```

## Notes

- Script scope is global package installs only (`pip`, `uv tool`, and global `npm`).
- APT packages are not scanned or installed.
- npm operations use only the active npm prefix. Inactive NVM prefixes are inspected locally and are modified only when an explicit migration command is confirmed.
- If permissions are insufficient for a package install, the script records the failure and continues.
- The tab-separated history log keeps six columns: timestamp, event/manager, subject/package, old version, new version, and result. Operational rows use `run` or `scan` in the second column.

## License

MIT. See `LICENSE`.

## Contributing

See `CONTRIBUTING.md`.

## Code of Conduct

See `CODE_OF_CONDUCT.md`.
