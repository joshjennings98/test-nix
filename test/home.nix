{ pkgs, inputs, ... }:

{ 
  imports = [ ];

  home.stateVersion = "23.11"; # Please read the comment before changing.

  home = {
    username = "josh";
    homeDirectory = "/home/josh";
  };

  programs.home-manager.enable = true;
}
