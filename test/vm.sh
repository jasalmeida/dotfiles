#!/bin/bash
# Runs inside the test container: a UEFI VM with
#   - its screen in a browser: http://HOST:6080/vnc.html
#   - a root shell on its serial console: /work/serial.sock (live image only)
#   - /work/www served to it over HTTP at http://10.0.2.2:8000 (test repo, answers)
# VM_BOOT says what it boots:
#   auto  the newest custom image's Install entry, unattended: it clones the test
#         repo and answers setup.sh from www/answers (fresh disk)
#   usb   the newest custom image through its own boot menu, as a real USB key
#         would (fresh disk; the installer asks its questions)
#   disk  what's installed on the disk
# VM_ISO picks another image in /work; VM_NET=none leaves the VM offline. See test/README.md.
set -euo pipefail
cd /work
iso=${VM_ISO:-$(ls out/jasalmeida-cachyos-*.iso 2> /dev/null | sort | tail -1)}
[[ -f $iso ]] || { echo "no custom image in /work/out: run iso/build.sh" >&2; exit 1; }

fresh_disk() {
  cp /usr/share/OVMF/OVMF_VARS_4M.fd vars.fd
  qemu-img create -q -f qcow2 disk.qcow2 30G
}

case ${VM_BOOT:-auto} in
  auto)
    # The Install entry's kernel and options, plus a serial console and the test hooks.
    kernel=boot/$(basename "$iso" .iso)
    if [[ ! -f $kernel/vmlinuz-linux-cachyos ]]; then
      mkdir -p "$kernel"
      bsdtar -xf "$iso" -C "$kernel" --strip-components=3 \
        arch/boot/x86_64/vmlinuz-linux-cachyos arch/boot/x86_64/initramfs-linux-cachyos.img
    fi
    options=$(bsdtar -xOf "$iso" boot/grub/grub.cfg |
      awk "/id 'dotfiles-install'/ {found = 1} found && /^ *linux / {sub(/^ *linux [^ ]* /, \"\"); print; exit}")
    [[ $options == *dotfiles.install* ]] || { echo "no Install entry in $iso" >&2; exit 1; }
    fresh_disk
    boot=(-drive file="$iso",media=cdrom,readonly=on
          -kernel "$kernel/vmlinuz-linux-cachyos" -initrd "$kernel/initramfs-linux-cachyos.img"
          -append "$options copytoram=n console=tty0 console=ttyS0,115200 systemd.debug_shell=ttyS0 dotfiles.repo=http://10.0.2.2:8000/dotfiles.git dotfiles.answers=http://10.0.2.2:8000/answers")
    ;;
  usb)
    fresh_disk
    boot=(-drive file="$iso",media=cdrom,readonly=on,if=none,id=usb -device ide-cd,drive=usb,bootindex=0)
    ;;
  disk)
    boot=()
    ;;
esac
# VM_NET=none: no network, like a laptop whose Wi-Fi isn't set up yet.
nic=(-nic user,model=virtio-net-pci)
[[ ${VM_NET:-user} == none ]] && nic=(-nic none)
rm -f serial.sock monitor.sock

mkdir -p www
python3 -m http.server 8000 --bind 127.0.0.1 --directory www > http.log 2>&1 &
websockify --web /usr/share/novnc 0.0.0.0:6080 127.0.0.1:5900 > novnc.log 2>&1 &

exec qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp "${VM_CPUS:-3}" -m "${VM_MEMORY:-2560M}" \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=vars.fd \
  -drive file=disk.qcow2,if=virtio,format=qcow2 \
  "${boot[@]}" \
  "${nic[@]}" \
  -serial unix:serial.sock,server,nowait \
  -monitor unix:monitor.sock,server,nowait \
  -vnc 127.0.0.1:0
