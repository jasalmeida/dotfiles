# Testing setup.sh in a VM

`run.sh` installs a whole machine in a VM, from the CachyOS live image to the desktop,
using this repo's working tree (uncommitted changes included):

    test/run.sh 192.168.0.12

The VM runs in a Docker container on that host, so the host needs Docker (you in the
`docker` group), `/dev/kvm`, and the live image in `~/dotfiles-test/`:

    mkdir -p ~/dotfiles-test && cd ~/dotfiles-test
    curl -fLO https://cdn77.cachyos.org/ISO/desktop/260809/cachyos-desktop-linux-260809.iso
    curl -fLO https://cdn77.cachyos.org/ISO/desktop/260809/cachyos-desktop-linux-260809.iso.sha256
    sha256sum -c cachyos-desktop-linux-260809.iso.sha256

Watch it at `http://HOST:6080/vnc.html`. It answers `setup.sh`'s questions from a file
(user `tester`, password and disk passphrase `test`), then boots the installed disk,
types the passphrase, and saves screenshots and the install log in `test/out/`.

The container is capped at 3.5 GB of memory (the VM gets 2.5 GB), so a VM that runs short
is stopped on its own instead of squeezing the host. Remove it when done:
`ssh HOST docker rm -f dotfiles-test-vm`.

- **`Dockerfile`, `vm.sh`**: the container: QEMU (UEFI), noVNC, and an HTTP server the
  VM reaches at `10.0.2.2:8000` for the test copy of the repo. `VM_BOOT=disk` boots the
  installed disk instead of the live image.
- **`publish-repo.sh`**: snapshots the working tree into that HTTP folder.
- **`serial.py`**: runs a command in the live VM's root shell on its serial console
  (used once, to let SSH in).
- **`monitor.py`**: QEMU monitor commands: screenshots, and typing on the VM's keyboard.

The VM has no GPU, so `setup.sh` allows mango's software rendering when it runs in a VM
(`WLR_RENDERER_ALLOW_SOFTWARE=1` in `/etc/environment`); real machines don't get that.
