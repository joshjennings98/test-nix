#!/bin/sh

set -e

# List disks and prompt for which one to use
lsblk -o NAME,SIZE,PATH
read -p "Device path to partition (e.g. '/dev/sda'): " DEVICE

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

# Fetch system flake
rm -rf $HOME/nix-cfg
mkdir $HOME/nix-cfg
cd $HOME/nix-cfg
sudo nix --experimental-features "nix-command flakes" flake init -t github:joshjennings98/test-nix#nix-cfg

# Copy generated hardware-configuration.nix and disko.nix
sudo cp /mnt/etc/nixos/hardware-configuration.nix $HOME/nix-cfg/nixos/
sudo cp /tmp/disko.nix $HOME/nix-cfg/nixos/

# Run the installation
sudo nixos-install --root /mnt --flake '.#Ganymede'

# Copy nix config to /persist
sudo cp -r $HOME/nix-cfg/ /mnt/persist/home/josh/
