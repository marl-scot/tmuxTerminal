#!/usr/bin/env bash
# MIT License - Copyright (c) 2026 Matt Lowe / Marl Scot
#
# Tests for install.sh and the hook it writes. Everything runs in a temp dir
# and on a private tmux server socket, so nothing real is touched.
set -uo pipefail

ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d)
SOCK=tmuxterminal-test-$$
trap 'tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
export PROJECT_HOOK_FILE=$WORK/hook.sh PROJECT_HOOK_FORCE=1
fails=0

check() {   # check NAME EXPECTED ACTUAL
    if [[ $2 == "$3" ]]; then echo "ok   - $1"
    else echo "FAIL - $1: expected [$2] got [$3]"; fails=$((fails + 1)); fi
}

# --- installer ---------------------------------------------------------------
printf 'echo plain >/dev/null\n' >"$WORK/rc-plain"
"$ROOT/install.sh" "$WORK/rc-plain" >/dev/null
"$ROOT/install.sh" "$WORK/rc-plain" >/dev/null
check "plain rc: source line added once" 1 "$(grep -c '# project-hook' "$WORK/rc-plain")"

printf 'a=1\neval "$(atuin init bash)"\nb=2\n' >"$WORK/rc-atuin"
"$ROOT/install.sh" "$WORK/rc-atuin" >/dev/null
check "atuin rc: source line follows atuin init" "# project-hook" \
    "$(sed -n 3p "$WORK/rc-atuin" | grep -o '# project-hook')"
check "hook file passes bash -n" 0 "$(bash -n "$PROJECT_HOOK_FILE"; echo $?)"

# --- parser ------------------------------------------------------------------
mkdir -p "$WORK/proj/sub" "$WORK/bare" "$WORK/unnamed"
printf '# comment\n  name = my.app  \n  # indented comment\nvenv = ".venv"\nbad key = x\r\n' \
    >"$WORK/proj/.project"
printf 'barename\n' >"$WORK/bare/.project"
: >"$WORK/unnamed/.project"

parse() {   # parse DIR VAR — value of VAR after the hook runs in DIR
    (unset TMUX; cd "$1" && source "$PROJECT_HOOK_FILE" 2>/dev/null; __proj_hook; printf '%s' "${!2-}")
}
check "name from key, trimmed"     "my.app"     "$(parse "$WORK/proj/sub" PROJECT_NAME)"
check "quoted value unquoted"      ".venv"      "$(parse "$WORK/proj/sub" PROJECT_VENV)"
check "root is the .project dir"   "$WORK/proj" "$(parse "$WORK/proj/sub" PROJECT_ROOT)"
check "bare line is the name"      "barename"   "$(parse "$WORK/bare" PROJECT_NAME)"
check "empty file uses dir name"   "unnamed"    "$(parse "$WORK/unnamed" PROJECT_NAME)"
check "no .project, no vars"       ""           "$(parse "$WORK" PROJECT_NAME)"

# --- tmux --------------------------------------------------------------------
if command -v tmux >/dev/null; then
    tmux -L "$SOCK" new-session -d -s t -c "$WORK/proj/sub" \
        "bash --norc -c 'source $PROJECT_HOOK_FILE; __proj_hook; sleep 3'"
    tmux -L "$SOCK" new-window -d -t t -c "$WORK/proj/sub" \
        "bash --norc -c 'source $PROJECT_HOOK_FILE; __proj_hook; cd /; __proj_hook; sleep 3'"
    sleep 1
    check "window renamed in project" "my.app" "$(tmux -L "$SOCK" display -p -t t:0 '#W')"
    check "window option @project_root" "$WORK/proj" "$(tmux -L "$SOCK" display -p -t t:0 '#{@project_root}')"
    check "leaving restores automatic-rename" 1 "$(tmux -L "$SOCK" display -p -t t:1 '#{automatic-rename}')"
else
    echo "skip - tmux not installed"
fi

echo
(( fails == 0 )) && echo "all tests passed" || echo "$fails test(s) failed"
exit $(( fails > 0 ))
