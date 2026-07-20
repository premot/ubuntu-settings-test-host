#!/bin/sh
set -eu

# Provide spawn.sh's command-line dependencies in a temporary Nix environment.
# Packages are downloaded to the Nix store, but no NixOS configuration is changed.
#
# spawn.sh expects libvirtd to be enabled and running. On NixOS, add this to
# /etc/nixos/configuration.nix and apply it before running this script:
#
#   virtualisation.libvirtd.enable = true;
#
#   sudo nixos-rebuild switch
exec nix-shell \
  -p curl python3 virt-manager libvirt qemu \
  --run './spawn.sh'
