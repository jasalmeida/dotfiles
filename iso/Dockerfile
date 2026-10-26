# Builds the custom USB image from the official CachyOS one; see iso/build.sh.
FROM archlinux:latest
RUN pacman -Syu --noconfirm --needed squashfs-tools xorriso libarchive && pacman -Scc --noconfirm
COPY remaster.sh /usr/local/bin/remaster.sh
CMD ["/usr/local/bin/remaster.sh"]
