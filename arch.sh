#!/usr/bin/env bash
set -e

### ---- USER PROMPTS ---- ###
read -rp "Hostname: " HOSTNAME
read -rp "Username: " USERNAME
read -rsp "Password: " PASSWORD
echo
read -rsp "Confirm Password: " PASSWORD2
echo

if [[ "$PASSWORD" != "$PASSWORD2" ]]; then
    echo "Passwords do not match."
    exit 1
fi

DISK="/dev/nvme0n1"

### ---- PARTITION DISK ---- ###
echo "Partitioning $DISK"

sgdisk -Z $DISK
sgdisk -n1:0:+1G -t1:ef00 -c1:EFI $DISK
sgdisk -n2:0:0   -t2:8300 -c2:ROOT $DISK

mkfs.fat -F32 ${DISK}p1
mkfs.ext4 ${DISK}p2

mount ${DISK}p2 /mnt
mkdir -p /mnt/efi
mount ${DISK}p1 /mnt/efi

### ---- MIRRORS + BASE INSTALL ---- ###
pacman -Sy --noconfirm

pacstrap -K /mnt base base-devel linux linux-firmware \
  networkmanager sudo vim git pipewire pipewire-alsa pipewire-pulse \
  pipewire-jack wireplumber gnome gnome-extra i3-wm i3status i3blocks \
  xorg xorg-server xdg-user-dirs

genfstab -U /mnt >> /mnt/etc/fstab

### ---- CHROOT CONFIGURATION ---- ###
arch-chroot /mnt /bin/bash <<EOF

# Timezone
ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc

# Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname + Hosts
echo "$HOSTNAME" > /etc/hostname
cat <<EOT > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
EOT

# User + Password
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

# Sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable services
systemctl enable NetworkManager
systemctl enable gdm
systemctl enable i3

# Bootloader (systemd-boot)
bootctl install
cat <<EOT > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value ${DISK}p2) rw
EOT

EOF

echo "Arch installation complete!"
echo "You may now reboot."

