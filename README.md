# dotfiles

Personal [mango](https://github.com/mangowm/mango) (mangowc) setup on CachyOS, with the
Noctalia shell, tuned to feel like Omarchy and macOS.

## New machine

Boot the custom USB key (see below) and leave the first boot entry, **Install CachyOS,
set up my way**, selected. The installer comes up full screen, gets online (a Wi-Fi
picker if there's no cable), and fetches the latest `setup.sh` from GitHub, falling back
to the copy on the key.

[`setup.sh`](setup.sh) asks for your name, username, password, git name and email, a name
for the computer, which disk to use (never the USB key itself), and whether to reuse the
password for the disk encryption. Then, unattended:

- **erases the disk** (after you type its name to confirm) and installs CachyOS the way
  its own installer does: a 4 GB EFI partition, LUKS2, btrfs with `@`, `@home`, `@root`,
  `@srv`, `@cache`, `@tmp` and `@log`, and Limine with btrfs snapshots in its boot menu
- picks CachyOS's repos for the CPU (`x86-64-v4` or `-v3`, else generic), the CPU's
  microcode, and the GPU drivers (`chwd`)
- installs everything in [`packages.txt`](packages.txt) (no Firefox, no SDDM; Chromium
  and Claude Code are in)
- creates your account (fish, sudo through `wheel`; root is locked), sets the timezone
  (`America/New_York`), locale and keymap at the top of `setup.sh`
- clones this repo to `~/workspace/dotfiles` over HTTPS, runs `install.sh`, and logs in
  through greetd with a login keyring that has no password (see Login)

Reboot, type the disk passphrase, and you're on the desktop. The clone's `origin` is the
read-only GitHub URL; add your SSH key and point it at the home server to push.

The repo has to live at `~/workspace/dotfiles`: `config/noctalia/config.toml` names that
path as a plugin source (keybindings menu, workspace HUD).

[`test/`](test/README.md) runs the whole thing in a VM, from the USB key to the desktop.

### The USB key

[`iso/build.sh`](iso/build.sh) makes it from the official CachyOS image, in Docker on the
home server (it downloads the newest official image into `~/cachyos-usb/` there first,
when cachyos.org has one):

    iso/build.sh 192.168.0.12

It adds the Install boot entry (the default; CachyOS's live desktop entries stay below
it), `gum` for the installer's prompts, Terminus console fonts for high-resolution
screens, and a copy of this repo. Builds of committed code are published to Forgejo's
package registry as `cachyos-usb` (version `RELEASE-COMMIT`), using an upload token in
`~/.config/cachyos-usb/forgejo-token` on the server.

Changes to `setup.sh`, `packages.txt` and the dotfiles don't need a rebuild: the key
fetches the latest, and every install downloads current packages. `setup.sh` also
refreshes the key's package signing keys before installing, so an old image keeps
working. Rebuild after changing `iso/`, or every few months to pick up a newer kernel for
newer hardware.

The image stays on the server, in `~/cachyos-usb/out/` (each build replaces it). To
write a key, find its name with `lsblk` (check the size and model: this erases it), then
stream the image straight onto it:

    ssh 192.168.0.12 cat cachyos-usb/out/jasalmeida-cachyos-260809.iso |
      sudo dd of=/dev/sdX bs=4M oflag=direct status=progress conv=fsync

## On an existing CachyOS install

Install the packages in `packages.txt`, then run `./install.sh`. It links everything into
place (existing files are kept as `*.bak`), copies in Noctalia's settings, installs the
Pixelbook keyboard fix on a Pixelbook, and installs the greetd login files through sudo.
Switching from SDDM to greetd stays manual (see Login).

Disk encryption matters: the greetd autologin only skips the login password because the
disk passphrase already proved it's you. On an unencrypted disk it would hand a cold boot
straight to the desktop.

After switching to greetd and rebooting, the login keyring still has the password from
your first SDDM login, so the first app to use it prompts for it. Clear it once:
`sudo pacman -S seahorse`, then in Seahorse right-click Login → Change Password, enter the
old password, leave the new one empty, and accept storing it unencrypted. Don't delete the
keyring instead: it holds Chromium's Safe Storage key, and losing that signs Chromium out
of everything.

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
- **`monitors.conf`**: `install.sh` symlinks in `monitors-pixelbook.conf` (1.5x),
  `monitors-motile.conf` (1x) or `monitors-g14.conf` (1.5x) by DMI product name, since
  every laptop's internal panel is named eDP-1 regardless of model; unmatched hardware gets the hardware-free
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
  They hold the bar layout, launcher default view (All), idle (lock at 10 min, screen off
  at 10½, and no sleep, so a key brings the lock screen back at once), theme, wallpaper
  folder, and the enabled plugins, including Arch Updater (`yuuto/arch-updater`) for the
  updates button.
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
at rest by the disk encryption (`setup.sh` creates it that way; on an existing install, see above).
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
