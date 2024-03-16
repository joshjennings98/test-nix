#!/bin/sh

set -e

# List disks and prompt for which one to use
lsblk
read -p "Device to use (e.g. '/dev/sda'): " DEVICE

# Download disko configuration
#curl https://raw.githubusercontent.com/joshjennings98/test-nix/install-script/minimal/nixos/disko.nix -o /tmp/disko.nix
sudo cp minimal/nixos/disko.nix /tmp/disko.nix

# Set up partitions with disko
sudo nix --experimental-features "nix-command flakes" \
         run github:nix-community/disko -- \
         --mode disko /tmp/disko.nix \
         --arg device "\"$DEVICE\""

# Generate nix configuration files
sudo nixos-generate-config --no-filesystems --root /mnt

# Copy generated hardware-configuration.nix
cp /mnt/etc/nixos/hardware-configuration.nix minimal/nixos/hardware-configuration.nix

# Install nixos
sudo nixos-install --root /mnt --flake minimal#Ganymede
