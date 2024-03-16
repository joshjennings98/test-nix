#!/bin/sh

set -e

# List disks and prompt for which one to use
lsblk
read -p "Device to use (e.g. '/dev/sda'): " DEVICE

# Download disko configuration
curl https://raw.githubusercontent.com/joshjennings98/test-nix/install-script/minimal/nixos/disko.nix -o /tmp/disko.nix

# Set up partitions with disko
sudo nix --experimental-features "nix-command flakes" \
         run github:nix-community/disko -- \
         --mode disko /tmp/disko.nix \
         --arg device "\"$DEVICE\""

# Generate nix configuration files
sudo nixos-generate-config --no-filesystems --root /mnt

# Copy dotfiles from remote
cd /mnt/etc/nixos
nix flake init -t github:joshjennings98/test-nix#minimal

# Copy hardware configuration (note: make sure volumes match in configuration.nix)
cp /etc/nixos/hardware-configuration.nix nixos/hardware-configuration.nix

# Persist files
cp -r /etc/nixos /persist

# Install nixos
#sudo nixos-install --root /mnt --flake .#Ganymede
