{ pkgs, lib, inputs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  services.openssh.enable = true;

  system.stateVersion = "23.11"; # Did you read the comment?

  users.users."josh" = {
    isNormalUser = true;
    initialPassword = "password";
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  };

  programs.fuse.userAllowOther = true;
  home-manager = {
    extraSpecialArgs = {inherit inputs;};
    users = {
      "josh" = import ./home.nix;
    };
  };
}
