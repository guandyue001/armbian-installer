#!/bin/bash
# Modified for ARM64 (Apple Silicon: M1/M2/M3/M4)

echo Install required tools
apt-get update
apt-get -y install debootstrap squashfs-tools xorriso grub-efi-arm64-bin mtools dosfstools parted

echo Create directory where we will make the image
mkdir -p $HOME/LIVE_BOOT

echo Install Debian for ARM64
debootstrap --arch=arm64 --variant=minbase buster $HOME/LIVE_BOOT/chroot http://ftp.us.debian.org/debian/

echo Copy supporting documents into the chroot
cp -v /supportFiles/installChroot.sh $HOME/LIVE_BOOT/chroot/installChroot.sh
cp -v /supportFiles/custom/ddd $HOME/LIVE_BOOT/chroot/usr/bin/ddd
chmod +x $HOME/LIVE_BOOT/chroot/usr/bin/ddd
cp -v /supportFiles/sources.list $HOME/LIVE_BOOT/chroot/etc/apt/sources.list

echo Mounting dev / proc / sys
mount -t proc none $HOME/LIVE_BOOT/chroot/proc
mount -o bind /dev $HOME/LIVE_BOOT/chroot/dev
mount -o bind /sys $HOME/LIVE_BOOT/chroot/sys

echo Run install script inside chroot
chroot $HOME/LIVE_BOOT/chroot /installChroot.sh

echo Cleanup chroot
rm -v $HOME/LIVE_BOOT/chroot/installChroot.sh
mv -v $HOME/LIVE_BOOT/chroot/packages.txt /output/packages.txt

echo Copy in systemd-networkd config
cp -v /supportFiles/99-dhcp-en.network $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network
chown -v root:root $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network
chmod -v 644 $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network

echo Enable autologin
mkdir -p -v $HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/
cp -v /supportFiles/override.conf $HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/override.conf

echo Unmounting dev / proc / sys
umount $HOME/LIVE_BOOT/chroot/proc
umount $HOME/LIVE_BOOT/chroot/dev
umount $HOME/LIVE_BOOT/chroot/sys

echo Create directories that will contain files for our live environment files and scratch files.
mkdir -p $HOME/LIVE_BOOT/{staging/{EFI/boot,boot/grub/arm64-efi,live},tmp}

echo Compress the chroot environment into a Squash filesystem.
cp /mnt/custom.img ${HOME}/LIVE_BOOT/chroot/mnt/
ls ${HOME}/LIVE_BOOT/chroot/mnt/
mksquashfs $HOME/LIVE_BOOT/chroot $HOME/LIVE_BOOT/staging/live/filesystem.squashfs -e boot

echo Copy kernel and initrd
cp -v $HOME/LIVE_BOOT/chroot/boot/vmlinuz-* $HOME/LIVE_BOOT/staging/live/vmlinuz
cp -v $HOME/LIVE_BOOT/chroot/boot/initrd.img-* $HOME/LIVE_BOOT/staging/live/initrd

echo Copy boot config files
cp -v /supportFiles/custom/grub.cfg $HOME/LIVE_BOOT/staging/boot/grub/grub.cfg
cp -v /supportFiles/grub-standalone.cfg $HOME/LIVE_BOOT/tmp/grub-standalone.cfg
touch $HOME/LIVE_BOOT/staging/DEBIAN_CUSTOM

echo Copy GRUB ARM64 modules
cp -v -r /usr/lib/grub/arm64-efi/* "${HOME}/LIVE_BOOT/staging/boot/grub/arm64-efi/"

echo Make UEFI grub standalone image (ARM64)
grub-mkstandalone --format=arm64-efi --output=$HOME/LIVE_BOOT/tmp/bootaa64.efi --locales=""  --fonts="" "boot/grub/grub.cfg=$HOME/LIVE_BOOT/tmp/grub-standalone.cfg"

cd $HOME/LIVE_BOOT/staging/EFI/boot
SIZE=`expr $(stat --format=%s $HOME/LIVE_BOOT/tmp/bootaa64.efi) + 65536`
dd if=/dev/zero of=efiboot.img bs=$SIZE count=1
/sbin/mkfs.vfat efiboot.img
mmd -i efiboot.img efi efi/boot
mcopy -vi efiboot.img $HOME/LIVE_BOOT/tmp/bootaa64.efi ::efi/boot/

echo Build ARM64 UEFI-only ISO
xorriso \
    -as mkisofs \
    -iso-level 3 \
    -o "${HOME}/LIVE_BOOT/debian-custom-arm64.iso" \
    -full-iso9660-filenames \
    -volid "DEBIAN_CUSTOM_ARM64" \
    -eltorito-alt-boot \
        -e /EFI/boot/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -append_partition 2 0xef ${HOME}/LIVE_BOOT/staging/EFI/boot/efiboot.img \
    "${HOME}/LIVE_BOOT/staging"

echo Copy output
cp -v $HOME/LIVE_BOOT/debian-custom-arm64.iso /output/custom-installer-arm64.iso
chmod -v 666 /output/custom-installer-arm64.iso
ls -lah /output
