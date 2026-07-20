#!/bin/sh
set -e

missing=
for command in curl python3 virt-install virsh qemu-system-x86_64; do
  command -v "$command" >/dev/null 2>&1 || missing=1
done

if [ "$missing" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y curl python3 virtinst libvirt-daemon-system qemu-system-x86
  else
    echo "Missing dependencies. On NixOS, run ./spawn-nixos.sh after enabling virtualisation.libvirtd." >&2
    exit 1
  fi
fi
sudo systemctl enable --now libvirtd

# virt-install extracts --location kernels here. Some NixOS libvirt setups do
# not create this conventional directory, causing its transient "boot" pool
# to fail even though all packages are installed.
sudo install -d -m 0755 -o root -g root /var/lib/libvirt/boot

# The unattended installer and seed URL require libvirt's default NAT network.
sudo virsh -c qemu:///system net-autostart default >/dev/null
if ! sudo virsh -c qemu:///system net-info default | grep -q '^Active:.*yes'; then
  sudo virsh -c qemu:///system net-start default >/dev/null
fi

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
