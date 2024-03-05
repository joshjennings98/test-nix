# README

```sh
mkdir nix-cfg
cd nix-cfg
export NIX_CONFIG="experimental-features = nix-command flakes"
nix flake init -t github:joshjennings98/test-nix#minimal
cp /etc/nixos/hardware-configuration.nix nixos/hardware-configuration.nix
sudo nixos-rebuild switch --flake .#Ganymede 
# how to get home manager to work without running the below command?
nix-shell --packages home-manager --run "home-manager switch --flake .#josh@Ganymede"
```
