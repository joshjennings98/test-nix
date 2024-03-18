#!/bin/sh

set -e

# List disks and prompt for which one to use
lsblk
read -p "Device to use (e.g. '/dev/sda'): " DEVICE

# Make disko configuration
cat << EOF > "/tmp/disko.nix"
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "$DEVICE";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # for grub MBR
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
EOF

# Partition drive
sudo nix \
 --experimental-features "nix-command flakes" \
 run github:nix-community/disko -- \
 --mode disko /tmp/disko.nix

# Create nix config files (--no-filesystems because it is handled by disko, --root so we create them in /mnt/etc/nixos)
sudo nixos-generate-config --no-filesystems --root /mnt

# Convert generated nixos dir into flake (with disko and home-manager support etc.)
cat << EOF > "/mnt/etc/nixos/flake.nix"
{
  description = "Josh's NixOS Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs"; # use the same version of nixpkgs as specified in the current flake 
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    ...
  } @ inputs: let
    inherit (self) outputs;
  in {
    # Reload with 'nixos-rebuild --flake .#Ganymede'
    nixosConfigurations = {
      Ganymede = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        modules = [
          inputs.disko.nixosModules.default
          (import ./disko.nix { device = "$DEVICE"; })
          ./configuration.nix
        ];
      }; 
    };
  };
}
EOF

# Include the disko configuration
mv /tmp/disko.nix /mnt/etc/nixos/

# Create configuration.nix
rm /mnt/etc/nixos/configuration.nix
cat << EOF > "/mnt/etc/nixos/configuration.nix"
{ inputs, lib, config, pkgs, ...}: 
{
  # Import other home-manager modules here (either via flakes like inputs.xxx.yyy or directly like ./zzz.nix)
  imports = [
    ./disko-config.nix
    ./hardware-configuration.nix
  ];

  # Global nixpkgs settings
  nixpkgs = {
    overlays = [ ]; # Add overlays here either from flakes or inline (see https://github.com/Misterio77/nix-starter-configs/blob/main/minimal/nixos/configuration.nix and https://github.com/Misterio77/nix-config/tree/main/overlays) 
    config = {
      allowUnfree = true;
    };
  };

  # This will add each flake input as a registry to make nix3 commands consistent with this flake
  nix.registry = (lib.mapAttrs (_: flake: {inherit flake;})) ((lib.filterAttrs (_: lib.isType "flake")) inputs);

  # Add the inputs to the system's legacy channels making legacy nix commands consistent as well!
  nix.nixPath = [ "/etc/nix/path" ];
  environment.etc =
    lib.mapAttrs'
    (name: value: {
      name = "nix/path/${name}";
      value.source = value.flake;
    })
    config.nix.registry;

  # Settings for NixOS
  nix.settings = {
    experimental-features = "nix-command flakes"; # Enable flakes and new 'nix' command
    auto-optimise-store = true; # Deduplicate and optimize nix store
  };

  # Setup for GRUB
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  # Kernel options
  boot.kernelParams = [
    "quiet" # Don't print SystemD startup stuff
  ];

  # System-wide user settings (groups, etc.)
  users.users = {
    josh = {
      initialPassword = "password"; # Be sure to change me (using passwd)
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        # Add SSH public key(s) here.
      ];
      extraGroups = [ "networkmanager" "wheel" "docker" ];
      shell = pkgs.fish;
    };
  };

  # Use greetd (CLI greeter) for login
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --user-menu --cmd sway";
      };
    };
  };

  # Homemanager can't manage default shell and sway needs to be available for greetd
  programs.fish.enable = true;
  programs.sway.enable = true;

  # Global environment variables
  environment.sessionVariables = rec {
    WLR_NO_HARDWARE_CURSORS = "1"; # for sway/wayland in virtualbox
  };

  # Networking stuff
  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [];
      allowedUDPPorts = [];
    };
    hostName = "Ganymede";
    networkmanager.enable = true;
  };

  # Misc settings
  time.timeZone = "London/Europe";
  i18n = {
    defaultLocale = "en_GB.UTF-8";
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.11";
}
EOF

# Run the installation
sudo nixos-install --root /mnt --flake '/mnt/etc/nixos#Ganymede'
