#!/bin/bash
# Test setup.sh end to end in a VM on a Docker host: install onto a blank disk
# from the CachyOS live image, then boot the result, unlock the disk, and screenshot
# the desktop. Uses this repo's working tree, uncommitted changes included.
#   test/run.sh [HOST]        (default 192.168.0.12)
# Watch it at http://HOST:6080/vnc.html. Needs on HOST: Docker, /dev/kvm, and
# ~/dotfiles-test/ holding a cachyos-desktop-linux-*.iso (see test/README.md).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
host=${1:-192.168.0.12}
dir=dotfiles-test
key=${TEST_SSH_KEY:-$HOME/.ssh/dotfiles-test-vm}
out=${TEST_OUT:-$here/out}
mkdir -p "$out"
[[ -f $key ]] || ssh-keygen -q -t ed25519 -N '' -C dotfiles-test-vm -f "$key"

vm_ssh() {  # vm_ssh USER COMMAND: run in the VM, through the Docker host
  local user=$1; shift
  ssh -q -i "$key" -J "$host" -p 2223 -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "$user@127.0.0.1" "$@"
}
on_host() { ssh "$host" "cd ~/$dir && $1"; }
monitor() { on_host "python3 monitor.py monitor.sock $(printf '%q ' "$@")"; }
screenshot() {  # screenshot NAME
  monitor "screendump /work/screen.png -f png"
  scp -q "$host:$dir/screen.png" "$out/$1.png"
  echo "screenshot: $out/$1.png"
}
start_vm() {  # start_vm live|disk
  on_host "docker rm -f dotfiles-test-vm > /dev/null 2>&1; docker run -d --name dotfiles-test-vm \
    --memory 3.5g --memory-swap 3.5g --user \$(id -u):\$(id -g) --group-add \$(stat -c %g /dev/kvm) \
    --device /dev/kvm -e VM_BOOT=$1 -p $host:6080:6080 -p 127.0.0.1:2223:2222 \
    -v ~/$dir:/work dotfiles-test-vm > /dev/null"
}

echo "== Building the VM container on $host"
ssh "$host" "mkdir -p ~/$dir/build ~/$dir/www"
scp -q "$here/Dockerfile" "$here/vm.sh" "$host:$dir/build/"
scp -q "$here/serial.py" "$here/monitor.py" "$host:$dir/"
scp -q "$key.pub" "$host:$dir/www/id.pub"
on_host "docker build -q -t dotfiles-test-vm build > /dev/null"
"$here/publish-repo.sh" "$host:$dir"

echo "== Booting the live image"
start_vm live
# A root shell on the serial console: use it once, to let SSH in.
on_host "for i in \$(seq 100); do timeout 20 python3 serial.py serial.sock \
  'systemctl is-active sshd > /dev/null && mkdir -p /root/.ssh && curl -fs http://10.0.2.2:8000/id.pub > /root/.ssh/authorized_keys && echo KEYOK' 15 2>/dev/null \
  | grep -q KEYOK && exit 0; sleep 5; done; echo 'live VM never came up'; exit 1"

echo "== Running setup.sh (password and disk passphrase: test)"
vm_ssh root 'cat > /root/answers << EOF
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
git clone -q http://10.0.2.2:8000/dotfiles.git /root/dotfiles && chvt 1 && clear > /dev/tty1
nohup bash -c "SETUP_ANSWERS=/root/answers DOTFILES_REPO=http://10.0.2.2:8000/dotfiles.git bash /root/dotfiles/setup.sh 2>&1 | tee /dev/tty1 > /root/setup.log; echo EXIT \${PIPESTATUS[0]} >> /root/setup.log" > /dev/null 2>&1 < /dev/null &'
until vm_ssh root 'grep -q "^EXIT" /root/setup.log' 2> /dev/null; do sleep 30; done
vm_ssh root 'sed "s/\x1b\[[0-9;]*[mK]//g" /root/setup.log' > "$out/setup.log"
status=$(tail -1 "$out/setup.log")
echo "setup.sh: $status (log: $out/setup.log)"
[[ $status == "EXIT 0" ]] || exit 1

echo "== Booting the installed system"
start_vm disk
sleep 30
screenshot 1-passphrase
monitor "sendkey t" "sendkey e" "sendkey s" "sendkey t" "sendkey ret"
sleep 60
screenshot 2-desktop
echo "== Done. Look at the screenshots; the VM keeps running until: ssh $host docker rm -f dotfiles-test-vm"
