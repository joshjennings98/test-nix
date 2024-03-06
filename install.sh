#!/bin/sh

set -e

# This sets up nix-os with the user being `josh` and the hostname being `Ganymede`. It assumes the system is using grub with `boot.loader.grub.device = "/dev/sda"`

mkdir nix-cfg
cd nix-cfg
export NIX_CONFIG="experimental-features = nix-command flakes"
nix flake init -t github:joshjennings98/test-nix#minimal
cp /etc/nixos/hardware-configuration.nix nixos/hardware-configuration.nix
sudo nixos-rebuild switch --flake .#Ganymede 
nix shell nixpkgs#home-manager --run "home-manager switch --flake .#josh@Ganymede"

echo 'Installation complete. Reboot? [y/N]' && read val && [[ "$val" == "y" ]] && sudo reboot;
