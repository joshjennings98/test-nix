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
}
