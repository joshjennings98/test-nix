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

  users.mutableUsers = false;
  users.users = {
    josh = {
      hashedPasswordFile = "/persist/passwords/josh";
      isNormalUser = true;
      openssh.authorizedKeys.keys = []; # add SSH public key(s) here
      extraGroups = [ "networkmanager" "wheel" "docker" ];
      shell = pkgs.fish;
    };
  };
}
