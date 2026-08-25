# Changelog

All notable changes to `pkg-maint` will be documented in this file.

## [Unreleased]

### Added
- Verbose scan diagnostics with active npm prefix and package counts
- Local detection of packages stranded in inactive NVM prefixes
- Run-start, per-manager scan, and run-completion history events
- Automatic NVM package migration with preview, confirmation, explicit source selection, and post-install verification

### Changed
- Missing managers and partial uv tool scans now return failure instead of allowing a false clean result
- No-update output now states that selected managers are non-APT
- NVM migration installs only packages missing from the active prefix and preserves inactive source environments

## [0.1.0] - 2026-03-03

### Added
- Initial public release of `pkg-maint`
- Interactive updates for global `pip`, `uv tool`, and `npm` packages
- `--check`, `--yes`, `--manager`, `--config`, and `--verbose` CLI options
- Hold lists via `PIP_EXCLUDE`, `UV_EXCLUDE`, and `NPM_EXCLUDE`
- Install helpers via `make install`, `make setup-path`, and `make test`
- Local regression test suite and GitHub Actions CI
