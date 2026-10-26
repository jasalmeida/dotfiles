#!/bin/bash
# Test the custom USB end to end in a VM on a Docker host: its Install entry
# installs onto a blank disk by itself, then the result boots, the disk is
# unlocked, and the desktop is screenshotted. Uses this repo's working tree,
# uncommitted changes included, for setup.sh; the USB image itself comes from
# iso/build.sh, so rebuild that after changing iso/.
#   test/run.sh [HOST]        (default 192.168.0.12)
# Watch it at http://HOST:6080/vnc.html. See test/README.md.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
host=${1:-192.168.0.12}
dir=cachyos-usb
out=${TEST_OUT:-$here/out}
mkdir -p "$out"

on_host() { ssh "$host" "cd ~/$dir && $1"; }
serial() { on_host "python3 serial.py serial.sock $(printf '%q' "$1") ${2:-30}"; }
monitor() { on_host "python3 monitor.py monitor.sock $(printf '%q ' "$@")"; }
screenshot() {  # screenshot NAME
  monitor "screendump /work/screen.png -f png"
  scp -q "$host:$dir/screen.png" "$out/$1.png"
  echo "screenshot: $out/$1.png"
}
start_vm() {  # start_vm auto|usb|disk
  on_host "docker rm -f dotfiles-test-vm > /dev/null 2>&1; docker run -d --name dotfiles-test-vm \
    --memory 3.5g --memory-swap 3.5g --user \$(id -u):\$(id -g) --group-add \$(stat -c %g /dev/kvm) \
    --device /dev/kvm -e VM_BOOT=$1 -p $host:6080:6080 -v ~/$dir:/work dotfiles-test-vm > /dev/null"
}

echo "== Building the VM container on $host"
ssh "$host" "mkdir -p ~/$dir/build ~/$dir/www"
scp -q "$here/Dockerfile" "$here/vm.sh" "$host:$dir/build/"
scp -q "$here/serial.py" "$here/monitor.py" "$host:$dir/"
on_host "docker build -q -t dotfiles-test-vm build > /dev/null"
"$here/publish-repo.sh" "$host:$dir"
on_host "cat > www/answers" << 'EOF'
full_name="Test User"
username=tester
password=test
git_name="Test User"
git_email=tester@example.com
hostname=test-vm
disk=vda
luks_passphrase=test
confirm_disk=vda
EOF

echo "== Installing from the USB image's Install entry (password and passphrase: test)"
start_vm auto
# Wait for the installer's last line, through the live image's serial root shell.
for i in $(seq 240); do
  status=$(serial 'grep -h "^EXIT" /var/log/dotfiles-setup.log 2> /dev/null | tail -1' 20 2> /dev/null | tr -d '\r' | grep -o 'EXIT [0-9]*' || true)
  [[ -n $status ]] && break
  (( i == 20 )) && screenshot 0-installer
  sleep 15
done
serial 'cat /var/log/dotfiles-setup.log' 120 | sed 's/\x1b\[[0-9;]*[mK]//g' > "$out/setup.log" || true
echo "setup.sh: ${status:-no result} (log: $out/setup.log)"
screenshot 1-finished
[[ $status == "EXIT 0" ]] || exit 1

echo "== Booting the installed system"
start_vm disk
sleep 30
screenshot 2-passphrase
monitor "sendkey t" "sendkey e" "sendkey s" "sendkey t" "sendkey ret"
sleep 60
screenshot 3-desktop
echo "== Done. Look at the screenshots; the VM keeps running until: ssh $host docker rm -f dotfiles-test-vm"
