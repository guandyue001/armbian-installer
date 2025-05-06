#!/bin/bash
set -e

echo "📦 安装所需工具..."
apt-get update
apt-get install -y curl wget debootstrap squashfs-tools xorriso grub-efi-arm64-bin mtools dosfstools parted

echo "📁 创建工作目录..."
WORKDIR="$HOME/LIVE_BOOT"
CHROOT="$WORKDIR/chroot"
mkdir -p "$WORKDIR" "$CHROOT" "$WORKDIR/output"

echo "🌐 下载 OpenWrt 镜像..."
IMG_URL="https://downloads.openwrt.org/releases/24.10.1/targets/armsr/armv8/openwrt-24.10.1-armsr-armv8-generic-squashfs-combined-efi.img.gz"
IMG_PATH="$WORKDIR/openwrt.img.gz"
curl -L "$IMG_URL" -o "$IMG_PATH"
gunzip -c "$IMG_PATH" > "$WORKDIR/custom.img"

echo "📥 安装 Debian 到 chroot (ARM64)..."
debootstrap --arch=arm64 --variant=minbase buster "$CHROOT" http://ftp.us.debian.org/debian/

echo "🗂️ 拷贝支持文件..."
cp -v /supportFiles/installChroot.sh "$CHROOT/installChroot.sh"
cp -v /supportFiles/custom/ddd "$CHROOT/usr/bin/ddd"
chmod +x "$CHROOT/usr/bin/ddd"
cp -v /supportFiles/sources.list "$CHROOT/etc/apt/sources.list"
cp -v /supportFiles/99-dhcp-en.network "$CHROOT/etc/systemd/network/99-dhcp-en.network"
mkdir -p "$CHROOT/etc/systemd/system/getty@tty1.service.d/"
cp -v /supportFiles/override.conf "$CHROOT/etc/systemd/system/getty@tty1.service.d/override.conf"

echo "🔗 挂载 dev/proc/sys..."
mount -t proc none "$CHROOT/proc"
mount -o bind /dev "$CHROOT/dev"
mount -o bind /sys "$CHROOT/sys"

echo "🚀 执行 chroot 配置..."
chroot "$CHROOT" /installChroot.sh

echo "🧹 清理 chroot..."
rm -v "$CHROOT/installChroot.sh"
mv -v "$CHROOT/packages.txt" "$WORKDIR/output/packages.txt"

echo "📁 创建输出 staging 目录..."
mkdir -p "$WORKDIR/staging/EFI/boot"
mkdir -p "$WORKDIR/staging/boot/grub/arm64-efi"
mkdir -p "$WORKDIR/staging/live"
mkdir -p "$WORKDIR/tmp"

echo "📦 打包 squashfs..."
mkdir -p "$CHROOT/mnt"
cp "$WORKDIR/custom.img" "$CHROOT/mnt/"
mksquashfs "$CHROOT" "$WORKDIR/staging/live/filesystem.squashfs" -e boot

echo "📤 拷贝 kernel 和 initrd..."
cp -v "$CHROOT"/boot/vmlinuz-* "$WORKDIR/staging/live/vmlinuz"
cp -v "$CHROOT"/boot/initrd.img-* "$WORKDIR/staging/live/initrd"

echo "📄 拷贝 GRUB 配置文件..."
cp -v /supportFiles/custom/grub.cfg "$WORKDIR/staging/boot/grub/grub.cfg"
cp -v /supportFiles/grub-standalone.cfg "$WORKDIR/tmp/grub-standalone.cfg"
touch "$WORKDIR/staging/DEBIAN_CUSTOM"

echo "🧩 拷贝 GRUB ARM64 模块..."
cp -v -r /usr/lib/grub/arm64-efi/* "$WORKDIR/staging/boot/grub/arm64-efi/"

echo "⚙️ 构建 GRUB standalone EFI..."
grub-mkstandalone --format=arm64-efi --output="$WORKDIR/tmp/bootaa64.efi" --locales="" --fonts="" \
    "boot/grub/grub.cfg=$WORKDIR/tmp/grub-standalone.cfg"

echo "💾 制作 UEFI EFI 镜像..."
cd "$WORKDIR/staging/EFI/boot"
SIZE=$(expr $(stat --format=%s "$WORKDIR/tmp/bootaa64.efi") + 65536)
dd if=/dev/zero of=efiboot.img bs=$SIZE count=1
mkfs.vfat efiboot.img
mmd -i efiboot.img efi efi/boot
mcopy -vi efiboot.img "$WORKDIR/tmp/bootaa64.efi" ::efi/boot/

echo "📀 构建最终 ARM64 ISO..."
xorriso -as mkisofs \
    -iso-level 3 \
    -o "$WORKDIR/debian-custom-arm64.iso" \
    -full-iso9660-filenames \
    -volid "DEBIAN_CUSTOM_ARM64" \
    -eltorito-alt-boot \
    -e /EFI/boot/efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -append_partition 2 0xef "$WORKDIR/staging/EFI/boot/efiboot.img" \
    "$WORKDIR/staging"

echo "📤 复制输出..."
cp -v "$WORKDIR/debian-custom-arm64.iso" /output/custom-installer-arm64.iso
chmod -v 666 /output/custom-installer-arm64.iso
ls -lah /output

echo "✅ 构建完成!"
