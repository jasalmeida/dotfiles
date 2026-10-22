# dotfiles

Personal [mango](https://github.com/mangowm/mango) (mangowc) setup on CachyOS, with the
Noctalia shell, tuned to feel like Omarchy and macOS.

Run `./install.sh` to symlink everything into place (existing files are kept as `*.bak`).
It also installs the Pixelbook keyboard fix on a Pixelbook, and says how to add the
Noctalia plugin.

Needs `mango`, `noctalia`, `fuzzel`, `wtype`, `jq` and `python3`.

The earlier Omarchy/Hyprland setup is kept, untouched, in
[`archive/omarchy-hyprland/`](archive/omarchy-hyprland/).

## Keys worth knowing

Super+K lists every binding (see `keybindings-menu` below). The highlights:

| Keys | Does |
| --- | --- |
| Super+Space | App launcher (fuzzel); Super+Alt+Space is Noctalia's launcher |
| Super+K | Keybindings |
| Super+. | Workspace HUD |
| Super+W | Close window |
| Super+Return / Super+Shift+Return | Terminal / browser |
| Alt+Tab | mango's thumbnail switcher, most recently used first, across all workspaces |
| Alt+\` | Next window of the same app |
| Super+Tab / Super+Shift+Tab | Next / previous workspace that has windows, wrapping around |
| Super+/ | Flip the split between side-by-side and stacked |

## mango (`config/mango/` → `~/.config/mango`)

- **`keybinds.conf`**: every bind ends in `#"Description"`, and short comment lines
  (`# Windows`) start sections; `keybindings-menu` reads both.
- **`env.conf`**: puts `~/.local/bin` on `PATH` for binds, since mango starts with a bare
  system `PATH`.
- **`layout.conf`**: dwindle on every workspace; `tag_carousel` makes Super+Tab wrap.
- **`appearance.conf`**: no gaps. **`input.conf`**: natural trackpad scrolling.

## Scripts (`bin/` → `~/.local/bin`)

- **`keybindings-menu`**: Super+K. Keys on the left, what they do on the right, in fuzzel;
  Enter runs the binding. Read from the config every time, so edits show up at once.
- **`mango-keybindings`**: the parser behind it. Follows `source =` includes, prints JSON,
  or `--columns` for the menu.
- **`app-window-cycle`**: Alt+\` / Alt+Shift+\`, like macOS's Cmd+\`. Windows of the
  focused app cycle in opening order, on any workspace.
- **`fuzzel-themed`**: fuzzel in Noctalia's current colors, read from the GTK 4 palette
  Noctalia rewrites on every theme or wallpaper change.
- **`mango-workspace-menu`**: text version of the workspace overview, one fuzzel row per
  workspace (terminals show their directory, browsers the page title). Not bound.

`focusid` needs its target as `mmsg dispatch focusid client,<id>`; `focusid,<id>`
is accepted and silently does nothing.

## Noctalia plugin (`config/noctalia/plugins/`)

Added in Noctalia as a plugin source of kind `path` pointing at this folder.

- **`workspace-hud`**: Super+., an [aerohud](https://github.com/nikhilmwarrier/aerohud)-style
  3x3 grid of workspace cards listing each one's windows. Arrows + Enter, a click, or 1-9 go
  to a workspace; click a window to focus it; drag a window's icon onto another card to
  move it there.

Noctalia gives each plugin callback a small CPU budget, so heavy work (parsing configs,
drawing long lists) has to happen elsewhere; that's why the keybindings list is a script.

## fuzzel (`config/fuzzel/` → `~/.config/fuzzel`)

Monospace (so the keybindings columns line up), larger text, rounded border. Colors come
from `fuzzel-themed`.

`config/applications/` (→ `~/.local/share/applications`) adds Lock Screen, Suspend, Log Out,
Reboot and Shut Down to the app launcher, through `noctalia msg session <action>`.

## Pixelbook (`etc/udev/hwdb.d/`, `config/mango/cfg/pixelbook.conf`)

**`61-pixelbook-super.hwdb`** overrides systemd's Pixelbook keymap. `install.sh` copies it
to `/etc` on a Pixelbook (DMI product "Eve").

- The Assistant key (between Ctrl and Alt) becomes Super. systemd maps it to KEY_ASSISTANT,
  which no compositor keymap can see.
- The top row sends plain F1-F10, and the hamburger key F13 (bound as `code:191`: the
  keymap calls F13 XF86Tools).

**`pixelbook.conf`** uses Super like an Fn key for the action printed on each top-row key:
Super+F5/F6 brightness (+Shift keyboard backlight, +Alt min/max), Super+F7 play/pause,
Super+F8 mute (+Shift audio devices), Super+F9/F10 volume (+Alt by 1%). The hamburger key
opens the app launcher. With no Delete key, Super+Backspace types Delete (needs `wtype`),
and Super+Ctrl+Alt+Backspace closes every window (`mango-close-all-windows`). `kbd-backlight`
steps the keyboard backlight by 10% through logind; Noctalia's own step is 1% here.
