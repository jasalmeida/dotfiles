# dotfiles

Personal [mango](https://github.com/mangowm/mango) (mangowc) setup on CachyOS, with the
Noctalia shell, tuned to feel like Omarchy and macOS.

## Fresh install

Enable disk encryption (LUKS) in the CachyOS installer. The greetd autologin below (see
Login) only skips the login password because the disk passphrase already proved it's you;
on an unencrypted disk, autologin would hand a cold boot straight to the desktop.

Install the packages (`mango` is the binary; the package is `mangowm`):

    sudo pacman -S mangowm noctalia noctalia-greeter rofi wtype jq python3 greetd \
      alacritty dolphin chromium

Clone this repo to `~/workspace/dotfiles` specifically — `config/noctalia/config.toml`
hardcodes that path as a plugin source, so a different clone location breaks the
Noctalia plugins (keybindings menu, workspace HUD, etc). Then run `./install.sh`.

Run `./install.sh` to symlink everything into place (existing files are kept as `*.bak`).
It also copies in Noctalia's settings, installs the Pixelbook keyboard fix on a Pixelbook,
and installs the greetd login files (switching to greetd stays manual, see Login below).

After switching to greetd (see Login) and rebooting, the login keyring still has the
password from your first SDDM login, so the first app to use it prompts for it. Clear it
once: `sudo pacman -S seahorse`, then in Seahorse right-click Login → Change Password,
enter the old password, leave the new one empty, and accept storing it unencrypted. Don't
delete the keyring instead: it holds Chromium's Safe Storage key, and losing that signs
Chromium out of everything.

The earlier Omarchy/Hyprland setup is kept, untouched, in
[`archive/omarchy-hyprland/`](archive/omarchy-hyprland/).

## Keys worth knowing

Super+K lists every binding (see `keybindings-menu` below). The highlights:

| Keys | Does |
| --- | --- |
| Super+Space | Noctalia's launcher (set to show All in its settings) |
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
- **`appearance.conf`**: no gaps. **`input.conf`**: natural trackpad scrolling, and
  two-finger click = right click (`trackpad_click_method = 2`; the default only
  right-clicks in the bottom-right corner).
- **`monitors.conf`**: `install.sh` symlinks in `monitors-pixelbook.conf` (1.5x) or
  `monitors-motile.conf` (1x) by DMI product name, since every laptop's internal panel
  is named eDP-1 regardless of model; unmatched hardware gets the hardware-free
  `monitors.conf` template. Add a `monitors-<host>.conf` and a case in `install.sh` for
  a new machine. Display tools like wdisplays only change it until logout.

## Alacritty (`config/alacritty/` → `~/.config/alacritty`)

CachyOS's default `alacritty.toml`, fixed: its `working_directory = "None"` (read as a
folder named "None") is gone, and Shift+Enter (a newline in Claude Code) is in the
`[keyboard] bindings` list. Claude Code's `/terminal-setup` appends that binding as a
separate `[[keyboard.bindings]]` table, which clashes with the list and stops Alacritty
from loading the file at all, so don't rerun it here.

## Scripts (`bin/` → `~/.local/bin`)

- **`keybindings-menu`**: Super+K. Keys on the left, what they do on the right, in rofi;
  Enter runs the binding. Read from the config every time, so edits show up at once.
- **`mango-keybindings`**: the parser behind it. Follows `source =` includes, prints JSON,
  or `--columns` for the menu.
- **`launch-browser`**: Super+Shift+Enter. Opens the default browser (`xdg-settings`), so
  switching browsers needs no keybinding change. `install.sh` makes Chromium the default.
- **`app-window-cycle`**: Alt+\` / Alt+Shift+\`, like macOS's Cmd+\`. Windows of the
  focused app cycle in opening order, on any workspace.
- **`rofi-themed`**: rofi in Noctalia's current colors (regenerated each run from the GTK 4
  palette Noctalia rewrites on every theme or wallpaper change), monospace so columns line
  up, larger text, rounded border. Replaced fuzzel, whose scrolling snaps the selection back
  to the item under the pointer.
- **`mango-workspace-menu`**: text version of the workspace overview, one rofi row per
  workspace (terminals show their directory, browsers the page title). Not bound.

`focusid` needs its target as `mmsg dispatch focusid client,<id>`; `focusid,<id>`
is accepted and silently does nothing.

## Noctalia (`config/noctalia/`)

- **`config.toml`** (→ `~/.config/noctalia/`) and **`settings.toml`** (→
  `~/.local/state/noctalia/`, what the settings window saves; it overrides `config.toml`).
  Copied, not linked, since Noctalia rewrites them. After changing settings, copy them
  back: `cp ~/.config/noctalia/config.toml ~/.local/state/noctalia/settings.toml config/noctalia/`.
  They hold the bar layout, launcher default view (All), idle (lock at 10 min, lock &
  suspend at 15), theme, wallpaper folder, and the enabled plugins, including Arch Updater
  (`yuuto/arch-updater`) for the updates button.
- **`plugins/`**: `config.toml` registers this folder as a plugin source of kind `path`.

- **`workspace-hud`**: Super+., an [aerohud](https://github.com/nikhilmwarrier/aerohud)-style
  3x3 grid of workspace cards listing each one's windows. Arrows + Enter, a click, or 1-9 go
  to a workspace; click a window to focus it; drag a window's icon onto another card to
  move it there.

Noctalia gives each plugin callback a small CPU budget, so heavy work (parsing configs,
drawing long lists) has to happen elsewhere; that's why the keybindings list is a script.

## Login (`etc/greetd/`, `etc/pam.d/greetd`)

Noctalia's greeter (`noctalia-greeter`) under greetd replaces SDDM. After the disk (LUKS)
passphrase, greetd logs straight into mango once per boot (`initial_session`); logging out
shows the greeter. `noctalia msg greeter-sync` copies the wallpaper, colors and scale to it.

greetd's autologin skips PAM `auth`, so nothing can unlock the keyring there
(`pam_systemd_loadkey` included): the login keyring has **no password** and is protected
at rest by the disk encryption (clearing its password is a fresh-install step above).
Only sound with full-disk encryption. The PAM file adds
the usual gnome-keyring lines for logins through the greeter.

Switching (after `install.sh` put the files in `/etc`): `sudo systemctl disable sddm`,
`sudo systemctl enable greetd`, reboot. Undo from a console (Ctrl+Alt+F2):
`sudo systemctl disable greetd && sudo systemctl enable sddm && sudo reboot`.

## App launcher entries

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
