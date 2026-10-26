#!/bin/bash
# Build a whole machine from the CachyOS live USB: erase a disk, install CachyOS
# (LUKS + btrfs + Limine, as CachyOS's own installer sets it up), every package in
# packages.txt, and these dotfiles. Asks only for the personal details.
#
# From the live USB's terminal:
#   curl -fsSL https://raw.githubusercontent.com/jasalmeida/dotfiles/main/setup.sh | sudo bash
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
TARBALL=https://github.com/jasalmeida/dotfiles/archive/refs/heads/main.tar.gz

mnt=/mnt
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }
in_target() { arch-chroot "$mnt" "$@"; }
as_user() { arch-chroot "$mnt" su - "$username" -c "$1"; }

# --- Checks -------------------------------------------------------------------

[[ $EUID == 0 ]] || die "run this as root (sudo bash setup.sh)"
[[ -d /sys/firmware/efi ]] || die "this machine didn't boot in UEFI mode"
for tool in pacstrap arch-chroot genfstab sgdisk cryptsetup mkfs.btrfs mkfs.fat curl; do
  command -v $tool > /dev/null || die "missing $tool: run this from the CachyOS live USB"
done
curl -fsI -m 10 https://github.com > /dev/null || die "no internet connection (connect to Wi-Fi first)"

# The rest of the repo (packages.txt, ...): next to this script, or downloaded.
src=$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)
if [[ ! -f $src/packages.txt ]]; then
  src=$(mktemp -d)
  curl -fsSL "$TARBALL" | tar -xz -C "$src" --strip-components=1
fi

# --- Questions ----------------------------------------------------------------

if [[ -n ${SETUP_ANSWERS:-} ]]; then
  # shellcheck disable=SC1090
  source "$SETUP_ANSWERS"
fi

ask() {  # ask VAR "Question" [default]
  local var=$1 question=$2 default=${3:-} reply
  [[ -n ${!var:-} ]] && return
  while :; do
    read -rp "$question${default:+ [$default]}: " reply < /dev/tty
    reply=${reply:-$default}
    [[ -n $reply ]] && break
  done
  printf -v "$var" '%s' "$reply"
}

ask_secret() {  # ask_secret VAR "What"
  local var=$1 what=$2 one two
  [[ -n ${!var:-} ]] && return
  while :; do
    read -rsp "$what: " one < /dev/tty; echo
    read -rsp "$what again: " two < /dev/tty; echo
    [[ -n $one && $one == "$two" ]] && break
    echo "They didn't match (or were empty). Try again."
  done
  printf -v "$var" '%s' "$one"
}

step "About you"
ask full_name "Full name"
ask username "Username" "$(tr '[:upper:]' '[:lower:]' <<< "${full_name%% *}")"
[[ $username =~ ^[a-z_][a-z0-9_-]*$ ]] || die "usernames are lowercase letters, digits, - and _"
ask_secret password "Password for $username"
ask git_name "Name for git commits" "$full_name"
ask git_email "Email for git commits"
ask hostname "Name for this computer"

step "Disk"
lsblk -dno NAME,SIZE,MODEL,TRAN -e 7,11 | grep -v '^zram' | sed 's/^/  /'
ask disk "Disk to erase and install onto (e.g. nvme0n1)"
disk=/dev/${disk#/dev/}
[[ -b $disk && $(lsblk -dno TYPE "$disk") == disk ]] || die "$disk isn't a disk"
ask_secret luks_passphrase "Disk encryption passphrase (asked at every boot)"

echo
echo "This ERASES EVERYTHING on $disk: $(lsblk -dno SIZE,MODEL "$disk" | xargs)"
if [[ ${confirm_disk:-} != "${disk#/dev/}" ]]; then
  read -rp "Type the disk's name (${disk#/dev/}) to go ahead: " confirm_disk < /dev/tty
fi
[[ $confirm_disk == "${disk#/dev/}" ]] || die "not confirmed; nothing was changed"

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

sync
umount -R "$mnt"
cryptsetup close "$mapper"
step "Done. Remove the USB key and reboot; you'll be asked for the disk passphrase."
