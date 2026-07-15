#!/bin/sh

ISO=${1:?Usage: ./spawn.sh /path/to/ubuntu-desktop.iso}
python3 -m http.server 3003 --directory seed --bind 0.0.0.0 &
server=$!
trap 'kill "$server"' EXIT INT TERM

virt-install \
  --name ubuntu-settings-test \
  --memory 4096 \
  --vcpus 2 \
  --disk size=32,bus=virtio \
  --os-variant ubuntu24.04 \
  --location "$ISO",kernel=casper/vmlinuz,initrd=casper/initrd \
  --extra-args 'autoinstall ds=nocloud-net;s=http://192.168.122.1:3003/' \
  --graphics spice \
  --noautoconsole
