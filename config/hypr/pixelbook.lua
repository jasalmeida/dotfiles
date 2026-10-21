-- Pixelbook (Google "Eve") keyboard workarounds. Loaded on every machine from
-- hyprland.lua, but only applies on a Pixelbook. Its Assistant key is remapped
-- to Super by /etc/udev/hwdb.d/61-pixelbook-super.hwdb (not in this repo).
if not o.shell_succeeds("grep -qx Eve /sys/class/dmi/id/product_name") then
  return
end

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

-- The Pixelbook's top row sends plain F1-F10. Keep them as F-keys and use
-- Super (the key between Ctrl and Alt) like an Fn key to get the action
-- printed on each key, with the same commands as Omarchy's media bindings.
local function top_row(keys, desc, cmd, repeating)
  o.bind(keys, desc, cmd, { locked = true, repeating = repeating })
end

top_row("SUPER + F5", "Brightness down", "omarchy-brightness-display 5%-", true)
top_row("SUPER + F6", "Brightness up", "omarchy-brightness-display +5%", true)
top_row("SUPER + SHIFT + F5", "Brightness minimum", "omarchy-brightness-display 1%")
top_row("SUPER + SHIFT + F6", "Brightness maximum", "omarchy-brightness-display 100%")
top_row("SUPER + ALT + F5", "Keyboard brightness down", "omarchy-brightness-keyboard down", true)
top_row("SUPER + ALT + F6", "Keyboard brightness up", "omarchy-brightness-keyboard up", true)
top_row("SUPER + F7", "Play/pause", "omarchy-shell media playPause")
top_row("SUPER + F8", "Mute", "omarchy-audio-output-volume mute-toggle")
top_row("SUPER + SHIFT + F8", "Switch audio output", "omarchy-audio-output-switch")
top_row("SUPER + F9", "Volume down", "omarchy-audio-output-volume lower", true)
top_row("SUPER + F10", "Volume up", "omarchy-audio-output-volume raise", true)
top_row("SUPER + ALT + F9", "Volume down precise", "omarchy-audio-output-volume -1", true)
top_row("SUPER + ALT + F10", "Volume up precise", "omarchy-audio-output-volume +1", true)

-- The hamburger (Menu) key at the end of the top row sends F13: open the
-- Omarchy menu, same as Super+Space.
o.bind("F13", "Omarchy menu", "omarchy-menu toggle")
