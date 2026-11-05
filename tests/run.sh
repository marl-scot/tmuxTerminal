#!/usr/bin/env bash
# MIT License - Copyright (c) 2026 Marl Scot
#
# Tests for install.sh and the hook it writes. Everything runs in a temp dir
# and on a private tmux server socket, so nothing real is touched.
set -uo pipefail

ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d)
SOCK=tmuxterminal-test-$$
trap 'tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
export PROJECT_HOOK_FILE=$WORK/hook.sh PROJECT_HOOK_FORCE=1
export TMUXTERMINAL_TMUX_CONF=$WORK/tmux.conf   # never touch the real config
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

# --- auto-attach block --------------------------------------------------------
BEGIN='# >>> tmuxTerminal auto-attach >>>'
check "attach block added once" 1 "$(grep -cF "$BEGIN" "$WORK/rc-plain")"
check "attach block is last" "# <<< tmuxTerminal auto-attach <<<" "$(tail -1 "$WORK/rc-plain")"
check "re-run leaves rc unchanged" "$WORK/rc-plain already up to date" \
    "$("$ROOT/install.sh" "$WORK/rc-plain" | tail -1)"

"$ROOT/install.sh" --session work "$WORK/rc-plain" >/dev/null
check "--session replaces the block" "1 1" \
    "$(grep -cF "$BEGIN" "$WORK/rc-plain") $(grep -c 'new-session -t work' "$WORK/rc-plain")"
"$ROOT/install.sh" --no-attach "$WORK/rc-plain" >/dev/null
check "--no-attach removes the block" 0 "$(grep -cF "$BEGIN" "$WORK/rc-plain")"
check "--no-attach keeps the hook line" 1 "$(grep -c '# project-hook' "$WORK/rc-plain")"

printf 'if true; then\n    tmux new-session -t main\n    exit\nfi\n' >"$WORK/rc-own"
"$ROOT/install.sh" "$WORK/rc-own" >/dev/null 2>&1
check "existing tmux start: block not added" 0 "$(grep -cF "$BEGIN" "$WORK/rc-own")"

# Run the block in an interactive shell with a stub tmux that logs its calls.
# STUB_JOIN=group: no base session but its group exists (has-session fails).
# STUB_JOIN=fail: neither exists (has-session and joining the group both fail).
mkdir -p "$WORK/bin"
cat >"$WORK/bin/tmux" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_LOG"
[[ $1 == has-session && ${STUB_JOIN-} != ok ]] && exit 1
[[ "$*" == "new-session -d -t "* && ${STUB_JOIN-} == fail ]] && exit 1
exit 0
STUB
chmod +x "$WORK/bin/tmux"
sed -n "/^$BEGIN\$/,\$p" "$WORK/rc-atuin" >"$WORK/rc-block"
attach() {   # attach SSH_CONNECTION STUB_JOIN — prints tmux calls, then the shell's fate
    : >"$WORK/stub.log"
    env -i HOME="$HOME" PATH="$WORK/bin:/usr/bin:/bin" STUB_LOG="$WORK/stub.log" \
        SSH_CONNECTION="$1" STUB_JOIN="$2" \
        bash --rcfile "$WORK/rc-block" -i <<<'echo still-here' 2>/dev/null |
        grep -o still-here || echo exited
    tr '\n' ';' <"$WORK/stub.log"
}
JOIN='new-session -t main ; set-option destroy-unattached on;'
check "ssh: joins session, exits on detach" "exited has-session -t =main;$JOIN" \
    "$(attach '10.0.0.1 1 10.0.0.2 22' ok | tr '\n' ' ')"
check "ssh: base session added to existing group" \
    "exited has-session -t =main;new-session -d -t main -s main;$JOIN" \
    "$(attach '10.0.0.1 1 10.0.0.2 22' group | tr '\n' ' ')"
check "ssh: missing session is created" \
    "exited has-session -t =main;new-session -d -t main -s main;new-session -d -s main;$JOIN" \
    "$(attach '10.0.0.1 1 10.0.0.2 22' fail | tr '\n' ' ')"
check "local login: tmux not started" "still-here " \
    "$(attach '' ok | tr '\n' ' ')"

