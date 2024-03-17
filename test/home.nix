{ pkgs, inputs, ... }:

{ 
  imports = [

  ];

  home.stateVersion = "23.11"; # Please read the comment before changing.

  home = {
    username = "josh";
    homeDirectory = "/home/josh";
  };

  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist/system" = {
    hideMounts = true;
    directories = [
      "/etc/nixos"
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
  };

  programs.fuse.userAllowOther = true;

  programs.home-manager.enable = true;
}
