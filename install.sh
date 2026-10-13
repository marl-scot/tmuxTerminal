#!/usr/bin/env bash
# MIT License - Copyright (c) 2026 Matt Lowe / Marl Scot
#
# tmuxTerminal install.sh — install the .project → tmux window name hook.
#
# On each prompt where the directory changed, the hook finds the nearest
# .project file (current dir or any parent), exports its key=value pairs as
# PROJECT_<KEY> variables and renames the tmux window to PROJECT_NAME.
#
# It also adds an auto-attach block: an interactive SSH login opens the tmux
# session "main" (as a grouped view) instead of a bare shell.
#
# Usage: install.sh [--session NAME] [--no-attach] [rcfile]   (default: ~/.bashrc)
#        ssh HOST 'bash -s' < install.sh
#        ssh HOST 'bash -s -- --no-attach' < install.sh
#   --session NAME  tmux session SSH logins attach to (default: main)
#   --no-attach     leave out the auto-attach block, removing a managed one
# Safe to re-run: the hook file and the auto-attach block are refreshed, the
# source line is added once.
set -euo pipefail

VERSION=1.1.0

HOOK=${PROJECT_HOOK_FILE:-$HOME/.config/bash/project-hook.sh}
MARKER='# project-hook'
ATTACH_BEGIN='# >>> tmuxTerminal auto-attach >>>'
ATTACH_END='# <<< tmuxTerminal auto-attach <<<'

die() { echo "error: $*" >&2; exit 1; }

RC=$HOME/.bashrc
SESSION=main
ATTACH=1
while (( $# )); do
  case $1 in
    --session)   SESSION=${2-}; shift 2 || die "--session needs a name" ;;
    --no-attach) ATTACH=0; shift ;;
    -*)          die "unknown option: $1" ;;
    *)           RC=$1; shift ;;
  esac
done
[[ $SESSION =~ ^[A-Za-z0-9_-]+$ ]] || die "session name must be letters, digits, _ or -"
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

# The rc edits are built up in $rctmp and written back in one go at the end.
rctmp=$(mktemp "${RC}.XXXXXX")
cp "$RC" "$rctmp"
changes=()

# --- 2. source the hook from the rc file (once) ------------------------------
if ! grep -qF "$MARKER" "$rctmp"; then
  line="[[ -f $(printf %q "$HOOK") ]] && source $(printf %q "$HOOK")  $MARKER"
  if grep -q 'atuin init bash' "$rctmp"; then
    # after atuin init, so bash-preexec's precmd_functions already exists
    awk -v l="$line" '{print} /atuin init bash/ && !done {print l; done=1}' "$rctmp" >"$tmp"
    changes+=("hook source line added after 'atuin init bash'")
  else
    { cat "$rctmp"; printf '\n%s\n' "$line"; } >"$tmp"
    changes+=("hook source line added at end")
  fi
  cat "$tmp" >"$rctmp"
fi

# --- 3. SSH auto-attach block (managed, always last in the file) -------------
# Drop any managed block, then re-append the current one. Last in the file so
# the outer login shell has run all of the rc before it starts the tmux server.
had_block=0
grep -qF "$ATTACH_BEGIN" "$rctmp" && had_block=1
if (( had_block )); then
  # Remove the block and the blank lines it leaves at the end of the file, so
  # re-appending it doesn't grow the gap on every run.
  awk -v b="$ATTACH_BEGIN" -v e="$ATTACH_END" '
    $0==b {skip=1} !skip {lines[++n]=$0} $0==e {skip=0}
    END { while (n && lines[n] ~ /^[[:space:]]*$/) n--; for (i=1; i<=n; i++) print lines[i] }
  ' "$rctmp" >"$tmp"
  cat "$tmp" >"$rctmp"
fi

if (( ATTACH )); then
  # Lines of the rc outside the managed block that already start tmux.
  if grep -nE '^[^#]*tmux +(new-session|new|attach|a)\b' "$rctmp" >"$tmp"; then
    echo "note: $RC already starts tmux outside the managed block:" >&2
    sed 's/^/  line /' "$tmp" >&2
    echo "      auto-attach not added; remove those lines and re-run to use it" >&2
  else
    cat >>"$rctmp" <<ATTACH_EOF

$ATTACH_BEGIN
# Managed by tmuxTerminal install.sh; re-run it to update, or with --no-attach
# to remove. An interactive SSH login joins tmux session "$SESSION" as a grouped
# view (shared windows, own current window), creating it if it doesn't exist,
# so a missing session never closes the login. Detaching ends the SSH session.
if [[ \$- == *i* && -n \${SSH_CONNECTION-} && -z \${TMUX-} ]] && command -v tmux >/dev/null; then
    tmux new-session -t $SESSION 2>/dev/null || tmux new-session -s $SESSION && exit
fi
$ATTACH_END
ATTACH_EOF
    (( had_block )) || changes+=("SSH auto-attach block added (session \"$SESSION\")")
  fi
elif (( had_block )); then
  changes+=("SSH auto-attach block removed")
fi

# --- 4. write the rc file back ------------------------------------------------
if cmp -s "$RC" "$rctmp"; then
  echo "$RC already up to date"
  exit 0
fi
bash -n "$rctmp" || die "modified $RC failed syntax check — left unchanged"

backup="$RC.bak.$(date +%Y%m%d-%H%M%S)"
cp -p "$RC" "$backup"
cat "$rctmp" >"$RC"                              # keep original inode/permissions
(( ${#changes[@]} )) || changes+=("SSH auto-attach block updated")
echo "$RC:"
printf '  %s\n' "${changes[@]}"
echo "backup: $backup"
echo "open a new shell (or: source $RC) to activate"
