# README

```sh
mkdir nix-cfg
cd nix-cfg
export NIX_CONFIG="experimental-features = nix-command flakes"
nix flake init -t github:joshjennings98/test-nix#minimal
cp /etc/nixos/hardware-configuration.nix nixos/hardware-configuration.nix
sudo nixos-rebuild switch --flake .#Ganymede
home-manager switch --flake .#josh@Ganymede 
```
