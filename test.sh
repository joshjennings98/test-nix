#!/bin/sh

set -e

# List disks and prompt for which one to use
lsblk
read -p "Device to use (e.g. '/dev/sda'): " DEVICE

# Make disko configuration
rm -f "/tmp/disko.nix"
cat << EOF > "/tmp/disko.nix"
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "$DEVICE";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02";
          };
          esp = {
            name = "ESP";
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          swap = {
            size = "4G";
            content = {
              type = "swap";
              resumeDevice = true;
            };
          };
          root = {
            name = "root";
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "root_vg";
            };
          };
        };
      };
    };
    lvm_vg = {
      root_vg = {
        type = "lvm_vg";
        lvs = {
          root = {
            size = "100%FREE";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];

              subvolumes = {
                "/root" = {
                  mountpoint = "/";
                };

                "/persist" = {
                  mountOptions = ["subvol=persist" "noatime"];
                  mountpoint = "/persist";
                };

                "/nix" = {
                  mountOptions = ["subvol=nix" "noatime"];
                  mountpoint = "/nix";
                };
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
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/disko.nix

# Create nix config files (--no-filesystems because it is handled by disko, --root so we create them in /mnt/etc/nixos)
sudo nixos-generate-config --no-filesystems --root /mnt

# Convert generated nixos dir into flake (with disko and home-manager support etc.)
rm -f "/tmp/flake.nix"
cat << EOF > "/tmp/flake.nix"
{
  description = "Josh's NixOS Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs"; # use the same version of nixpkgs as specified in the current flake 
    };

    impermanence.url = "github:nix-community/impermanence";

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
          ./configuration.nix
        ];
      }; 
    };
  };
}
EOF

# Create configuration.nix
rm -f "/tmp/configuration.nix"
cat << EOF > "/tmp/configuration.nix"
{ inputs, lib, config, pkgs, ...}: 
{
  # Import other home-manager modules here (either via flakes like inputs.xxx.yyy or directly like ./zzz.nix)
  imports = [
    ./hardware-configuration.nix
    
    inputs.disko.nixosModules.default
    ./disko.nix

    ./impermanence.nix
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
      name = "nix/path/\${name}";
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
        command = "\${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --user-menu --cmd sway";
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

# Create impermanence.nix
rm -f "/tmp/impermanence.nix"
cat << EOF > "/tmp/impermanence.nix"
{ lib, pkgs, inputs, ... }: {

  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  boot.initrd.postDeviceCommands = lib.mkAfter ''
  
  # Mount old root
  mkdir /btrfs_tmp
  mount /dev/root_vg/root /btrfs_tmp

  # Backup previous root
  if [[ -e /btrfs_tmp/root ]]; then
    mkdir -p /btrfs_tmp/old_roots
    timestamp=\$(date --date="@\$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
    mv /btrfs_tmp/root "/btrfs_tmp/old_roots/\$timestamp"
  fi

  # Delete backups older than 7 days
  delete_subvolume_recursively() {
    IFS=$'\n'
    for i in \$(btrfs subvolume list -o "\$1" | cut -f 9- -d ' '); do
      delete_subvolume_recursively "/btrfs_tmp/\$i"
    done
    btrfs subvolume delete "$1"
  }

  for i in \$(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +7); do
    delete_subvolume_recursively "\$i"
  done

  # Create new clean root    
  btrfs subvolume create /btrfs_tmp/root
  umount /btrfs_tmp
  '';

  environment.persistence."/persistent" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      { directory = "/var/lib/colord"; user = "colord"; group = "colord"; mode = "u=rwx,g=rx,o="; }
    ];
    files = [
      "/etc/machine-id"
      { file = "/var/keys/secret_file"; parentDirectory = { mode = "u=rwx,g=,o="; }; }
    ];
    users.josh = {
      directories = [
        "Downloads"
        "Music"
        "Pictures"
        "Documents"
        "Videos"
        "VirtualBox VMs"
        { directory = ".gnupg"; mode = "0700"; }
        { directory = ".ssh"; mode = "0700"; }
        { directory = ".nixops"; mode = "0700"; }
        { directory = ".local/share/keyrings"; mode = "0700"; }
        ".local/share/direnv"
      ];
      files = [
        ".screenrc"
      ];
    };
  };}
EOF

# Move nixos configuration files
sudo mv /tmp/configuration.nix /mnt/etc/nixos/
sudo mv /tmp/disko.nix         /mnt/etc/nixos/
sudo mv /tmp/flake.nix         /mnt/etc/nixos/
sudo mv /tmp/impermanence.nix  /mnt/etc/nixos/

# Run the installation
sudo nixos-install --root /mnt --flake '/mnt/etc/nixos#Ganymede'

