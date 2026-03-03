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
- Writes run history log with timestamps

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
pkg-maint --config /path/to/config.env --yes
```

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
- If permissions are insufficient for a package install, the script records the failure and continues.

## License

MIT. See `LICENSE`.

## Contributing

See `CONTRIBUTING.md`.
