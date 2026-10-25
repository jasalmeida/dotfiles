#!/bin/bash
# Symlink these dotfiles into place. Existing files are moved to *.bak.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

link() {
  local src=$1 dest=$2
  mkdir -p "$(dirname "$dest")"
  if [[ -e $dest && ! -L $dest ]]; then
    mv "$dest" "$dest.bak"
    echo "backed up $dest -> $dest.bak"
  fi
  ln -sfn "$src" "$dest"
  echo "linked $dest"
}

# For files their program rewrites (a symlink would be replaced): copy, keeping
# any different existing file as *.bak.
place() {
  local src=$1 dest=$2
  mkdir -p "$(dirname "$dest")"
  if [[ -e $dest ]] && ! cmp -s "$src" "$dest"; then
    mv "$dest" "$dest.bak"
    echo "backed up $dest -> $dest.bak"
  fi
  cp "$src" "$dest"
  echo "copied $dest"
}

for script in "$repo"/bin/*; do
  link "$script" "$HOME/.local/bin/$(basename "$script")"
done

link "$repo/config/mango/config.conf" "$HOME/.config/mango/config.conf"
for file in "$repo"/config/mango/cfg/*.conf; do
  base=$(basename "$file")
  # monitors-*.conf are per-host variants, picked below instead of linked as-is.
  [[ $base == monitors-*.conf ]] && continue
  link "$file" "$HOME/.config/mango/cfg/$base"
done

# monitors.conf: pick the panel-specific file by DMI product name. Every laptop's
# internal output is named eDP-1 regardless of model, so a rule tuned for one
# machine's panel (mode, scale) would otherwise get forced onto any other machine's
# panel too. Unmatched hardware falls back to the generic, hardware-free monitors.conf.
dmi_product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
case "$dmi_product" in
  Eve)  monitors_src="$repo/config/mango/cfg/monitors-pixelbook.conf" ;;
  M141) monitors_src="$repo/config/mango/cfg/monitors-motile.conf" ;;
  *)    monitors_src="$repo/config/mango/cfg/monitors.conf" ;;
esac
link "$monitors_src" "$HOME/.config/mango/cfg/monitors.conf"

# Noctalia: config.toml (incl. the plugin source for config/noctalia/plugins)
# and the settings its UI saves. Copy them back here after changing settings:
#   cp ~/.config/noctalia/config.toml ~/.local/state/noctalia/settings.toml config/noctalia/
place "$repo/config/noctalia/config.toml" "$HOME/.config/noctalia/config.toml"
place "$repo/config/noctalia/settings.toml" "$HOME/.local/state/noctalia/settings.toml"

# Chromium opens web links and HTML files; Super+Shift+Enter follows this too.
if [[ -f /usr/share/applications/chromium.desktop ]]; then
  xdg-settings set default-web-browser chromium.desktop
fi

# Lock / suspend / log out / reboot / shut down as launcher entries (Super+Space).
for entry in "$repo"/config/applications/*.desktop; do
  link "$entry" "$HOME/.local/share/applications/$(basename "$entry")"
done

# Pixelbook: the Assistant key (between Ctrl and Alt) becomes Super. Copied, not
# linked: udev reads /etc before any user is logged in.
if [[ $(cat /sys/class/dmi/id/product_name 2>/dev/null) == Eve ]]; then
  hwdb=/etc/udev/hwdb.d/61-pixelbook-super.hwdb
  if ! cmp -s "$repo/etc/udev/hwdb.d/61-pixelbook-super.hwdb" "$hwdb"; then
    sudo install -Dm644 "$repo/etc/udev/hwdb.d/61-pixelbook-super.hwdb" "$hwdb"
    sudo systemd-hwdb update
    sudo udevadm trigger --sysname-match="event*"
    echo "installed $hwdb"
  fi
fi

# Login: Noctalia's greeter under greetd, autologin into mango after the disk
# passphrase. Only the files are installed; switching display managers is left
# to do by hand (see README).
if [[ -d /etc/greetd ]]; then
  for f in greetd/config.toml pam.d/greetd; do
    if ! cmp -s "$repo/etc/$f" "/etc/$f"; then
      sudo install -Dm644 "$repo/etc/$f" "/etc/$f"
      echo "installed /etc/$f"
    fi
  done
fi
