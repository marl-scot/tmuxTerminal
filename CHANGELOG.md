# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

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
