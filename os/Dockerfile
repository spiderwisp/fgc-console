FROM ubuntu:26.04@sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78
ENV DEBIAN_FRONTEND=noninteractive
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d && \
    apt-get update && apt-get install -y --no-install-recommends \
    systemd-sysv systemd-timesyncd dbus dbus-user-session libpam-systemd udev kmod linux-image-generic linux-firmware \
    initramfs-tools live-boot live-boot-initramfs-tools \
    grub-efi-amd64-bin grub-efi-amd64-signed grub-pc-bin grub2-common shim-signed efibootmgr \
    dosfstools parted gdisk e2fsprogs squashfs-tools xorriso mtools rsync \
    xserver-xorg-core xserver-xorg-input-libinput x11-xserver-utils xinit openbox lightdm \
    libgl1-mesa-dri mesa-vulkan-drivers libegl1 libgl1 libx11-6 libxcursor1 libxi6 \
    libxinerama1 libxrandr2 libxrender1 libasound2t64 libpulse0 \
    pipewire pipewire-pulse wireplumber alsa-utils pulseaudio-utils \
    network-manager wireless-regdb wpasupplicant bluez ca-certificates \
    python3 python3-gi gir1.2-nm-1.0 curl zstd unzip locales tzdata \
    plymouth plymouth-themes fonts-dejavu-core util-linux sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi
RUN useradd --create-home --uid 1000 --shell /bin/bash --groups audio,video,render,input fgc && \
    passwd -l root && passwd -l fgc && \
    systemctl mask getty@tty1.service getty@tty2.service getty@tty3.service getty@tty4.service getty@tty5.service getty@tty6.service && \
    systemctl enable NetworkManager lightdm && \
    rm -f /etc/machine-id /var/lib/dbus/machine-id && touch /etc/machine-id
WORKDIR /build
