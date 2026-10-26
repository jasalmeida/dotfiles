#!/bin/bash
# Snapshot this repo's working tree (uncommitted changes included) as a git repo
# the test VM clones over plain HTTP, at http://10.0.2.2:8000/dotfiles.git, and
# copy it into the test folder's www/ (a local path or HOST:PATH).
# Rerun after each edit.
#   test/publish-repo.sh 192.168.0.12:cachyos-usb
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
dest=${1:?usage: publish-repo.sh TEST_FOLDER (local path or HOST:PATH)}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone -q "$repo" "$tmp/work"
rsync -a --delete --exclude .git "$repo/" "$tmp/work/"
git -C "$tmp/work" add -A
git -C "$tmp/work" -c user.name=test -c user.email=test@test commit -qm "test snapshot" || true
git clone -q --bare "$tmp/work" "$tmp/dotfiles.git"
git -C "$tmp/dotfiles.git" update-server-info
rsync -a --delete "$tmp/dotfiles.git" "$dest/www/"
echo "published $(git -C "$tmp/dotfiles.git" rev-parse --short HEAD) to $dest/www/dotfiles.git"
