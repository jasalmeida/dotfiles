#!/bin/bash
# Build a whole machine from the custom CachyOS USB (see iso/): erase a disk,
# install CachyOS (LUKS + btrfs + Limine, as CachyOS's own installer sets it up),
# every package in packages.txt, and these dotfiles. Asks only for the personal
# details. The USB runs this by itself from its "Install" boot entry.
#
# SETUP_ANSWERS=FILE answers the questions from a file of NAME=value lines instead
# (for testing in a VM; see test/); DOTFILES_REPO overrides where the dotfiles
# are cloned from.
set -euo pipefail

# Machine-wide settings, the same on every machine.
TIMEZONE=America/New_York
LOCALE=en_US.UTF-8
KEYMAP=us
SHELL_PATH=/bin/fish
DOTFILES_REPO=${DOTFILES_REPO:-https://github.com/jasalmeida/dotfiles.git}
LOG=/var/log/dotfiles-setup.log

mnt=/mnt
accent=14
# gum's prompts and menus in the same cyan (its defaults are blue and red).
export GUM_INPUT_HEADER_FOREGROUND=14 GUM_INPUT_PROMPT_FOREGROUND=14 GUM_INPUT_CURSOR_FOREGROUND=14 \
  GUM_CHOOSE_HEADER_FOREGROUND=14 GUM_CHOOSE_CURSOR_FOREGROUND=14 GUM_CHOOSE_SELECTED_FOREGROUND=14 \
  GUM_CONFIRM_PROMPT_FOREGROUND=14 GUM_CONFIRM_SELECTED_BACKGROUND=14 GUM_CONFIRM_SELECTED_FOREGROUND=0 \
  GUM_SPIN_SPINNER_FOREGROUND=14
step() { echo; gum style --bold --foreground "$accent" "==> $*"; }
die() { gum style --bold --foreground 9 "error: $*" >&2; exit 1; }
in_target() { arch-chroot "$mnt" "$@"; }
as_user() { arch-chroot "$mnt" su - "$username" -c "$1"; }

# --- Checks -------------------------------------------------------------------

[[ $EUID == 0 ]] || { echo "run this as root" >&2; exit 1; }
# Only from the custom USB: it carries gum, and this script assumes CachyOS's
# live environment throughout.
[[ -f /etc/dotfiles-installer ]] || { echo "run this from the custom USB (see iso/)" >&2; exit 1; }
[[ -d /sys/firmware/efi ]] || die "this machine didn't boot in UEFI mode"
curl -fsI -m 10 https://github.com > /dev/null || die "no internet connection"

src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ -f $src/packages.txt ]] || die "packages.txt isn't next to setup.sh"

# --- Questions ----------------------------------------------------------------

if [[ -n ${SETUP_ANSWERS:-} ]]; then
  # shellcheck disable=SC1090
  source "$SETUP_ANSWERS"
fi

ask() {  # ask VAR "Question" [default]
  local var=$1 question=$2 default=${3:-} reply=
  [[ -n ${!var:-} ]] && return
  while [[ -z $reply ]]; do
    reply=$(gum input --header "$question" --value "$default" --width 60)
  done
  printf -v "$var" '%s' "$reply"
}

ask_secret() {  # ask_secret VAR "What"
  local var=$1 what=$2 one two
  [[ -n ${!var:-} ]] && return
  while :; do
    one=$(gum input --password --header "$what" --width 60)
    two=$(gum input --password --header "$what, again" --width 60)
    [[ -n $one && $one == "$two" ]] && break
    gum style --foreground 9 "They didn't match (or were empty). Try again."
  done
  printf -v "$var" '%s' "$one"
}

clear
gum style --border rounded --border-foreground "$accent" --padding "1 4" --margin "1 2" --align center \
  "$(gum style --bold --foreground "$accent" "CachyOS, set up the way I like it")" \
  "mango + Noctalia, every package, and the dotfiles" \
  "" "A few questions, then it runs on its own."

step "About you"
ask full_name "Your full name"
ask username "Username" "$(tr '[:upper:]' '[:lower:]' <<< "${full_name%% *}" | tr -cd 'a-z0-9_-')"
until [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]]; do
  gum style --foreground 9 "Usernames are lowercase letters, digits, - and _."
  username= && ask username "Username"
done
ask_secret password "Password for $username"
ask git_name "Name for git commits" "$full_name"
ask git_email "Email for git commits"

