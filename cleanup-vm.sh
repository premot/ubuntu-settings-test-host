#!/bin/sh
# Remove the VM created by spawn.sh, including its attached file-backed disks.
set -eu

VM=ubuntu-settings-test
URI=qemu:///system

if ! command -v virsh >/dev/null 2>&1; then
  echo "virsh is required (install libvirt clients first)." >&2
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM

domain_exists=false
if sudo virsh -c "$URI" dominfo "$VM" >/dev/null 2>&1; then
  domain_exists=true
  # Record only writable VM disks, not installer/configuration CD-ROMs.
  sudo virsh -c "$URI" domblklist "$VM" --details \
    | awk '$1 == "file" && $2 == "disk" && $4 != "-" { print $4 }' >"$tmp"
elif sudo test -e "/var/lib/libvirt/images/$VM.qcow2"; then
  # A previously undefined domain can leave the default-name disk behind.
  echo "/var/lib/libvirt/images/$VM.qcow2" >"$tmp"
else
  echo "No '$VM' domain or default-name disk exists; nothing to clean up."
  exit 0
fi

echo "This will permanently delete domain '$VM' (if present), its snapshots,"
echo "managed-save/NVRAM state, and these file-backed disks:"
if [ -s "$tmp" ]; then
  sed 's/^/  /' "$tmp"
else
  echo "  (none found)"
fi

if [ "$domain_exists" = true ]; then
  state=$(sudo virsh -c "$URI" domstate "$VM" 2>/dev/null || true)
  case $state in
    shut\ off|shutoff) ;;
    *)
      echo "Stopping $VM..."
      sudo virsh -c "$URI" destroy "$VM" >/dev/null
      ;;
  esac

  # These may legitimately report that no corresponding state exists.
  sudo virsh -c "$URI" managedsave-remove "$VM" >/dev/null 2>&1 || true

  # Modern libvirt accepts both flags and removes snapshot metadata and UEFI NVRAM.
  # Fall back for older versions or domains without either kind of metadata.
  if ! sudo virsh -c "$URI" undefine "$VM" --snapshots-metadata --nvram >/dev/null 2>&1; then
    if ! sudo virsh -c "$URI" undefine "$VM" --snapshots-metadata >/dev/null 2>&1; then
      sudo virsh -c "$URI" undefine "$VM" >/dev/null
    fi
  fi
fi

while IFS= read -r disk; do
  [ -n "$disk" ] || continue
  sudo rm -f -- "$disk"
done <"$tmp"

echo "Removed $VM and its file-backed disks. You can now run ./spawn.sh."
