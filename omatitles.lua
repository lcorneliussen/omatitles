-- omatitles: a titlebar showing the window's own title above agent and terminal
-- windows, styled from the Omarchy theme. No compiled plugin.
--
-- Hyprland has no titlebar of its own, but it draws a groupbar above any window
-- that belongs to a group, and group:groupbar:disable_when_only defaults to
-- false -- so a group of ONE renders a bar showing that window's title. Each
-- matching window opens as its own group; everything else here styles that bar
-- from the active theme and stops groups from forming by accident.
--
-- Usage, from ~/.config/hypr/hyprland.lua (Omarchy Lua config):
--   dofile(os.getenv("HOME") .. "/.local/share/omatitles/omatitles.lua").setup({})

local M = {}

local defaults = {
  -- Windows that get a titlebar: a Hyprland class regex. Pick windows whose
  -- title is already the useful name -- Claude writes the session summary,
  -- herdr writes "<host>: <session>", a shell writes the directory. Browsers
  -- are left out on purpose: their titles run past 100 characters.
  class = "^(org\\.omarchy\\.agent|com\\.mitchellh\\.ghostty|Alacritty|kitty|foot|org\\.codeberg\\.dnkl\\.foot)$",
  font_size = 13,
  height = 24,
  -- Bar alpha, 0-255. Kept mostly opaque: the bar sits in the outer gap, so a
  -- translucent one draws the title straight onto the wallpaper.
  active_alpha = 0xdd,
  inactive_alpha = 0xcc,
}

-- Marks windows omatitles gave a bar, so a window the user ungrouped on purpose
-- (SUPER + G) is left alone afterwards.
local TAG = "omatitles"
-- Marks every window omatitles has seen, so the retrofit below runs once per
-- window and never undoes a bar the user took off.
local SEEN_TAG = "omatitles-seen"
-- Marks windows whose bar was handed to Omarchy's floating-workspace titlebars.
local HANDOFF_TAG = "omatitles-handoff"
-- Omarchy 4.5+ tags every window on a floating workspace with this and draws
-- its own titlebar there (omarchy-hyprland-titlebars). Two bars would stack.
local FLOATING_TAG = "omarchy-floating-workspace"

local cfg
local pending = false

-- Theme colors --------------------------------------------------------------
-- The current theme's hyprland.lua is required by default/hypr/omarchy.lua,
-- which hyprland.lua loads before this file, so the theme's border colors are
-- readable here. `omarchy theme set` reloads the config, so these re-derive
-- themselves on every theme change.

local function theme_argb(key, fallback)
  local ok, value = pcall(hl.get_config, key)
  if not ok or value == nil then return fallback end
  -- Colors come back either as a scalar or as a gradient table; a gradient's
  -- first stop is the one the border actually leads with.
  local raw = value
  if type(value) == "table" and type(value.colors) == "table" then
    raw = value.colors[1]
  end
  return tonumber(raw) or fallback
end

local function rgba(color, alpha)
  return string.format("rgba(%02x%02x%02x%02x)",
    (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF, alpha)
end

-- Relative luminance, used to pick a title color that contrasts with whatever
-- the theme's accent turns out to be. Without this a light theme gets white
-- text on a pale bar.
local function luminance(color)
  return (0.2126 * ((color >> 16) & 0xFF)
        + 0.7152 * ((color >> 8) & 0xFF)
        + 0.0722 * (color & 0xFF)) / 255
end

local function readable_on(color)
  return luminance(color) > 0.55 and "rgb(000000)" or "rgb(ffffff)"
end

-- Windows -------------------------------------------------------------------

local function has_tag(win, tag)
  local tags = win and win.tags
  if type(tags) == "string" then
    tags = { tags }
  end
  for _, value in pairs(tags or {}) do
    if value == tag or value == tag .. "*" then
      return true
    end
  end
  return false
end

local function matches(win)
  -- Hyprland regexes are RE2; the default only needs alternation and anchors,
  -- which Lua patterns lack, so ask Hyprland which windows the rule matched.
  return has_tag(win, TAG)
end

local function group_size(win)
  return win.group and win.group.size or 0
end

local function toggle_group(win)
  hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. win.address }))
