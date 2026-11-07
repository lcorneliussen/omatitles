#!/usr/bin/env bash
# End-to-end tests for omatitles in an omabox box (a private, headless
# Hyprland + Omarchy desktop): real install, real windows, groups and tags read
# back from hyprctl.
#
#   tests/run.sh                            # starts its own box, tears it down afterwards
#   KEEP_BOX=1 tests/run.sh                 # leave the box up to poke at it
#   OMARCHY=~/src/omarchy tests/run.sh      # against an Omarchy checkout instead of the installed one
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOX="omatitles-test-$$"

pass=0
fail=0

ob() { omabox -b "$BOX" "$@"; }

cleanup() {
  if [[ -z "${KEEP_BOX:-}" ]]; then
    ob down >/dev/null 2>&1
  else
    echo "box left up: omabox -b $BOX ..."
  fi
}
trap cleanup EXIT

ok() { pass=$((pass + 1)); echo "  ok   $1"; }
nok() { fail=$((fail + 1)); echo "  FAIL $1"; [[ -n "${2:-}" ]] && echo "       $2"; }
skip() { echo "  skip $1"; }

# Run a check until it succeeds or ~3 s pass (tags and groups land a frame or two late).
eventually() {
  local name="$1"; shift
  local i out
  for i in $(seq 30); do
    if out=$("$@" 2>&1); then
      ok "$name"
      return 0
    fi
    sleep 0.1
  done
  nok "$name" "$out"
  return 1
}

clients() { ob hyprctl -j clients; }
# Windows are foot terminals told apart by app-id; omatitles is set up to match
# the ones starting with "ot".
win() { clients | jq -c --arg c "$1" 'first(.[] | select(.class == $c))'; }

open_term() {
  ob run -d -q --wait -- foot --app-id "$1" >/dev/null 2>&1
  ob wait window "class:^$1\$" >/dev/null
}

# --- checks --------------------------------------------------------------

group_is() {
  local got
  got=$(win "$1" | jq -r '.grouped | length')
  [[ "$got" == "$2" ]] || { echo "group size: want $2, got $got"; return 1; }
}

config_is() {
  local got
  got=$(ob lua "return hl.get_config(\"$1\")")
  [[ "$got" == "$2" ]] || { echo "$1: want $2, got $got"; return 1; }
}

layout_is() {
  local got
  got=$(ob run -- omarchy-hyprland-workspace-layout-current 2>/dev/null)
  [[ "$got" == "$1" ]] || { echo "layout: want $1, got $got"; return 1; }
}

reload() {
  ob hyprctl reload >/dev/null
  ob wait still --quiet 500ms >/dev/null
}

# --- setup ---------------------------------------------------------------

up_args=(--idle 30m)
[[ -n "${OMARCHY:-}" ]] && up_args+=(--omarchy "$OMARCHY")

echo "starting box $BOX"
if ! (cd "$ROOT" && omabox -b "$BOX" up "${up_args[@]}" >/dev/null); then
  echo "could not start an omabox box" >&2
  exit 2
fi
ob ls --json 2>/dev/null | jq -r --arg b "$BOX" \
  '.[] | select(.name == $b) | "omarchy \(.omarchy_version), hyprland \(.hyprland_version)"' 2>/dev/null

echo "retrofit setup"
# Opened before omatitles is loaded: no window rule saw it open.
open_term otEarly

echo "install"
ob run -- "$ROOT/install.sh" >/dev/null && ok "install.sh succeeds" || nok "install.sh succeeds"
ob run -- "$ROOT/install.sh" >/dev/null && ok "install.sh is re-runnable" || nok "install.sh is re-runnable"
home="$(ob path)/home"
conf="$home/.config/hypr/hyprland.lua"
n=$(grep -c 'omatitles/omatitles.lua' "$conf")
[[ "$n" == 1 ]] && ok "loader added exactly once" || nok "loader added exactly once" "found $n"

# A box's Hyprland runs omabox's own config, not ~/.config/hypr/hyprland.lua.
# It does load Omarchy's toggles folder from the box HOME on every reload, so
# the loader install.sh appended goes there -- with the test's window classes.
loader=$(sed -n '/^-- Titlebars showing/,$p' "$conf")
mkdir -p "$home/.local/state/omarchy/toggles/hypr"
printf '%s\n' "$loader" | sed 's/setup({})/setup({ class = "^ot.*" })/' \
  >"$home/.local/state/omarchy/toggles/hypr/omatitles.lua"
reload
errors=$(ob log --grep '^omatitles: ' 2>/dev/null)
[[ -z "$errors" ]] && ok "loader runs setup() without error" || nok "loader runs setup() without error" "$errors"

echo "settings"
eventually "auto_group off" config_is "group:auto_group" false
eventually "middle_click_close off" config_is "group:groupbar:middle_click_close" false
eventually "drag_into_group off" config_is "group:drag_into_group" 0

echo "titlebars"
eventually "a window open before install gets a bar" group_is otEarly 1
open_term otA
eventually "a matching window opens as a group of one" group_is otA 1
open_term plain
eventually "a window that does not match gets none" group_is plain 0
open_term otB
eventually "a second matching window is not pulled into the first" group_is otB 1
ob run -- pkill -f 'app-id plain' >/dev/null 2>&1

echo "a bar taken off stays off"
ob click --window "class:^otB\$" 40 40 >/dev/null 2>&1
ob keys --wait super+g >/dev/null 2>&1
eventually "SUPER+G takes the bar off" group_is otB 0
reload
eventually "  and a reload leaves it off" group_is otB 0
ob keys --wait super+g >/dev/null 2>&1
eventually "  SUPER+G puts it back" group_is otB 1

echo "floating workspaces"
if [[ ! -e "${OMARCHY:-/usr/share/omarchy}/default/hypr/workspace-modes.lua" ]]; then
  skip "no floating workspaces in this Omarchy (< 4.5)"
else
  ob run -- omarchy-hyprland-workspace-layout-toggle back >/dev/null 2>&1
  ob wait still --quiet 1s >/dev/null
  eventually "workspace floats" layout_is floating
  eventually "Omarchy's titlebar takes over (A)" group_is otA 0
  eventually "Omarchy's titlebar takes over (early)" group_is otEarly 0
  open_term otC
  eventually "a window opened on it gets no bar of ours" group_is otC 0
  ob run -- omarchy-hyprland-workspace-layout-toggle >/dev/null 2>&1
  ob wait still --quiet 1s >/dev/null
  eventually "back to tiling" layout_is dwindle
  eventually "bars come back (A)" group_is otA 1
  eventually "bars come back (C)" group_is otC 1
fi

echo
echo "$pass passed, $fail failed"
[[ $fail == 0 ]]
