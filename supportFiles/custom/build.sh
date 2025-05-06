#!/bin/bash
set -e

# 设置下载链接和保存目录
download_url="https://downloads.openwrt.org/releases/24.10.1/targets/armsr/armv8/openwrt-24.10.1-armsr-armv8-generic-squashfs-combined-efi.img.gz"
output_dir="$HOME/LIVE_BOOT"
mkdir -p imm "$output_dir"

echo "📥 下载 OpenWrt 镜像..."
curl -L "$download_url" -o imm/openwrt.img.gz
echo "✅ 下载成功!"

echo "🗜️ 解压..."
gzip -d -c imm/openwrt.img.gz > imm/custom.img
echo "✅ 解压成功"

# 安装依赖（基于 Debian Bookworm）
echo "📦 安装所需工具..."
apt-get update
apt-get install -y debootstrap squashfs-tools xorriso grub-efi-arm64-bin mtools dosfstools parted

echo "📁 创建构建目录..."
mkdir -p "$output_dir"/{chroot,staging/{EFI/boot,boot/grub/arm64-efi,live},tmp}

echo "📦 安装最小 Debian 系统到 chroot..."
debootstrap --arch=arm64 --variant=minbase bookworm "$output_dir/chroot" http://deb.debian.org/debian

echo "📂 拷贝 custom.img 到 chroot..."
cp imm/custom.img "$output_dir/chroot/mnt/"

echo "🧊 制作 squashfs..."
mksquashfs "$output_dir/chroot" "$output_dir/staging/live/filesystem.squashfs" -e boot

echo "📁 拷贝内核和 initrd..."
cp "$output_dir/chroot/boot/vmlinuz-"* "$output_dir/staging/live/vmlinuz"
cp "$output_dir/chroot/boot/initrd.img-"* "$output_dir/staging/live/initrd"

echo "⚙️ 配置 GRUB..."
cat <<EOF > "$output_dir/tmp/grub-standalone.cfg"
search --file --no-floppy --set=root /DEBIAN_CUSTOM
set default=0
set timeout=3
menuentry "OpenWrt Custom Installer (ARM64)" {
    linux /live/vmlinuz boot=live
    initrd /live/initrd
}
EOF

echo "📄 标记 ISO 内容..."
touch "$output_dir/staging/DEBIAN_CUSTOM"

echo "📁 拷贝 GRUB ARM64 模块..."
cp -r /usr/lib/grub/arm64-efi/* "$output_dir/staging/boot/grub/arm64-efi/"

echo "🧱 生成 EFI 启动镜像..."
grub-mkstandalone \
    --format=arm64-efi \
    --output="$output_dir/tmp/bootaa64.efi" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=$output_dir/tmp/grub-standalone.cfg"

cd "$output_dir/staging/EFI/boot"
SIZE=$(stat --format=%s "$output_dir/tmp/bootaa64.efi")
dd if=/dev/zero of=efiboot.img bs=1 count=0 seek=$((SIZE + 65536))
mkfs.vfat efiboot.img
mmd -i efiboot.img efi efi/boot
mcopy -vi efiboot.img "$output_dir/tmp/bootaa64.efi" ::efi/boot/

echo "🔥 制作最终 ISO..."
xorriso -as mkisofs \
  -iso-level 3 \
  -o "$output_dir/debian-custom-arm64.iso" \
  -full-iso9660-filenames \
  -volid "DEBIAN_CUSTOM_ARM64" \
  -eltorito-alt-boot \
      -e /EFI/boot/efiboot.img \
      -no-emul-boot \
      -isohybrid-gpt-basdat \
  -append_partition 2 0xef "$output_dir/staging/EFI/boot/efiboot.img" \
  "$output_dir/staging"

echo "📦 拷贝输出到 ./output 目录..."
mkdir -p ./output
cp "$output_dir/debian-custom-arm64.iso" ./output/custom-installer-arm64.iso
chmod 666 ./output/custom-installer-arm64.iso
ls -lh ./output

echo "✅ 全部完成！生成的 ISO 路径： ./output/custom-installer-arm64.iso"
