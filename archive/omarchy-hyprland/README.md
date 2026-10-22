# dotfiles (Omarchy/Hyprland, archived)

> **Archived.** This was the Omarchy/Hyprland setup, kept as it was in case I go back.
> Paths below are relative to this folder, and `install.sh` here still works from it.
> The Pixelbook hwdb rule it mentions now lives in the top-level `etc/`.

Personal Hyprland setup, written for [Omarchy](https://omarchy.org).

Run `./install.sh` to symlink everything into place (existing files are kept as `*.bak`).

## Scripts (`bin/` → `~/.local/bin`)

- **`window-cycle`**: Alt+Tab across every workspace, most recently used first. No longer bound
  (hyprshell replaced it), kept as an unused fallback together with the shell plugin below.
  Needs Hyprland, `hyprctl` and `jq`; the icon overlay also needs the plugin enabled.
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

## Omarchy shell plugin (`config/omarchy/plugins/`, currently unused)

- **`jalmeida.window-switcher`**: the Alt+Tab overlay, a row of window icons with the
  selection highlighted. A layer-shell panel, so Hyprland never tiles it, and it takes no
  focus or clicks. Summoned by `window-cycle` on each Tab and hidden when Alt is released;
  it only appears once Alt is held for 120ms. It's kept loaded, so QML edits need
  `omarchy restart shell`.

## Hyprland config (`config/hypr/` → `~/.config/hypr`)

- **`bindings.lua`**: Super+. binding, and frees Alt+Tab from Omarchy's defaults for
  hyprshell. Uses Omarchy's `o.bind` helper (plain Hyprland would use `hl.bind`).
- **`pixelbook.lua`**: keyboard workarounds that only load on a Pixelbook (DMI product
  "Eve"), like `gpu.lua` only acting on hybrid GPUs. Super+Backspace sends Delete
  (replacing Omarchy's transparency toggle), Super+Ctrl+Alt+Backspace is Ctrl+Alt+Delete
  ("Close all windows"), Super+top-row keys act as brightness/media/volume (the keys stay
  F1-F10 on their own), and the hamburger key (F13) opens the Omarchy menu. Needs the
  Assistant key remapped to Super by a udev hwdb rule, which isn't tracked here.
- **`input.lua`**: natural (macOS-style) touchpad scrolling.
- **`looknfeel.lua`**: no gaps between or around windows.

## systemd user units (`config/systemd/user/` → `~/.config/systemd/user`)

- **`screensaver-phrase.timer`**: rotates the screensaver phrase. `install.sh` enables it.

Requires a Hyprland with Lua config support.

## hyprshell (`config/hyprshell/` → `~/.config/hyprshell`)

Alt+Tab window switcher with icons, most recently used first (AUR: `hyprshell-bin`).
`install.sh` links `config.ron` and enables the `hyprshell.service` user unit.

## Shell

`~/.bashrc` also overrides `try` to use `~/workspace/tries` instead of Omarchy's `~/Work/tries`
(not tracked here).
