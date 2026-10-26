# A VM host in a container, for testing setup.sh on a machine where you can't
# use /dev/kvm directly but can run Docker. See test/README.md.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      qemu-system-x86 qemu-utils ovmf novnc websockify python3 libarchive-tools \
    && rm -rf /var/lib/apt/lists/*
COPY vm.sh /usr/local/bin/vm.sh
CMD ["/usr/local/bin/vm.sh"]
