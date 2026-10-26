#!/bin/bash
# Runs inside the test container: boots the CachyOS live image (UEFI) in a VM on
# a blank disk, with
#   - its screen in a browser: http://HOST:6080/vnc.html
#   - a root shell on its serial console: /work/serial.sock
#   - its SSH server on the container's port 2222
#   - /work/www served to it over HTTP at http://10.0.2.2:8000 (the test repo)
# /work is a folder on the Docker host holding the ISO; see test/README.md.
set -euo pipefail
cd /work
iso=$(ls cachyos-desktop-linux-*.iso | tail -1)

# The live image's kernel, booted directly so the VM's kernel command line can
# add a serial console and skip the desktop.
if [[ ! -f boot/vmlinuz-linux-cachyos ]]; then
  mkdir -p boot
  bsdtar -xf "$iso" -C boot --strip-components=3 \
    arch/boot/x86_64/vmlinuz-linux-cachyos arch/boot/x86_64/initramfs-linux-cachyos.img
fi
label=$(bsdtar -xOf "$iso" boot/grub/grub.cfg | grep -om1 'archisosearchuuid=[^ ]*')

# VM_BOOT=live (default): a fresh disk and UEFI settings, booting the live image,
# so each test is a clean install. VM_BOOT=disk: boot what was installed.
if [[ ${VM_BOOT:-live} == live ]]; then
  cp /usr/share/OVMF/OVMF_VARS_4M.fd vars.fd
  qemu-img create -q -f qcow2 disk.qcow2 30G
  boot=(-drive file="$iso",media=cdrom,readonly=on
        -kernel boot/vmlinuz-linux-cachyos -initrd boot/initramfs-linux-cachyos.img
        -append "archisobasedir=arch $label copytoram=n console=tty0 console=ttyS0,115200 systemd.debug_shell=ttyS0 systemd.mask=systemd-firstboot.service systemd.unit=multi-user.target")
else
  boot=()
fi
rm -f serial.sock monitor.sock

mkdir -p www
python3 -m http.server 8000 --bind 127.0.0.1 --directory www > http.log 2>&1 &
websockify --web /usr/share/novnc 0.0.0.0:6080 127.0.0.1:5900 > novnc.log 2>&1 &

exec qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp "${VM_CPUS:-3}" -m "${VM_MEMORY:-2560M}" \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=vars.fd \
  -drive file=disk.qcow2,if=virtio,format=qcow2 \
  "${boot[@]}" \
  -nic user,model=virtio-net-pci,hostfwd=tcp:0.0.0.0:2222-:22 \
  -serial unix:serial.sock,server,nowait \
  -monitor unix:monitor.sock,server,nowait \
  -vnc 127.0.0.1:0
