# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

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
