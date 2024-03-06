#!/bin/sh

set -e

###############################################################################################
#   This script sets up nix-os with the user being `josh` and the hostname being `Ganymede`   #
#       It assumes the system is using grub with `boot.loader.grub.device = "/dev/sda"`       #
###############################################################################################

# Create config directory
mkdir nix-cfg
cd nix-cfg

# Enable support for flakes
export NIX_CONFIG="experimental-features = nix-command flakes"

# Copy dotfiles from remote
nix flake init -t github:joshjennings98/test-nix#minimal

# Copy hardware configuration (note: make sure volumes match in configuration.nix)
cp /etc/nixos/hardware-configuration.nix nixos/hardware-configuration.nix

# Rebuild system based on downloaded flake
sudo nixos-rebuild switch --flake .#Ganymede

# Build home-manager stuff (run in home-manager shell since it isn't always available after the above nix-starter-configs/issues/12)
nix-shell --packages home-manager --run "home-manager switch --flake .#josh@Ganymede"

# Reboot
echo 'Installation complete. Reboot? [y/N]' && read val && [[ "$val" == "y" ]] && sudo reboot;
