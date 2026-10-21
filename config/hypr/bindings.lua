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

-- Alt+Tab is handled by hyprshell (config/hyprshell/config.ron). Free the key
-- from Omarchy's default window cycling so hyprshell can use it. The previous
-- keyboard-only switcher is still in bin/window-cycle.
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")

-- Pixelbook has no Delete key: use Super+Backspace (replaces Omarchy's window
-- transparency toggle). Sent as an explicit key down/up (same approach as
-- Omarchy's universal clipboard) so the held Super doesn't leak into it.
local function send_delete()
  hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Delete", state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Delete", state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

hl.unbind("SUPER + BACKSPACE")
o.bind("SUPER + BACKSPACE", "Delete", send_delete)

-- Ctrl+Alt+Delete equivalent: Omarchy's "Close all windows"
o.bind("SUPER + CTRL + ALT + BACKSPACE", "Close all windows", "omarchy-hyprland-window-close-all")

-- Pixelbook has no keyboard backlight keys: use Super + the screen brightness
-- keys (Alt is already Omarchy's "precise" screen brightness step).
o.bind("SUPER + XF86MonBrightnessUp", "Keyboard brightness up", "omarchy-brightness-keyboard up", { locked = true, repeating = true })
o.bind("SUPER + XF86MonBrightnessDown", "Keyboard brightness down", "omarchy-brightness-keyboard down", { locked = true, repeating = true })
