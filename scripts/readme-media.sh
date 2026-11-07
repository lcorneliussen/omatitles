#!/usr/bin/env bash
# Produce the README's images - docs/media/*.{png,gif} - from a scripted run in
# a contained Omarchy desktop (omabox), never from the author's own session.
#
# Window titles are staged with `ghostty --title`: an agent session summary and
# two herdr sessions on an invented host, so nothing real can appear in a
# published image. Rerun it after a visual change.
#
#   scripts/readme-media.sh [--keep]     --keep leaves the box up for poking at
#
# Needs omabox, ffmpeg and ghostty. The floating-workspace frames need
# Omarchy 4.5+ (omarchy-hyprland-titlebars).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=$ROOT/docs/media
BOX=omatitles-readme
FRAMES=$(mktemp -d)
KEEP=${1:-}
trap '[ "$KEEP" = "--keep" ] || omabox -b "$BOX" down >/dev/null 2>&1 || true; rm -rf "$FRAMES"' EXIT

for c in omabox ffmpeg ghostty; do
  command -v $c >/dev/null || { echo "$c is required" >&2; exit 1; }
done
mkdir -p "$OUT"

ob() { omabox -b "$BOX" "$@"; }
settle() { ob wait still --quiet 400ms --timeout 8 >/dev/null 2>&1 || true; }
# The pointer waits on an empty stretch of the top bar, over no window, so
# focus-follows-mouse leaves focus where the keys put it.
shot() { ob pointer -- move 700 4 >/dev/null 2>&1; settle; ob shot -o "$1" >/dev/null 2>&1; }
theme() { ob run -- omarchy-theme-set "$1" >/dev/null 2>&1; settle; }

# frames to a GIF: gif OUT WIDTH FILE:SECONDS...
gif() {
  local out=$1 w=$2 list=$FRAMES/list.txt fd; shift 2
  : > "$list"
  for fd in "$@"; do printf "file '%s'\nduration %s\n" "${fd%%:*}" "${fd##*:}" >> "$list"; done
  printf "file '%s'\n" "${fd%%:*}" >> "$list"   # concat drops the last duration otherwise
  ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" -fps_mode vfr -vf \
    "scale=$w:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=full[p];[b][p]paletteuse=dither=none" \
    "$out"
}

# A terminal with a fixed title, in its own app-id, sitting in an invented project dir.
term() {
  local class=$1 title=$2 dir=$3
  mkdir -p "$H/projects/$dir"
  ob run -d -q --wait -- ghostty --class="$class" --title="$title" \
    --working-directory="/home/sbx/projects/$dir" >/dev/null 2>&1
}

echo "==> box"
ob down >/dev/null 2>&1 || true
(cd "$ROOT" && ob up >/dev/null)
H=$(ob path)/home
theme tokyo-night

# Ghostty toasts "Reloaded the configuration" on every theme change.
mkdir -p "$H/.config/ghostty"
printf '\napp-notifications = no-config-reload\n' >>"$H/.config/ghostty/config"

echo "==> install"
ob run -- "$ROOT/install.sh" >/dev/null
# A box's Hyprland runs omabox's own config rather than ~/.config/hypr/hyprland.lua,
# but loads Omarchy's toggles folder on every reload: the same loader goes there.
mkdir -p "$H/.local/state/omarchy/toggles/hypr"
sed -n '/^-- Titlebars showing/,$p' "$H/.config/hypr/hyprland.lua" \
  >"$H/.local/state/omarchy/toggles/hypr/omatitles.lua"
# No pointer in the pictures. A toggle file too, so theme changes keep it hidden.
echo 'hl.config({ cursor = { invisible = true } })' >"$H/.local/state/omarchy/toggles/hypr/zz-demo.lua"
ob hyprctl reload >/dev/null
settle

echo "==> windows"
shot "$FRAMES/w0.png"
term org.omarchy.agent "◑ Window naming in Hyprland" titlebars
shot "$FRAMES/w1.png"
term com.mitchellh.ghostty "devbox: api" api
shot "$FRAMES/w2.png"
term com.mitchellh.ghostty "devbox: docs" docs
shot "$FRAMES/w3.png"
cp "$FRAMES/w3.png" "$OUT/hero.png"

echo "==> focus"
ob keys --wait super+left >/dev/null 2>&1; shot "$FRAMES/f1.png"
ob keys --wait super+right >/dev/null 2>&1; shot "$FRAMES/f2.png"

echo "==> themes"
theme catppuccin-latte; shot "$FRAMES/t1.png"
theme gruvbox; shot "$FRAMES/t2.png"
theme tokyo-night; shot "$FRAMES/t3.png"

frames=("$FRAMES/w0.png:0.8" "$FRAMES/w1.png:1.2" "$FRAMES/w2.png:1.2" "$FRAMES/w3.png:2"
  "$FRAMES/f1.png:1" "$FRAMES/f2.png:1.5"
  "$FRAMES/t1.png:1.8" "$FRAMES/t2.png:1.8" "$FRAMES/t3.png:1.2")

if [[ -e /usr/lib/omarchy-hyprland-titlebars/titlebars.so ]]; then
  echo "==> floating workspace"
  ob run -- omarchy-hyprland-workspace-layout-toggle back >/dev/null 2>&1
  shot "$FRAMES/l1.png"
  cp "$FRAMES/l1.png" "$OUT/floating.png"
  ob run -- omarchy-hyprland-workspace-layout-toggle >/dev/null 2>&1
  shot "$FRAMES/l2.png"
  frames+=("$FRAMES/l1.png:2.5" "$FRAMES/l2.png:2")
fi

echo "==> gif"
gif "$OUT/demo.gif" 1280 "${frames[@]}"
ls -la "$OUT"
