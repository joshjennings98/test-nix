{ pkgs, inputs, outputs, ... }: {
  imports = [
    inputs.home-manager.nixosModules.home-manager # Import home-manager's NixOS module
  ];

  home-manager = {
    extraSpecialArgs = { inherit inputs outputs; };
    users = {
      josh = import ../users/josh/home.nix;
    };
  };

  users = {
    mutableUsers = false;
    users = {
      josh = {
        hashedPasswordFile = "/persist/passwords/josh";
        isNormalUser = true;
        openssh.authorizedKeys.keys = []; # add SSH public key(s) here
        extraGroups = [ "networkmanager" "wheel" "docker" ];
        shell = pkgs.fish;
      };
      root.hashedPassword = "!"; # can replace hashed password with ! (or !*) since no hash function will evaluate to it https://wiki.archlinux.org/title/Sudo#Disable_root_login
    };
  };
}
