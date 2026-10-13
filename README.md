# tmuxTerminal

Name tmux windows (tabs) after the project you are in, automatically.

Drop a `.project` file in a project's root folder. Whenever a bash prompt
appears in a new directory, a small hook finds the nearest `.project` file
(the current directory or any parent), renames the tmux window to the
project's name and exports every value in the file for other scripts to use.
No more renaming tabs by hand, or forgetting to after moving to another
project.

The installer can also make SSH logins open straight into tmux; see
[SSH auto-attach](#ssh-auto-attach).

## The `.project` file

```ini
# Comments and blank lines are ignored.
name = atuin-server
venv = .venv
deploy_host = dev.example.com
```

| Line | Becomes |
|---|---|
| `name = my-app` | `$PROJECT_NAME`, and the tmux window name |
| `any_key = value` | `$PROJECT_ANY_KEY` (key upper-cased; letters, digits and `_` only) |
| `my-app` (a bare line) | the name, if no `name =` line came first |

- `$PROJECT_ROOT` is always set to the folder holding `.project`.
- With no name at all, the folder name is used, so an empty `.project` works.
- Values may be wrapped in `"…"` or `'…'`. A `#` only starts a comment at the
  beginning of a line.
- The file is **parsed, never sourced**, so a `.project` in a cloned repository
  cannot run code.

## How it works

`install.sh` writes the hook to `~/.config/bash/project-hook.sh` and adds one
line to `~/.bashrc` that sources it. The hook registers itself to run before
every prompt:

- With atuin (or anything else that loads bash-preexec), it joins
  `precmd_functions`. The source line is placed just after
  `eval "$(atuin init bash)"` so that array already exists.
- Without it, it is prepended to `PROMPT_COMMAND`. `$?` in your prompt is
  unaffected.

On each prompt the hook does nothing unless the directory changed. When it has:

1. It walks up from `$PWD` to the nearest `.project`.
2. It clears the previous project's `PROJECT_*` variables and exports the new
   ones.
3. Inside tmux, it renames the window its own pane is in (via `$TMUX_PANE`,
   so a shell in a background window renames that window, not the one you are
   looking at) and sets the window option `@project_root`.
4. When you leave a project, it turns tmux's `automatic-rename` back on for
   windows it renamed, so the tab returns to showing the running command.
   Windows you named by hand are left alone.

`#{@project_root}` can be used in tmux formats, e.g. the status line.

To have your terminal emulator's own tab title follow the window name, add to
`~/.tmux.conf`:

```
set -g set-titles on
set -g set-titles-string '#W'
```

## SSH auto-attach

By default the installer also adds this block to the **end** of the rc file:

```bash
# >>> tmuxTerminal auto-attach >>>
if [[ $- == *i* && -n ${SSH_CONNECTION-} && -z ${TMUX-} ]] && command -v tmux >/dev/null; then
    tmux new-session -t main 2>/dev/null || tmux new-session -s main && exit
fi
# <<< tmuxTerminal auto-attach <<<
```

An interactive SSH login then opens tmux instead of a bare shell:

- `new-session -t main` joins the session (or session group) `main` as a
  **grouped** session. It shares main's windows, but each login has its own
  current window, so two terminals can look at different windows.
- If `main` doesn't exist yet, it is created. Without this fallback a fresh
  server would close every SSH login straight away.
- Detaching (`prefix d`) ends the SSH session too.
- Local logins, non-interactive SSH (`scp`, `ssh host cmd`) and shells already
  inside tmux are left alone.

The block goes last so the outer login shell has run all of the rc before it
starts the tmux server, whose environment new windows inherit.

Re-running the installer replaces the block, so it can be changed later:

```bash
./install.sh --session work  # attach to "work" instead of "main"
./install.sh --no-attach     # leave the block out, removing an installed one
```

If the rc file already starts tmux outside the managed block, the installer
doesn't add a second one. It prints the lines it found; delete them and re-run
to switch to the managed block.

## Installation

```bash
./install.sh                 # into ~/.bashrc
./install.sh ~/.bashrc.local # into another rc file
```

| Option | Effect |
|---|---|
| `--session NAME` | tmux session SSH logins attach to (default `main`) |
| `--no-attach` | no SSH auto-attach block; removes a managed one |
| `RCFILE` | rc file to change (default `~/.bashrc`) |

On another server, without cloning:

```bash
ssh HOST 'bash -s' < install.sh
ssh HOST 'bash -s -- --no-attach' < install.sh   # with options
# or, on the server itself
curl -fsSL https://raw.githubusercontent.com/marl-scot/tmuxTerminal/main/install.sh | bash
```

The installer is safe to re-run: it always rewrites the hook file (so
re-running upgrades it) and the auto-attach block, but adds the hook's source
line only once. If nothing changed it leaves the rc file alone. Otherwise it
syntax-checks the result first and keeps a timestamped backup
(`~/.bashrc.bak.YYYYMMDD-HHMMSS`).

Open a new shell, or `source ~/.bashrc`, to activate it.

| Variable | Effect |
|---|---|
| `PROJECT_HOOK_FILE` | where the hook is written (default `~/.config/bash/project-hook.sh`) |
| `PROJECT_HOOK_FORCE=1` | load the hook in non-interactive shells too (used by the tests) |

### Uninstalling

Run `./install.sh --no-attach` to remove the auto-attach block, then delete the
line ending in `# project-hook` from `~/.bashrc` and remove
`~/.config/bash/project-hook.sh`.

## Requirements

- bash 4.0 or later
- tmux, for the window renaming (the variables are exported without it)

No other dependencies.

## Tests

```bash
tests/run.sh
```

Runs the installer against throwaway rc files, checks the parser, checks
window renaming on a private tmux server socket, and runs the auto-attach
block against a stub `tmux`. Nothing real is touched.

## Licence

MIT. See [LICENSE](LICENSE).
