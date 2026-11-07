#!/usr/bin/env bash
# Install (or update) omatitles for Omarchy's Lua Hyprland config.
#
#   curl -fsSL https://raw.githubusercontent.com/lcorneliussen/omatitles/main/install.sh | bash
#
# Run from a checkout, it links that checkout instead of cloning.
set -euo pipefail

REPO_URL="${OMATITLES_REPO:-https://github.com/lcorneliussen/omatitles.git}"
# Fixed, HOME-relative path: the loader line below must work in synced dotfiles too.
DEST="$HOME/.local/share/omatitles"
HYPR_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
MARKER="omatitles/omatitles.lua"

if [[ ! -f "$HYPR_CONF" ]]; then
  echo "omatitles: $HYPR_CONF not found. This needs Omarchy's Lua Hyprland config." >&2
  exit 1
fi

src_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "$(dirname "${BASH_SOURCE[0]}")/omatitles.lua" ]]; then
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

mkdir -p "$(dirname "$DEST")"
if [[ -n "$src_dir" && "$src_dir" != "$DEST" ]]; then
  if [[ -e "$DEST" && ! -L "$DEST" ]]; then
    echo "omatitles: $DEST exists and is not a link; remove it to link this checkout." >&2
    exit 1
  fi
  ln -sfn "$src_dir" "$DEST"
  echo "omatitles: linked $DEST -> $src_dir"
elif [[ -d "$DEST/.git" ]]; then
  git -C "$DEST" pull --ff-only --quiet
  echo "omatitles: updated $DEST"
else
  git clone --quiet --depth 1 "$REPO_URL" "$DEST"
  echo "omatitles: cloned into $DEST"
fi

if grep -q "$MARKER" "$HYPR_CONF"; then
  echo "omatitles: already loaded from $HYPR_CONF"
else
  cat >>"$HYPR_CONF" <<'EOF'

-- Titlebars showing the window's own title on agent and terminal windows. Options: see omatitles.lua.
local ot_ok, ot_err = pcall(function() dofile(os.getenv("HOME") .. "/.local/share/omatitles/omatitles.lua").setup({}) end)
if not ot_ok then print("omatitles: " .. tostring(ot_err)) end
EOF
  echo "omatitles: added loader to $HYPR_CONF"
fi

echo "omatitles: done. Hyprland reloads the config on save; if not, run: hyprctl reload"
