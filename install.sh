#!/bin/bash
# Symlink these dotfiles into place. Existing files are moved to *.bak.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

link() {
  local src=$1 dest=$2
  mkdir -p "$(dirname "$dest")"
  if [[ -e $dest && ! -L $dest ]]; then
    mv "$dest" "$dest.bak"
    echo "backed up $dest -> $dest.bak"
  fi
  ln -sfn "$src" "$dest"
  echo "linked $dest"
}

for script in "$repo"/bin/*; do
  link "$script" "$HOME/.local/bin/$(basename "$script")"
done

for file in "$repo"/config/hypr/*.lua; do
  link "$file" "$HOME/.config/hypr/$(basename "$file")"
done
