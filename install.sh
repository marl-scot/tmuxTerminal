#!/usr/bin/env bash
# MIT License - Copyright (c) 2026 Matt Lowe / Marl Scot
#
# tmuxTerminal install.sh — install the .project → tmux window name hook.
#
# On each prompt where the directory changed, the hook finds the nearest
# .project file (current dir or any parent), exports its key=value pairs as
# PROJECT_<KEY> variables and renames the tmux window to PROJECT_NAME.
#
# Usage: install.sh [rcfile]     (default: ~/.bashrc)
#        ssh HOST 'bash -s' < install.sh
# Safe to re-run: the hook file is refreshed, the rc line is added once.
set -euo pipefail

VERSION=1.0.0

RC=${1:-$HOME/.bashrc}
HOOK=${PROJECT_HOOK_FILE:-$HOME/.config/bash/project-hook.sh}
MARKER='# project-hook'

die() { echo "error: $*" >&2; exit 1; }
[[ -f $RC ]] || die "$RC not found"

# --- 1. write the hook file -------------------------------------------------
mkdir -p "${HOOK%/*}"
tmp=$(mktemp "${HOOK}.XXXXXX")
trap 'rm -f "$tmp" "${rctmp-}"' EXIT
{ echo "# project-hook $VERSION — managed by tmuxTerminal install.sh; re-run it to update."
  cat <<'HOOK_EOF'
# MIT License - Copyright (c) 2026 Matt Lowe / Marl Scot
#
# .project format (comments and blank lines ignored, file is parsed not sourced):
#   name = my-app          -> $PROJECT_NAME, also the tmux window name
#   any_key = value        -> $PROJECT_ANY_KEY
#   my-app                 -> a bare line is taken as the name
# Also exported: $PROJECT_ROOT. tmux window option: #{@project_root}.
# Interactive shells only; PROJECT_HOOK_FORCE=1 loads it in scripts and tests.
[[ $- == *i* || -n ${PROJECT_HOOK_FORCE-} ]] || return 0

__proj_last_pwd=
__proj_hook() {
  [[ $PWD == "$__proj_last_pwd" ]] && return
  __proj_last_pwd=$PWD
  local d=$PWD f=
  while [[ -n $d ]]; do                           # walk up to the nearest .project
    [[ -f $d/.project ]] && { f=$d/.project; break; }
    d=${d%/*}
  done
  unset "${!PROJECT_@}"                           # drop the previous project's vars
  if [[ -z $f ]]; then                            # left a project: hand name back to tmux
    [[ -n ${TMUX-} && -n $(tmux show-options -wqv -t "$TMUX_PANE" @project_root 2>/dev/null) ]] &&
      tmux set-option -wu -t "$TMUX_PANE" @project_root \; set-option -w -t "$TMUX_PANE" automatic-rename on
    return
  fi
  export PROJECT_ROOT=${f%/*}
  local line k v
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    line=${line#"${line%%[![:space:]]*}"}; line=${line%"${line##*[![:space:]]}"}
    [[ -z $line || $line == '#'* ]] && continue
    if [[ $line != *=* ]]; then
      [[ -n ${PROJECT_NAME-} ]] || export PROJECT_NAME=$line
      continue
    fi
    k=${line%%=*}; v=${line#*=}
    k=${k//[[:space:]]/}; k=${k^^}
    [[ $k =~ ^[A-Z0-9_]+$ ]] || continue
    v=${v#"${v%%[![:space:]]*}"}
    [[ $v == \"*\" || $v == \'*\' ]] && v=${v:1:-1}
    export "PROJECT_$k=$v"
  done < "$f"
  : "${PROJECT_NAME:=${PROJECT_ROOT##*/}}"
  export PROJECT_NAME
  [[ -n ${TMUX-} ]] || return
  tmux rename-window -t "$TMUX_PANE" -- "$PROJECT_NAME" \; \
       set-option -w -t "$TMUX_PANE" @project_root "$PROJECT_ROOT" 2>/dev/null
}

if declare -p precmd_functions &>/dev/null; then
  [[ " ${precmd_functions[*]} " == *" __proj_hook "* ]] || precmd_functions+=(__proj_hook)
elif [[ ${PROMPT_COMMAND-} != *__proj_hook* ]]; then
  PROMPT_COMMAND="__proj_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
HOOK_EOF
} >"$tmp"
bash -n "$tmp" || die "generated hook failed syntax check"
chmod 644 "$tmp"
mv "$tmp" "$HOOK"
echo "hook $VERSION written: $HOOK"

# --- 2. source it from the rc file (once) -----------------------------------
if grep -qF "$MARKER" "$RC"; then
  echo "already sourced from $RC — nothing to change"
  exit 0
fi

line="[[ -f $(printf %q "$HOOK") ]] && source $(printf %q "$HOOK")  $MARKER"
rctmp=$(mktemp "${RC}.XXXXXX")
if grep -q 'atuin init bash' "$RC"; then
  # after atuin init, so bash-preexec's precmd_functions already exists
  awk -v l="$line" '{print} /atuin init bash/ && !done {print l; done=1}' "$RC" >"$rctmp"
  where="after 'atuin init bash'"
else
  { cat "$RC"; printf '\n%s\n' "$line"; } >"$rctmp"
  where="at end"
fi
bash -n "$rctmp" || die "modified $RC failed syntax check — left unchanged"

backup="$RC.bak.$(date +%Y%m%d-%H%M%S)"
cp -p "$RC" "$backup"
cat "$rctmp" >"$RC"                              # keep original inode/permissions
echo "source line added to $RC ($where); backup: $backup"
echo "open a new shell (or: source $RC) to activate"
