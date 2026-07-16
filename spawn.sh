#!/bin/sh
set -e

missing=
for command in curl python3 virt-install virsh qemu-system-x86_64; do
  command -v "$command" >/dev/null 2>&1 || missing=1
done

if [ "$missing" ]; then
  sudo apt-get update
  sudo apt-get install -y curl python3 virtinst libvirt-daemon-system qemu-system-x86
fi
sudo systemctl enable --now libvirtd

ISO=ubuntu-24.04.4-desktop-amd64.iso
if [ ! -f "$ISO" ]; then
  curl -fL -C - -o "$ISO.part" "https://releases.ubuntu.com/noble/$ISO"
  mv "$ISO.part" "$ISO"
fi
python3 -m http.server 3003 --directory seed --bind 0.0.0.0 &
server=$!
trap 'kill "$server"' EXIT INT TERM

sudo virt-install \
  --name ubuntu-settings-test \
  --memory 4096 \
  --vcpus 2 \
  --disk size=32,bus=virtio \
  --os-variant ubuntu24.04 \
  --location "$ISO",kernel=casper/vmlinuz,initrd=casper/initrd \
  --extra-args 'autoinstall ds=nocloud-net;s=http://192.168.122.1:3003/' \
  --graphics spice
#  --noautoconsole
