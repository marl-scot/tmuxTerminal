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

### Keys other tools read

The hook exports any key, so other tools keep their settings in the same file.
They follow the parsing rules above (this hook is the reference):

| Key | Read by | Meaning |
|---|---|---|
| `language` | the Claude standards detector, `setupCi` | which language standards apply: `python`, `rust`, `go`, `php`, `powershell`, `shell` |
| `release` | `setupCi` | what a release builds: `rust`, `go`, `python`, `powershell`, `docker`, `none` |
| `dockerfile`, `image` | `setupCi` | the Dockerfile to build and the registry image name |
| `archived`, `archived_from`, `archived_reason`, `archived_host`, `unarchived` | projectArchive | where an archived project came from |

Because `#` only starts a comment at the beginning of a line, a comment after a
value becomes part of it: write `language = python`, not
`language = python  # standards`.

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

## tmux settings

The installer also puts a managed block of settings at the **top** of the tmux
config, so your own settings further down the file override it:

```tmux
# >>> tmuxTerminal >>>
set -g mouse on                 # scroll, select and resize with the mouse
set -g allow-passthrough on     # let escape sequences reach the outer terminal
set -g set-titles on            # outer terminal tab title: session / num:window
set -g set-titles-string "#S / #I:#W"
# <<< tmuxTerminal <<<
```

`set-titles` makes your terminal emulator's tab title follow tmux, e.g.
`main / 2:documentationServer`, so the project name from `.project` shows on
the tab.

- The config is `~/.tmux.conf`, or `~/.config/tmux/tmux.conf` if only that
  exists. If neither does, `~/.tmux.conf` is created holding just the block.
- The rest of the file is left as it is. A changed file gets a timestamped
  backup (`~/.tmux.conf.bak.YYYYMMDD-HHMMSS`), and a running tmux server
  reloads it.
- `--no-tmux-conf` leaves the block out, removing an installed one.

## SSH auto-attach

By default the installer also adds this block to the **end** of the rc file:

```bash
# >>> tmuxTerminal auto-attach >>>
if [[ $- == *i* && -n ${SSH_CONNECTION-} && -z ${TMUX-} ]] && command -v tmux >/dev/null; then
    tmux has-session -t "=main" 2>/dev/null ||
        tmux new-session -d -t main -s main 2>/dev/null ||
        tmux new-session -d -s main
    tmux new-session -t main \; set-option destroy-unattached on && exit
fi
# <<< tmuxTerminal auto-attach <<<
```

An interactive SSH login then opens tmux instead of a bare shell:

- A detached **base** session `main` holds the windows. If it is missing it is
  created, joining an existing `main` session group if there is one so the
  windows carry over.
- `new-session -t main` then joins it as a **grouped** session. It shares
  main's windows, but each login has its own current window, so two terminals
  can look at different windows.
- Each login's session has `destroy-unattached on`, so it is removed as soon as
  its client goes, whether you detach or the connection drops. Without this,
  every dropped SSH connection left a stale `main-N` session behind. The base
  session is never attached, so it (and your windows) stays. `tmux ls`
  therefore always shows a detached `main`; that is expected.
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
| `--no-tmux-conf` | no tmux settings block; removes a managed one |
| `--yes` | install tmux, if it's missing, without asking |
| `RCFILE` | rc file to change (default `~/.bashrc`) |

tmux must be installed. If it isn't, the installer runs
[pkg-install](https://github.com/marl-scot/pkgInstall) to install it with the
system's package manager, asking first. If `pkg-install` isn't on `PATH` it stops
and says how to get it; on a remote host without either, run
`ssh -t HOST 'bash -s -- tmux' < pkg-install` first.

On another server, without cloning:

```bash
ssh -t HOST 'bash -s' < install.sh                 # -t so it can ask about tmux
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
| `TMUXTERMINAL_TMUX_CONF` | tmux config to change instead of `~/.tmux.conf` (used by the tests; no reload) |

### Uninstalling

Run `./install.sh --no-attach --no-tmux-conf` to remove both managed blocks, then delete the
line ending in `# project-hook` from `~/.bashrc` and remove
`~/.config/bash/project-hook.sh`.

## Requirements

- bash 4.0 or later
- tmux (the installer installs it via
  [pkg-install](https://github.com/marl-scot/pkgInstall) if it's missing)

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
