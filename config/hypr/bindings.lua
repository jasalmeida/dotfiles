-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Personal scripts live in ~/.local/bin (installed from the dotfiles repo)
local bin_dir = (os.getenv("HOME") or "") .. "/.local/bin"

-- Workspace overview menu (like Cmd-. on macOS)
o.bind("SUPER + PERIOD", "Workspace overview", bin_dir .. "/workspace-menu")

-- Alt+Tab across all workspaces, most recently used first. Hyprland doesn't
-- deliver the Alt release once Tab has been pressed, so poll whether Alt is
-- still held and end the cycle (next press starts a fresh MRU list) when not.
local window_cycle = bin_dir .. "/window-cycle"

local function alt_held()
  local ok_l, left = pcall(hl.is_key_down, "Alt_L")
  local ok_r, right = pcall(hl.is_key_down, "Alt_R")
  return (ok_l and left) or (ok_r and right)
end

local alt_poll
alt_poll = hl.timer(function()
  if not alt_held() then
    alt_poll:set_enabled(false)
    hl.exec_cmd(window_cycle .. " reset")
  end
end, { timeout = 30, type = "repeat" })
alt_poll:set_enabled(false)

local function cycle(direction)
  return function()
    hl.exec_cmd(window_cycle .. " " .. direction)
    alt_poll:set_enabled(true)
  end
end

hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
o.bind("ALT + TAB", "Focus next window (all workspaces, MRU)", cycle("next"))
o.bind("ALT + SHIFT + TAB", "Focus previous window (all workspaces, MRU)", cycle("prev"))
