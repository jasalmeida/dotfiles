#!/bin/bash
# Build the custom USB image on a Docker host, from the official CachyOS image
# there and this repo's working tree (uncommitted changes included).
#   iso/build.sh [HOST]        (default 192.168.0.12)
# HOST needs Docker and ~/cachyos-usb/ holding a cachyos-desktop-linux-*.iso
# (see test/README.md). The result lands in HOST:~/cachyos-usb/out/.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
host=${1:-192.168.0.12}
dir=cachyos-usb
commit=$(git -C "$repo" rev-parse --short HEAD)
git -C "$repo" diff --quiet HEAD -- . ':!test/out' || commit+="+changes"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rsync -a --exclude .git --exclude test/out "$repo/" "$tmp/src/"
tar -C "$tmp/src" -cf "$tmp/src.tar" .

ssh "$host" "mkdir -p ~/$dir/iso-build && rm -rf ~/$dir/iso-src && mkdir ~/$dir/iso-src"
scp -q "$here/Dockerfile" "$here/remaster.sh" "$host:$dir/iso-build/"
scp -q "$tmp/src.tar" "$host:$dir/iso-src.tar"
ssh "$host" "cd ~/$dir && tar -xf iso-src.tar -C iso-src && rm iso-src.tar &&
  docker build -q -t dotfiles-iso-builder iso-build > /dev/null &&
  docker run --rm -e COMMIT=$commit -e OWNER=\$(id -u):\$(id -g) -v ~/$dir:/work -v ~/$dir/iso-src:/src:ro dotfiles-iso-builder"

# Publish to Forgejo's package registry as cachyos-usb, version RELEASE-COMMIT, so
# every image can be traced to the commit it was built from: only builds of
# committed code, and only with an upload token (package: read and write) in
# HOST:~/.config/cachyos-usb/forgejo-token.
if [[ $commit == *+changes ]]; then
  echo "Not published to Forgejo: built from uncommitted changes."
  exit 0
fi
ssh "$host" bash -s -- "$commit" << 'REMOTE'
set -euo pipefail
commit=$1
token_file=~/.config/cachyos-usb/forgejo-token
[[ -f $token_file ]] || { echo "Not published to Forgejo: no token in $token_file."; exit 0; }
cd ~/cachyos-usb/out
iso=$(ls jasalmeida-cachyos-*.iso | sort | tail -1)
release=${iso%.iso}; release=${release##*-}
base=http://localhost:3000/api/packages/jalmeida/generic/cachyos-usb/$release-$commit
for file in "$iso" "$iso.sha256"; do
  # The token goes to curl on stdin, so it doesn't show up in ps.
  status=$(printf 'user = "jalmeida:%s"\n' "$(< "$token_file")" |
    curl -sS --config - -o /dev/null -w '%{http_code}' --upload-file "$file" "$base/$file")
  case $status in
    201) echo "published $file" ;;
    409) echo "already published: $file" ;;
    *)   echo "upload of $file failed (HTTP $status)" >&2; exit 1 ;;
  esac
done
echo "Forgejo: http://192.168.0.12:3000/jalmeida/-/packages/generic/cachyos-usb/$release-$commit"
REMOTE
