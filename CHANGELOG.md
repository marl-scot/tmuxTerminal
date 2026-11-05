# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

## [1.1.4] - 2026-11-05

### Added

- Managed tmux settings block at the top of `~/.tmux.conf` (or
  `~/.config/tmux/tmux.conf`): `mouse on`, `allow-passthrough on`, and
  `set-titles` with `"#S / #I:#W"` so the terminal tab shows session, window
  number and name. The file is created if missing; your own lines are kept and
  override the block. `--no-tmux-conf` removes it.
- tmux check: if tmux isn't installed the installer runs `pkg-install tmux`
  (marl-scot/pkgInstall), which asks first; `--yes` skips the question.
  Without pkg-install it stops and says how to get it.

### Changed

- tmux is now required by the installer (the hook itself still works without
  it).

## [1.1.3] - 2026-11-05

### Fixed

- SSH auto-attach no longer leaves a stale `main-N` session behind for every
  dropped connection. A detached base session now holds the windows and each
  login's grouped session sets `destroy-unattached on`, so it is removed when
  its client goes. Works on tmux 3.3 (no `keep-group` needed). Re-run the
  installer to update the block.

## [1.1.2] - 2026-10-21

### Changed

- README lists the `.project` keys other tools read (`language`, `release`,
  `dockerfile`, `image`, projectArchive's `archived*`).

## [1.1.1] - 2026-10-13

### Changed

- Copyright holder in `LICENSE` and file headers is now Marl Scot.

## [1.1.0] - 2026-10-13

### Added

- SSH auto-attach: the installer adds a managed block to the end of the rc
  file so an interactive SSH login joins tmux session `main` as a grouped
  session, and ends when you detach.
- If the session doesn't exist it is created. Without this, a fresh server
  would close every SSH login straight away.
- `--session NAME` picks the session and `--no-attach` leaves the block out
  (removing an installed one). Re-running the installer refreshes the block.
- If the rc file already starts tmux, the installer reports it and doesn't add
  a second auto-attach.
- `PROJECT_HOOK_FORCE=1` loads the hook in non-interactive shells (for tests).

### Changed

- The rc file is only rewritten (and backed up) when something actually
  changed.

## [1.0.0] - 2026-10-13

### Added

- `install.sh`: installs a bash hook that reads the nearest `.project` file on
  each directory change, exports its values as `PROJECT_*` variables and
  renames the tmux window to the project name.
- Works with or without atuin / bash-preexec: joins `precmd_functions` when
  present, otherwise `PROMPT_COMMAND`.
- Leaving a project hands the window name back to tmux's `automatic-rename`.
- Idempotent installer with rc-file backup and syntax checks.
- `tests/run.sh` test suite.
