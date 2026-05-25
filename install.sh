#!/bin/sh

set -e

no_lock=false
ref=""

# Parse args
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-lock)
      no_lock=true
      shift
      ;;
    --ref)
      if [ -n "$2" ]; then
        ref="$2"
        shift 2
      else
        echo "Error: --ref requires a value"
        exit 1
      fi
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

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
              type = "luks";
              name = "crypted";
              settings.allowDiscards = true;
              content = {
                type = "lvm_pv";
                vg = "root_vg";
              };
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
rm -rf "$HOME/nix-config"
mkdir "$HOME/nix-config"
cd "$HOME/nix-config"
if [ -z "$ref" ]; then
  nix --experimental-features "nix-command flakes" flake init -t github:joshjennings98/test-nix#Ganymede
else
  nix --experimental-features "nix-command flakes" flake init -t "github:joshjennings98/test-nix/$ref#Ganymede"
fi

# Copy generated hardware-configuration.nix and disko.nix (source files are
# world-readable so no sudo needed; destination is user-owned)
cp /mnt/etc/nixos/hardware-configuration.nix "$HOME/nix-config/nixos/"
cp /tmp/disko.nix "$HOME/nix-config/nixos/"

# Optionally delete flake.lock to get latest packages
if [ "$no_lock" = true ]; then
  rm "$HOME/nix-config/flake.lock"
fi

# Hash user password to file
sudo mkdir -p /mnt/persist/passwords
mkpasswd -m sha-512 | sudo tee /mnt/persist/passwords/josh > /dev/null

# Run the installation
sudo nixos-install --no-root-passwd --root /mnt --flake '.#Ganymede'

# Copy nix config to /persist so impermanence picks it up after reboot.
# The 'josh' user doesn't exist yet on the live ISO, so chown by numeric
# uid/gid (first NixOS-managed user lands at 1000:100 by default).
sudo mkdir -p /mnt/persist/home/josh
sudo cp -r "$HOME/nix-config" /mnt/persist/home/josh/
sudo chown -R 1000:100 /mnt/persist/home/josh
