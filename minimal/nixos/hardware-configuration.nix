# Example config, replace with generated hardware-configuration.nix
{
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  # Set system kind (needed for flakes)
  nixpkgs.hostPlatform = "x86_64-linux";
}
