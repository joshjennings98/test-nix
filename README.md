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

## Virtualbox

* When using virtualbox make sure that 3D acceleration is enabled.

* Sway needs the following variable set in `configuration.nix`:
  
  ```nix
  environment.sessionVariables = rec {
    WLR_NO_HARDWARE_CURSORS = "1"; # for sway/wayland in virtualbox
  };
  ```

* Kitty needs to be launced with the following variables: `LIBGL_ALWAYS_SOFTWARE=true GALLIUM_DRIVER=llvmpipe kitty`
