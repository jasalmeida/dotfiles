#!/bin/bash
# Runs in the iso/ build container: turns the official CachyOS live image in
# /work into the custom USB image, adding
#   - an "Install" boot entry (the default) that runs dotfiles-installer on tty1
#   - gum and the Terminus console fonts
#   - a copy of this repo in /usr/share/dotfiles (the fallback if GitHub is down)
# /src is this repo; COMMIT names the version. See iso/build.sh.
set -euo pipefail
iso=$(ls /work/cachyos-desktop-linux-*.iso | sort | tail -1)
release=$(basename "$iso" .iso | sed 's/.*-//')
out=/work/out/jasalmeida-cachyos-$release.iso
build=/build
rm -rf "$build" && mkdir -p "$build" /work/out

echo "== Unpacking $(basename "$iso")"
bsdtar -xf "$iso" -C "$build" arch/x86_64/airootfs.sfs boot/grub/grub.cfg
unsquashfs -q -no-progress -d "$build/root" "$build/arch/x86_64/airootfs.sfs"
rm "$build/arch/x86_64/airootfs.sfs"

echo "== Adding gum, the Terminus fonts and the installer"
mkdir -p /tmp/pkgs
pacman -Syw --noconfirm --cachedir /tmp/pkgs gum terminus-font > /dev/null
for pkg in /tmp/pkgs/*.pkg.tar.zst; do
  bsdtar -xpf "$pkg" -C "$build/root" --exclude '.*'
done
cp -a /src/iso/airootfs/. "$build/root/"
chmod 755 "$build/root/usr/local/bin/dotfiles-installer"
ln -sf ../dotfiles-installer.service \
  "$build/root/etc/systemd/system/multi-user.target.wants/dotfiles-installer.service"
rm -rf "$build/root/usr/share/dotfiles"
cp -a /src "$build/root/usr/share/dotfiles"
echo "${COMMIT:-unknown}, built $(date +%F)" > "$build/root/etc/dotfiles-installer"

echo "== Repacking the root filesystem"
mksquashfs "$build/root" "$build/airootfs.sfs" -comp zstd -Xcompression-level 15 -b 1M -noappend -quiet -no-progress
(cd "$build" && sha512sum airootfs.sfs > airootfs.sha512)

# The Install entry: the stock entry's kernel and options, booting to a console
# (no live desktop) where dotfiles-installer.service takes tty1.
grub=$build/boot/grub/grub.cfg
uuid=$(grep -om1 'archisosearchuuid=[^ ]*' "$grub" | cut -d= -f2)
linux=$(grep -m1 'linux /arch/boot/x86_64/vmlinuz-linux-cachyos ' "$grub" | sed 's/^ *//')
initrd=$(grep -m1 'initrd /arch/boot/x86_64/initramfs-linux-cachyos.img' "$grub" | sed 's/^ *//')
entry=$(cat << EOF
menuentry "Install CachyOS, set up my way (erases a disk you pick)" --class arch --class os --id 'dotfiles-install' {
    set gfxpayload=keep
    $linux systemd.unit=multi-user.target systemd.mask=systemd-firstboot.service dotfiles.install
    $initrd
}

EOF
)
awk -v entry="$entry" '
  /^menuentry "CachyOS" / && !done { print entry; done = 1 }
  { print }
' "$grub" > "$grub.new"
sed -i 's/^default=cachyos$/default=dotfiles-install/; s/Welcome to CachyOS \$CACHYOS_VERSION Live ISO/CachyOS $CACHYOS_VERSION, set up my way/' "$grub.new"
mv "$grub.new" "$grub"
grep -q "id 'dotfiles-install'" "$grub" && grep -q '^default=dotfiles-install$' "$grub" ||
  { echo "couldn't add the Install entry to grub.cfg" >&2; exit 1; }

echo "== Writing $(basename "$out")"
rm -f "$out"
# Same boot setup as the original; keeping its date-based UUID keeps the boot
# entries' archisosearchuuid= finding this image.
xorriso -indev "$iso" -outdev "$out" \
  -map "$build/airootfs.sfs" /arch/x86_64/airootfs.sfs \
  -map "$build/airootfs.sha512" /arch/x86_64/airootfs.sha512 \
  -map "$grub" /boot/grub/grub.cfg \
  -volume_date uuid "${uuid//-/}" \
  -boot_image any replay > "$build/xorriso.log" 2>&1 ||
  { cat "$build/xorriso.log" >&2; exit 1; }
(cd /work/out && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")
rm -rf "$build"
# Owned by whoever ran build.sh, not root.
[[ -n ${OWNER:-} ]] && chown "$OWNER" /work/out /work/out/*
ls -la "$out"
