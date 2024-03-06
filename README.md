# README

This repo contains a NixOS configuration as well as a script to set it up. It does this using flakes.

## Usage

This sets up nix-os with the user being `josh` and the hostname being `Ganymede`. 

It assumes the system is using grub with `boot.loader.grub.device = "/dev/sda"`.

*Note: It will create the directory `nix-cfg`.*

```sh
curl -o install.sh https://raw.githubusercontent.com/joshjennings98/test-nix/main/install.sh
bash install.sh
```