end

local function set_tag(win, tag, on)
  hl.dispatch(hl.dsp.window.tag({ tag = (on and "+" or "-") .. tag, window = "address:" .. win.address }))
end

-- Bring one window in line: a bar of ours on tiled workspaces, none where
-- Omarchy draws its own. Only ever touches groups of one, so tabs the user made
-- are never split up.
local function reconcile(win)
  if not matches(win) then
    return
  end

  local size = group_size(win)
  if has_tag(win, FLOATING_TAG) then
    if size == 1 then
      toggle_group(win)
      set_tag(win, HANDOFF_TAG, true)
    end
  elseif has_tag(win, HANDOFF_TAG) then
    if size == 0 then
      toggle_group(win)
    end
    set_tag(win, HANDOFF_TAG, false)
  end
end

-- Tag changes arrive as a burst of window.update_rules events, one or more per
-- window. Coalesce them into a single pass once the burst is over.
local function schedule()
  if pending then
    return
  end
  pending = true
  hl.timer(function()
    pending = false
    for _, win in ipairs(hl.get_windows() or {}) do
      reconcile(win)
    end
  end, { type = "oneshot", timeout = 1 })
end

function M.setup(opts)
  if cfg then
    return M
  end
  cfg = {}
  for k, v in pairs(defaults) do
    cfg[k] = v
  end
  for k, v in pairs(opts or {}) do
    cfg[k] = v
  end

  local accent = theme_argb("general:col.active_border", 0xFF33CCFF)
  local muted = theme_argb("general:col.inactive_border", 0xFF595959)

  hl.config({
    group = {
      -- Never group by accident. Hyprland's defaults auto-group new windows
      -- into the focused group and merge windows dragged onto each other --
      -- harmless when nothing is ever a group, but with every terminal now
      -- being one it silently turns unrelated windows into tabs. Grouping stays
      -- deliberate: SUPER + G, or SUPER + ALT + <arrow> to pull a neighbour in.
      auto_group = false,
      drag_into_group = 0,
      merge_groups_on_drag = false,
      merge_groups_on_groupbar = false,

      groupbar = {
        -- Middle-click on a groupbar closes that window by default. Middle-click
        -- is also the primary-selection paste gesture, so with a bar above every
        -- terminal, one stray click kills a live agent session.
        middle_click_close = false,

        -- "monospace" resolves through fontconfig, which is what
        -- `omarchy font set` changes -- so the bar follows the system font.
        font_family = "monospace",
        font_size = cfg.font_size,
        height = cfg.height,
        blur = true,
        gradients = true,

        -- The focused window wears the theme accent, the rest the theme's
        -- muted border color.
        col = {
          active = rgba(accent, cfg.active_alpha),
          inactive = rgba(muted, cfg.inactive_alpha),
        },
        text_color = readable_on(accent),
        text_color_inactive = readable_on(muted),
      },
    },
  })

  -- "new always" is shorthand for "barred set always": every matching window
  -- opens as its own group ("set") and never joins the focused one ("barred"),
  -- for every window rather than just the first ("always").
  o.window({ class = cfg.class }, { group = "new always", tag = "+" .. TAG })

  hl.on("window.open", function(win)
    set_tag(win, SEEN_TAG, true)
  end)
  hl.on("window.update_rules", schedule)
  hl.on("window.move_to_workspace", schedule)

  -- Window rules apply when a window opens, so windows already running when
  -- omatitles is first installed have no bar yet. Give them one, once: a
  -- window that already carries the tag was seen before, and if it has no bar
  -- now, the user took it off.
  hl.timer(function()
    for _, win in ipairs(hl.get_windows() or {}) do
      if has_tag(win, SEEN_TAG) then
        goto continue
      end
      set_tag(win, SEEN_TAG, true)
      if has_tag(win, TAG) and group_size(win) == 0 and not has_tag(win, FLOATING_TAG) then
        toggle_group(win)
      end
      ::continue::
    end
    schedule()
  end, { type = "oneshot", timeout = 1 })

  return M
end

return M
