# Testing the USB key in a VM

`run.sh` boots the custom USB image (from `iso/build.sh`) in a VM, lets its Install entry
build a whole machine on a blank disk, then boots the result, unlocks the disk, and
screenshots the desktop. `setup.sh` comes from this repo's working tree, uncommitted
changes included; rebuild the image only after changing `iso/`.

    iso/build.sh 192.168.0.12     # when iso/ changed
    test/run.sh 192.168.0.12

The VM runs in a Docker container on that host, so the host needs Docker (you in the
`docker` group), `/dev/kvm`, and the official CachyOS image in `~/cachyos-usb/`, which
`iso/build.sh` starts from:

    mkdir -p ~/cachyos-usb && cd ~/cachyos-usb
    curl -fLO https://cdn77.cachyos.org/ISO/desktop/260809/cachyos-desktop-linux-260809.iso
    curl -fLO https://cdn77.cachyos.org/ISO/desktop/260809/cachyos-desktop-linux-260809.iso.sha256
    sha256sum -c cachyos-desktop-linux-260809.iso.sha256

Watch it at `http://HOST:6080/vnc.html`. The installer answers its questions from
`www/answers` (user `tester`, password and disk passphrase `test`); screenshots and the
install log land in `test/out/`.

The container is capped at 3.5 GB of memory (the VM gets 2.5 GB), so a VM that runs short
is stopped on its own instead of squeezing the host. Remove it when done:
`ssh HOST docker rm -f dotfiles-test-vm`.

- **`Dockerfile`, `vm.sh`**: the container: QEMU (UEFI), noVNC, and an HTTP server the VM
  reaches at `10.0.2.2:8000` for the test copy of the repo and the answers. `VM_BOOT`
  picks what it boots:
  - `auto` (what `run.sh` uses): the Install entry, with a serial console and the
    launcher's test hooks, `dotfiles.repo=` and `dotfiles.answers=`. Without a
    `www/answers`, it asks its questions, so you can try them out over noVNC.
  - `usb`: the image through its own boot menu, as a real USB key would boot (it then
    fetches `setup.sh` from GitHub).
  - `disk`: the installed system.
- **`publish-repo.sh`**: snapshots the working tree into that HTTP folder.
- **`serial.py`**: runs a command in the live image's root shell on the serial console.
- **`monitor.py`**: QEMU monitor commands: screenshots, and typing on the VM's keyboard.

The VM has no GPU, so `setup.sh` allows mango's software rendering when it runs in a VM
(`WLR_RENDERER_ALLOW_SOFTWARE=1` in `/etc/environment`); real machines don't get that.