# --- tmux config block ------------------------------------------------------------
CB='# >>> tmuxTerminal >>>'
printf 'echo x\n' >"$WORK/rc-conf"
rm -f "$TMUXTERMINAL_TMUX_CONF"
"$ROOT/install.sh" "$WORK/rc-conf" >/dev/null
check "tmux.conf created with block" "$CB" "$(head -1 "$TMUXTERMINAL_TMUX_CONF")"
check "block sets the title string" 1 "$(grep -c '^set -g set-titles-string "#S / #I:#W"$' "$TMUXTERMINAL_TMUX_CONF")"
check "tmux accepts the block" 0 \
    "$(tmux -L "$SOCK-conf" -f "$TMUXTERMINAL_TMUX_CONF" new-session -d 2>&1 | wc -l | tr -d ' '; tmux -L "$SOCK-conf" kill-server 2>/dev/null)"

printf '\n# mine\nset -g history-limit 5000\n' >"$TMUXTERMINAL_TMUX_CONF"
"$ROOT/install.sh" "$WORK/rc-conf" >/dev/null
check "existing tmux.conf: block goes first" "$CB" "$(head -1 "$TMUXTERMINAL_TMUX_CONF")"
check "existing tmux.conf: own lines kept, after a blank line" "|# mine|set -g history-limit 5000" \
    "$(sed -n '/^# <<< tmuxTerminal <<<$/,$p' "$TMUXTERMINAL_TMUX_CONF" | tail -n +2 | tr '\n' '|' | sed 's/|$//')"
cp "$TMUXTERMINAL_TMUX_CONF" "$WORK/conf-before"
check "re-run: tmux.conf unchanged" "$TMUXTERMINAL_TMUX_CONF already up to date" \
    "$("$ROOT/install.sh" "$WORK/rc-conf" | grep tmux.conf)"
check "re-run: block once" 1 "$(grep -cF "$CB" "$TMUXTERMINAL_TMUX_CONF")"
"$ROOT/install.sh" --no-tmux-conf "$WORK/rc-conf" >/dev/null
check "--no-tmux-conf removes the block" "# mine|set -g history-limit 5000" \
    "$(tr '\n' '|' <"$TMUXTERMINAL_TMUX_CONF" | sed 's/|$//')"
rm -f "$TMUXTERMINAL_TMUX_CONF"
"$ROOT/install.sh" --no-tmux-conf "$WORK/rc-conf" >/dev/null
check "--no-tmux-conf, no file: none created" no "$([[ -e $TMUXTERMINAL_TMUX_CONF ]] && echo yes || echo no)"
"$ROOT/install.sh" "$WORK/rc-conf" >/dev/null   # leave a config for later tests

# --- tmux missing ------------------------------------------------------------------
# A stub pkg-install logs its arguments and whether stdin is /dev/null.
mkdir -p "$WORK/pkgbin"
cat >"$WORK/pkgbin/pkg-install" <<'STUB'
#!/usr/bin/env bash
read -r -t 0.1 line && echo "stdin: $line" >>"$PKG_LOG"
echo "pkg-install $*" >>"$PKG_LOG"
exit "${PKG_STATUS:-0}"
STUB
chmod +x "$WORK/pkgbin/pkg-install"
missing() {   # missing PATH STATUS [args]: run install.sh with tmux missing
    local path=$1 status=$2; shift 2
    : >"$WORK/pkg.log"
    echo 'more script' | TMUXTERMINAL_TMUX=no-such-tmux PATH="$path" PKG_LOG="$WORK/pkg.log" \
        PKG_STATUS=$status "$ROOT/install.sh" "$@" "$WORK/rc-conf" >/dev/null 2>"$WORK/pkg.err"
    echo "$? $(tr '\n' ';' <"$WORK/pkg.log")"
}
check "no tmux: pkg-install asked, stdin not passed" "0 pkg-install tmux;" "$(missing "$WORK/pkgbin:$PATH" 0)"
check "no tmux: --yes passed on" "0 pkg-install --yes tmux;" "$(missing "$WORK/pkgbin:$PATH" 0 --yes)"
check "no tmux: declined stops the install" "1 pkg-install tmux;" "$(missing "$WORK/pkgbin:$PATH" 1)"
check "no tmux, no pkg-install: error names pkgInstall" "1 1" \
    "$(missing /usr/bin:/bin 0 | cut -c1) $(grep -c 'github.com/marl-scot/pkgInstall' "$WORK/pkg.err")"

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