case $(cat /sys/class/dmi/id/product_name 2> /dev/null) in
  Eve)  suggested=pixelbook ;;
  M141) suggested=motile ;;
  *)    suggested=$(tr '[:upper:]' '[:lower:]' < /sys/class/dmi/id/product_name 2> /dev/null |
          tr -c 'a-z0-9' '-' | tr -s '-' | sed 's/^-//; s/-$//') ;;
esac
ask hostname "Name for this computer" "${suggested:-cachyos}"

step "Disk"
# Never offer the USB stick this is running from: the disk under the boot mount
# (through Ventoy's device-mapper layer, if any), and any disk holding a Ventoy
# or USB-image filesystem (the boot mount is gone after copytoram).
usb_disks() {
  local src
  src=$(findmnt -no SOURCE /run/archiso/bootmnt 2> /dev/null) &&
    lsblk -slnpo NAME,TYPE "$src" 2> /dev/null | awk '$2 == "disk" {print $1}'
  lsblk -lnpo NAME,FSTYPE,LABEL | awk '$2 == "iso9660" || $3 == "Ventoy" || $3 == "VTOYEFI" {print $1}' |
    while read -r part; do lsblk -slnpo NAME,TYPE "$part" | awk '$2 == "disk" {print $1}'; done
}
if [[ -z ${disk:-} ]]; then
  skip=$(usb_disks | sort -u)
  mapfile -t disks < <(lsblk -dnpo NAME,SIZE,MODEL -e 7,11 | grep -v zram |
    awk -v skip="$skip" 'BEGIN {n = split(skip, s, "\n"); for (i = 1; i <= n; i++) if (s[i] != "") bad[s[i]] = 1} !($1 in bad)')
  [[ ${#disks[@]} -gt 0 ]] || die "no disk to install onto"
  disk=$(printf '%s\n' "${disks[@]}" | gum choose --header "Disk to ERASE and install onto")
  disk=${disk%% *}
fi
disk=/dev/${disk#/dev/}
[[ -b $disk && $(lsblk -dno TYPE "$disk") == disk ]] || die "$disk isn't a disk"

if [[ -z ${luks_passphrase:-} ]]; then
  if gum confirm "Use your password for the disk encryption too? (asked at every boot)"; then
    luks_passphrase=$password
  else
    ask_secret luks_passphrase "Disk encryption passphrase (asked at every boot)"
  fi
fi

echo
gum style --border rounded --border-foreground 9 --padding "1 3" --margin "0 2" \
  "$(gum style --bold "Ready to install")" "" \
  "You         $full_name ($username)" \
  "Git         $git_name <$git_email>" \
  "Computer    $hostname" \
  "Disk        $disk  $(lsblk -dno SIZE,MODEL "$disk" | xargs)" "" \
  "$(gum style --bold --foreground 9 "Everything on $disk will be erased.")"
if [[ ${confirm_disk:-} != "${disk#/dev/}" ]]; then
  confirm_disk=$(gum input --header "Type ${disk#/dev/} to erase it and install" --width 60)
fi
[[ $confirm_disk == "${disk#/dev/}" ]] || die "not confirmed; nothing was changed"

# From here on, a copy of everything goes to the log, and nothing reads the
# keyboard: anything that would ask (limine-mkinitcpio does, after chwd adds
# drivers) takes its default instead of waiting at an unattended screen.
exec > >(tee -a "$LOG") 2>&1 < /dev/null

# --- Disk: EFI partition + LUKS2 with btrfs subvolumes ------------------------

step "Partitioning $disk"
umount -R "$mnt" 2>/dev/null || true
# Anything still open on the disk (say, from an earlier attempt) blocks erasing it.
lsblk -lnpo NAME,TYPE "$disk" | awk '$2 == "crypt" {print $1}' | xargs -r -n1 cryptsetup close
wipefs -af "$disk" > /dev/null
sgdisk --zap-all "$disk" > /dev/null
sgdisk -n1:0:+4G -t1:ef00 -c1:EFI -n2:0:0 -t2:8309 -c2:cachyos "$disk" > /dev/null
partprobe "$disk" 2>/dev/null || true
udevadm settle
[[ $disk =~ [0-9]$ ]] && p=p || p=
esp=$disk${p}1
root_part=$disk${p}2

step "Encrypting"
printf '%s' "$luks_passphrase" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$root_part"
luks_uuid=$(cryptsetup luksUUID "$root_part")
mapper=luks-$luks_uuid
printf '%s' "$luks_passphrase" | cryptsetup open --key-file=- "$root_part" "$mapper"

step "Making filesystems"
mkfs.fat -F32 -n EFI "$esp" > /dev/null
mkfs.btrfs -fq "/dev/mapper/$mapper"
mount "/dev/mapper/$mapper" "$mnt"
for sv in @ @home @root @srv @cache @tmp @log; do
  btrfs subvolume create "$mnt/$sv" > /dev/null
done
umount "$mnt"

opts=noatime,compress=zstd:1
mount -o "subvol=/@,$opts" "/dev/mapper/$mapper" "$mnt"
for pair in @home:home @root:root @srv:srv @cache:var/cache @tmp:var/tmp @log:var/log; do
  mkdir -p "$mnt/${pair#*:}"
  mount -o "subvol=/${pair%%:*},$opts" "/dev/mapper/$mapper" "$mnt/${pair#*:}"
done
mkdir -p "$mnt/boot"
mount -o umask=0077 "$esp" "$mnt/boot"

# --- Base system --------------------------------------------------------------

# CachyOS's CPU-tuned repos: v4 needs AVX-512, v3 AVX2; older CPUs get only the
# generic [cachyos] repo.
level=
for l in v4 v3; do
  if /lib/ld-linux-x86-64.so.2 --help | grep -q "x86-64-$l (supported"; then level=$l; break; fi
done
# The options CachyOS's installer writes.
{
  cat << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
Color
ILoveCandy
VerbosePkgLists
DisableDownloadTimeout
ParallelDownloads = 10
DownloadUser = alpm
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
EOF
  if [[ -n $level ]]; then
    for repo in cachyos-$level cachyos-core-$level cachyos-extra-$level; do
      printf '\n[%s]\nInclude = /etc/pacman.d/cachyos-%s-mirrorlist\n' "$repo" "$level"
    done
  fi
  printf '\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n'
  for repo in core extra multilib; do
    printf '\n[%s]\nInclude = /etc/pacman.d/mirrorlist\n' "$repo"
  done
} > /tmp/pacman.conf

step "Installing the base system (CachyOS ${level:-generic} repos)"
# mkinitcpio now, so its config can be set before the kernels are installed.
pacstrap -K -C /tmp/pacman.conf "$mnt" base mkinitcpio cachyos-keyring cachyos-mirrorlist \
  cachyos-v3-mirrorlist cachyos-v4-mirrorlist
cp /tmp/pacman.conf "$mnt/etc/pacman.conf"

# fstab written by hand, as CachyOS does: mounting by subvolume path (not id) is what
# lets a restored snapshot boot.
uuid_root=$(blkid -s UUID -o value "/dev/mapper/$mapper")
uuid_esp=$(blkid -s UUID -o value "$esp")
{
  echo "UUID=$uuid_esp /boot vfat defaults,umask=0077 0 2"
  echo "UUID=$uuid_root / btrfs subvol=/@,defaults,$opts 0 0"
  for pair in @home:/home @root:/root @srv:/srv @cache:/var/cache @tmp:/var/tmp @log:/var/log; do
    echo "UUID=$uuid_root ${pair#*:} btrfs subvol=/${pair%%:*},defaults,$opts 0 0"
  done
  echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0"
} >> "$mnt/etc/fstab"

# --- Settings that must exist before the kernel and bootloader are installed ---

step "Settings"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$mnt/etc/localtime"
in_target hwclock --systohc
sed -i "s/^#\($LOCALE \)/\1/" "$mnt/etc/locale.gen"
in_target locale-gen > /dev/null
echo "LANG=$LOCALE" > "$mnt/etc/locale.conf"
echo "KEYMAP=$KEYMAP" > "$mnt/etc/vconsole.conf"
echo "$hostname" > "$mnt/etc/hostname"
cat > "$mnt/etc/hosts" << EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $hostname.localdomain $hostname
EOF

# The initramfs CachyOS's installer makes: systemd-based, unlocks the disk.
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth sd-encrypt filesystems)/' \
  "$mnt/etc/mkinitcpio.conf"
# Lets the snapshots listed in the boot menu boot (CachyOS's installer adds it).
mkdir -p "$mnt/etc/mkinitcpio.conf.d"
cat > "$mnt/etc/mkinitcpio.conf.d/10-limine-snapper-sync.conf" << 'EOF'
# This hook is necessary for the proper loading of Limine snapshots.
# Please do not touch unless you know what you are doing.
HOOKS+=(sd-btrfs-overlayfs)
EOF

# Limine reads this when the kernels are installed below.
cat > "$mnt/etc/default/limine" << EOF
ESP_PATH="/boot"
KERNEL_CMDLINE[default]+="quiet nowatchdog splash rw rootflags=subvol=/@ rd.luks.uuid=$luks_uuid root=/dev/mapper/$mapper"
BOOT_ORDER="*, *lts, *fallback, Snapshots"
EOF

# --- Everything else ----------------------------------------------------------

grep -q GenuineIntel /proc/cpuinfo && ucode=intel-ucode || ucode=amd-ucode
mapfile -t packages < <(sed 's/#.*//; /^\s*$/d' "$src/packages.txt")

step "Installing ${#packages[@]} packages"
in_target pacman -Syu --noconfirm --needed "${packages[@]}" "$ucode"

step "Graphics drivers"
in_target chwd --autoconfigure || echo "chwd found nothing to add"

# CachyOS's boot animation; the boot images below are rebuilt with it.
in_target plymouth-set-default-theme cachyos

# In a VM (a test install) there's no GPU, and mango won't start on software
# rendering unless allowed to. Real hardware doesn't get this.
if systemd-detect-virt -q --vm; then
  echo WLR_RENDERER_ALLOW_SOFTWARE=1 >> "$mnt/etc/environment"
fi

step "Bootloader"
in_target limine-install --fallback
in_target limine-update

step "Snapshots"
# cachyos-snapper-support usually creates this while the packages install.
[[ -f $mnt/etc/snapper/configs/root ]] || in_target snapper --no-dbus -c root create-config /

step "Services"
for unit in NetworkManager bluetooth ufw greetd systemd-resolved systemd-timesyncd \
    systemd-oomd avahi-daemon ananicy-cpp limine-snapper-sync fstrim.timer \
    snapper-cleanup.timer cachyos-rate-mirrors.timer cachyos-iw-set-regdomain.path; do
  in_target systemctl enable "$unit" 2> /dev/null || echo "  (no $unit, skipped)"
done
ln -sf /run/systemd/resolve/stub-resolv.conf "$mnt/etc/resolv.conf"

# --- You ------------------------------------------------------------------------

step "Account for $username"
groups=
for g in wheel sys network rfkill users video storage lp audio; do
  in_target getent group "$g" > /dev/null && groups+=${groups:+,}$g
done
in_target useradd -m -G "$groups" -s "$SHELL_PATH" -c "$full_name" "$username"
printf '%s:%s\n' "$username" "$password" | in_target chpasswd
in_target passwd -l root > /dev/null
echo '%wheel ALL=(ALL:ALL) ALL' > "$mnt/etc/sudoers.d/10-wheel"
chmod 440 "$mnt/etc/sudoers.d/10-wheel"

step "Dotfiles"
as_user "git config --global user.name $(printf %q "$git_name") &&
  git config --global user.email $(printf %q "$git_email") &&
  git clone -q $(printf %q "$DOTFILES_REPO") ~/workspace/dotfiles &&
  ~/workspace/dotfiles/install.sh --user &&
  find ~ -name '*.bak' -delete"  # backups of a new account's defaults: nothing to keep
in_target "/home/$username/workspace/dotfiles/install.sh" --system "$username"

# A login keyring with no password: greetd's autologin can't unlock one that has
# a password, and the encrypted disk protects it at rest.
as_user 'mkdir -p ~/.local/share/keyrings && cd ~/.local/share/keyrings &&
  printf "[keyring]\ndisplay-name=Login\nctime=0\nmtime=0\nlock-on-idle=false\nlock-after=false\n" > login.keyring &&
  echo login > default && chmod 600 login.keyring default'

# --- Done -------------------------------------------------------------------------

# A copy of the log on the new system, where it'll still be after the reboot.
cp "$LOG" "$mnt/var/log/dotfiles-setup.log"
sync
# Helpers started inside the new system can hold it for a few seconds after the
# last command; wait for them, and as a last resort detach it (all is synced).
for _ in $(seq 15); do
  umount -R "$mnt" 2> /dev/null && break
  sleep 2
done
if mountpoint -q "$mnt"; then
  umount -Rl "$mnt"
else
  cryptsetup close "$mapper" || true
fi
step "Done"
