#!/bin/bash
# Put these dotfiles into place. Run as yourself: it links your files (existing
# ones are moved to *.bak), then installs the /etc files through sudo.
#   install.sh                 both parts
#   install.sh --user          only the files in your home folder
#   install.sh --system USER   only the /etc files, as root, for USER's login
# setup.sh runs the two parts separately while it builds a new machine.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dmi_product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
dmi_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)

# A laptop with two GPUs (built-in plus NVIDIA): more than one display device.
two_gpus() {
  local vga count=0
  for vga in /sys/class/drm/card*/device/boot_vga; do
    if [[ $vga =~ /card[0-9]+/device/ ]]; then count=$((count + 1)); fi
  done
  ((count > 1))
}

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

user_files() {
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

  # env.conf spells out the home folder (mango doesn't expand ~ there), so any
  # other user gets a copy with their own.
  if [[ $HOME != /home/jalmeida ]]; then
    rm -f "$HOME/.config/mango/cfg/env.conf"
    sed "s|/home/jalmeida|$HOME|g" "$repo/config/mango/cfg/env.conf" > "$HOME/.config/mango/cfg/env.conf"
    echo "copied $HOME/.config/mango/cfg/env.conf (for $HOME)"
  fi

  # monitors.conf: pick the panel-specific file by DMI product name. Every laptop's
  # internal output is named eDP-1 regardless of model, so a rule tuned for one
  # machine's panel (mode, scale) would otherwise get forced onto any other machine's
  # panel too. Unmatched hardware falls back to the generic, hardware-free monitors.conf.
  case "$dmi_product" in
    Eve)  monitors_src="$repo/config/mango/cfg/monitors-pixelbook.conf" ;;
    M141) monitors_src="$repo/config/mango/cfg/monitors-motile.conf" ;;
    "ROG Zephyrus G14"*) monitors_src="$repo/config/mango/cfg/monitors-g14.conf" ;;
    *)    monitors_src="$repo/config/mango/cfg/monitors.conf" ;;
  esac
  link "$monitors_src" "$HOME/.config/mango/cfg/monitors.conf"

  link "$repo/config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

  # Noctalia: config.toml (incl. the plugin source for config/noctalia/plugins)
  # and the settings its UI saves. Copy them back here after changing settings:
  #   cp ~/.config/noctalia/config.toml ~/.local/state/noctalia/settings.toml config/noctalia/
  place "$repo/config/noctalia/config.toml" "$HOME/.config/noctalia/config.toml"
  place "$repo/config/noctalia/settings.toml" "$HOME/.local/state/noctalia/settings.toml"

  # Noctalia's git plugin sources (the cat, Arch Updater, ...), cloned where it
  # keeps them, so its plugins are there from its first start even if that's
  # before the network is up. Ones already there are left for Noctalia to update.
  local name url
  while read -r name url; do
    local dest=$HOME/.local/state/noctalia/plugins/sources/$name/repo
    [[ -d $dest ]] && continue
    git clone -q "$url" "$dest" && echo "cloned Noctalia plugin source $name" ||
      echo "couldn't clone Noctalia plugin source $name (Noctalia fetches it when online)"
  done < <(awk '/^\s*\[\[plugins.source\]\]/ {kind = url = ""}
                /^\s*kind = / {kind = $3} /^\s*location = / {url = $3}
                /^\s*name = / && kind == "\"git\"" {print $3, url}' \
             "$repo/config/noctalia/config.toml" | tr -d '"')

  # Chromium opens web links and HTML files; Super+Shift+Enter follows this too.
  if [[ -f /usr/share/applications/chromium.desktop ]]; then
    xdg-settings set default-web-browser chromium.desktop ||
      echo "couldn't make Chromium the default browser"
  fi

  # Lock / suspend / log out / reboot / shut down as launcher entries (Super+Space).
  for entry in "$repo"/config/applications/*.desktop; do
    link "$entry" "$HOME/.local/share/applications/$(basename "$entry")"
  done
}

system_files() {
  local user=$1

  # Pixelbook: the Assistant key (between Ctrl and Alt) becomes Super. Copied, not
  # linked: udev reads /etc before any user is logged in.
  if [[ $dmi_product == Eve ]]; then
    hwdb=/etc/udev/hwdb.d/61-pixelbook-super.hwdb
    if ! cmp -s "$repo/etc/udev/hwdb.d/61-pixelbook-super.hwdb" "$hwdb"; then
      install -Dm644 "$repo/etc/udev/hwdb.d/61-pixelbook-super.hwdb" "$hwdb"
      systemd-hwdb update
      # Inside setup.sh's chroot there are no live devices; they pick it up at boot.
      systemd-detect-virt -q --chroot || udevadm trigger --sysname-match="event*"
      echo "installed $hwdb"
    fi
  fi

  # Two GPUs: names for them (/dev/dri/main-gpu, other-gpu), then mango set to
  # drive only the main one so the NVIDIA card can be off (gpu-outputs switches).
  # gpu.conf is written only once the names exist: mango won't start without them.
  if two_gpus; then
    rules=/etc/udev/rules.d/61-gpu-names.rules
    if ! cmp -s "$repo/etc/udev/rules.d/61-gpu-names.rules" "$rules"; then
      install -Dm644 "$repo/etc/udev/rules.d/61-gpu-names.rules" "$rules"
      systemd-detect-virt -q --chroot || { udevadm control --reload && udevadm trigger --subsystem-match=drm; }
      echo "installed $rules"
    fi
    local home gpu_conf
    home=$(getent passwd "$user" | cut -d: -f6)
    gpu_conf=$home/.config/mango/cfg/gpu.conf
    if [[ ! -e $gpu_conf ]]; then
      runuser -u "$user" -- "$repo/bin/gpu-outputs" off > /dev/null
      echo "wrote $gpu_conf (gpu-outputs off)"
    fi
  fi

  # ASUS laptops with an NVIDIA card: dgpu-power turns it off through the firmware
  # (its driver can't put it to sleep), off by default; dgpu-power.service applies
  # that at boot. Installed after gpu.conf above, so that gpu-outputs off didn't
  # call it (through sudo) already.
  if [[ -e /sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable ]]; then
    local f
    for f in usr/local/sbin/dgpu-power etc/systemd/system/dgpu-power.service; do
      if ! cmp -s "$repo/$f" "/$f"; then
        install -Dm"$([[ $f == */sbin/* ]] && echo 755 || echo 644)" "$repo/$f" "/$f"
        echo "installed /$f"
      fi
    done
    systemctl -q is-enabled dgpu-power.service 2> /dev/null || systemctl enable dgpu-power.service
    if [[ ! -e /var/lib/dgpu-power/mode ]]; then
      install -Dm644 /dev/stdin /var/lib/dgpu-power/mode <<< off
      echo "NVIDIA card set to turn off at the next boot (gpu-outputs on to keep it)"
    fi
  fi

  # ASUS laptops: asusd keeps the battery from charging past 80%. It runs from
  # udev and isn't up inside setup.sh's chroot; the next run of install.sh sets it.
  if [[ $dmi_vendor == ASUS* ]] && command -v asusctl > /dev/null; then
    if ! asusctl battery limit 80 > /dev/null 2>&1; then
      echo "couldn't set the battery charge limit (asusd not running yet?)"
    fi
  fi

  # Login: Noctalia's greeter under greetd, autologin into mango (as $user) after
  # the disk passphrase. Only the files are installed; setup.sh switches a new
  # machine to greetd, an existing one is switched by hand (see README).
  if [[ -d /etc/greetd ]]; then
    local greetd
    greetd=$(sed "s/^user = \"jalmeida\"$/user = \"$user\"/" "$repo/etc/greetd/config.toml")
    if [[ $greetd != "$(cat /etc/greetd/config.toml 2>/dev/null)" ]]; then
      install -Dm644 /dev/stdin /etc/greetd/config.toml <<< "$greetd"
      echo "installed /etc/greetd/config.toml"
    fi
    if ! cmp -s "$repo/etc/pam.d/greetd" /etc/pam.d/greetd; then
      install -Dm644 "$repo/etc/pam.d/greetd" /etc/pam.d/greetd
      echo "installed /etc/pam.d/greetd"
    fi
  fi
}

if [[ $dmi_vendor == ASUS* && ${1:-} != --system ]] && ! command -v asusctl > /dev/null; then
  echo "ASUS laptop: install packages-asus.txt (setup.sh does on a new machine):"
  echo "  sudo pacman -S --needed \$(sed 's/#.*//' $repo/packages-asus.txt)"
fi

case ${1:-} in
  --system) system_files "${2:?usage: install.sh --system USER}" ;;
  --user)   user_files ;;
  *)        user_files; sudo "$repo/install.sh" --system "$USER" ;;
esac
