{ inputs, outputs, ... }: {
  imports = [
    inputs.home-manager.nixosModules.home-manager # Import home-manager's NixOS module
  ];

  home-manager = {
    extraSpecialArgs = { inherit inputs outputs; };
    users = {
      josh = import ../home-manager/home.nix;
    };
  };
}
