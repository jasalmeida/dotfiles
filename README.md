# dotfiles

Personal Hyprland setup, written for [Omarchy](https://omarchy.org).

Run `./install.sh` to symlink everything into place (existing files are kept as `*.bak`).

## Scripts (`bin/` → `~/.local/bin`)

- **`window-cycle`**: Alt+Tab across every workspace, most recently used first. A press
  jumps to the previous window; while Alt stays held, more presses go deeper. Releasing Alt
  puts the window you started on second in the MRU order, so passing through windows
  doesn't count as using them. Shows the window switcher overlay (below) while cycling.
  Needs Hyprland, `hyprctl` and `jq`.
- **`workspace-menu`**: Super+. overview, one row per workspace listing its apps (terminals
  show their directory, browsers the page title). Picking a row switches to it. Uses
  Omarchy's `omarchy-menu-select`; on other setups swap in fuzzel/wofi/rofi.
- **`screensaver-phrase`**: writes a random silly programmer phrase ("WORKS ON MY MACHINE")
  in big block letters to the Omarchy screensaver text. `screensaver-phrase.timer` runs it
  every 20s, and the screensaver re-reads the file before each effect.
- **`hostname-logo`**: replaces the OMARCHY logo on the disk-unlock (Plymouth) and SDDM
  screens with the hostname in block letters, via `omarchy plymouth set` (asks for sudo).
  `--preview` only renders the PNG. Undo with `omarchy refresh plymouth`.

Both use pyfiglet in its own venv (no sudo needed):
`python3 -m venv ~/.local/share/pyfiglet && ~/.local/share/pyfiglet/bin/pip install pyfiglet`

## Omarchy shell plugin (`config/omarchy/plugins/` → `~/.config/omarchy/plugins`)

- **`jalmeida.window-switcher`**: the Alt+Tab overlay, a row of window icons with the
  selection highlighted. A layer-shell panel, so Hyprland never tiles it, and it takes no
  focus or clicks. Summoned by `window-cycle` on each Tab and hidden when Alt is released;
  it only appears once Alt is held for 120ms. It's kept loaded, so QML edits need
  `omarchy restart shell`.

## Hyprland config (`config/hypr/` → `~/.config/hypr`)

- **`bindings.lua`**: Super+. and Alt+Tab bindings. Uses Omarchy's `o.bind` helper (plain
  Hyprland would use `hl.bind`). Alt+Tab polls `hl.is_key_down` to detect when Alt is
  released, because Hyprland doesn't deliver the release after Tab was pressed.
- **`bindings.lua`** also gives the Pixelbook a Delete key: Super+Backspace sends Delete
  (replacing Omarchy's transparency toggle) and Super+Ctrl+Alt+Backspace runs Omarchy's
  Ctrl+Alt+Delete action, "Close all windows".
- **`input.lua`**: natural (macOS-style) touchpad scrolling.
- **`looknfeel.lua`**: no gaps between or around windows.

## systemd user units (`config/systemd/user/` → `~/.config/systemd/user`)

- **`screensaver-phrase.timer`**: rotates the screensaver phrase. `install.sh` enables it.

Requires a Hyprland with Lua config support.

## Shell

`~/.bashrc` also overrides `try` to use `~/workspace/tries` instead of Omarchy's `~/Work/tries`
(not tracked here).
