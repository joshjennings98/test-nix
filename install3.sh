#!/bin/sh

set -e

# List disks and prompt for which one to use
lsblk
read -p "Device to use (e.g. '/dev/sda'): " DEVICE

sudo nix --experimental-features "nix-command flakes" \
         run github:nix-community/disko -- \
         --mode disko test/disko.nix \
         --arg device "\"$DEVICE\""

sudo nixos-generate-config --no-filesystems --root /mnt

sudo cp -r test/* /mnt/etc/nixos/

sudo nixos-install --root /mnt --flake /mnt/etc/nixos#default
