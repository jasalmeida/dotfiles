# dotfiles

Personal Hyprland setup, written for [Omarchy](https://omarchy.org).

Run `./install.sh` to symlink everything into place (existing files are kept as `*.bak`).

## Scripts (`bin/` → `~/.local/bin`)

- **`window-cycle`**: Alt+Tab across every workspace, most recently used first. A press
  jumps to the previous window; while Alt stays held, more presses go deeper. Needs only
  Hyprland, `hyprctl` and `jq`.
- **`workspace-menu`**: Super+. overview, one row per workspace listing its apps (terminals
  show their directory, browsers the page title). Picking a row switches to it. Uses
  Omarchy's `omarchy-menu-select`; on other setups swap in fuzzel/wofi/rofi.

## Hyprland config (`config/hypr/` → `~/.config/hypr`)

- **`bindings.lua`**: Super+. and Alt+Tab bindings. Uses Omarchy's `o.bind` helper (plain
  Hyprland would use `hl.bind`). Alt+Tab polls `hl.is_key_down` to detect when Alt is
  released, because Hyprland doesn't deliver the release after Tab was pressed.
- **`input.lua`**: natural (macOS-style) touchpad scrolling.

Requires a Hyprland with Lua config support.

## Shell

`~/.bashrc` also overrides `try` to use `~/workspace/tries` instead of Omarchy's `~/Work/tries`
(not tracked here).
