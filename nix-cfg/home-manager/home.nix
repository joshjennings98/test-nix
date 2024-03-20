{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: 
{
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence
  ];

  programs.home-manager.enable = true;

  home.stateVersion = "23.11"; # Please read the comment before changing.

  home.homeDirectory = "/home/josh";

  home.persistence."/persist/home/josh" = {
    directories = [
      "Downloads"
      "Music"
      "Pictures"
      "Documents"
      "Videos"
      "VirtualBox VMs"
      ".gnupg"
      ".ssh"
      ".local/share/keyrings"
      ".local/share/direnv"
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
    ];
    files = [
      ".screenrc"
    ];
    allowOther = true;
  };
}
