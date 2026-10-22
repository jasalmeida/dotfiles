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

for script in "$repo"/bin/*; do
  link "$script" "$HOME/.local/bin/$(basename "$script")"
done

link "$repo/config/mango/config.conf" "$HOME/.config/mango/config.conf"
for file in "$repo"/config/mango/cfg/*.conf; do
  link "$file" "$HOME/.config/mango/cfg/$(basename "$file")"
done

link "$repo/config/fuzzel/fuzzel.ini" "$HOME/.config/fuzzel/fuzzel.ini"

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

echo
echo "Noctalia plugins: in Noctalia settings (Super+Shift+S) > Plugins, add a"
echo "source of kind \"path\" at $repo/config/noctalia/plugins, then enable"
echo "Workspace HUD."
