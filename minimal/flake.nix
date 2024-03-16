{
  description = "Josh's NixOS Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    ...
  } @ inputs: let
    inherit (self) outputs;
  in {
    # Reload with 'nixos-rebuild --flake .#Ganymede'
    nixosConfigurations = {
      Ganymede = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        modules = [
          inputs.disko.nixosModules.default
          (import ./nixos/disko.nix { device = "/dev/sda"; }) # TODO: in script awk and replace with value in $DEVICE
          inputs.impermanence.nixosModules.impermanence
          ./nixos/configuration.nix
        ];
      };
    };

    # # Reload with 'home-manager --flake .#josh@Ganymede'
    # homeConfigurations = {
    #   "josh@Ganymede" = home-manager.lib.homeManagerConfiguration {
    #     pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
    #     extraSpecialArgs = { inherit inputs outputs; };
    #     modules = [
    #      ./home-manager/home.nix
    #     ];
    #   };
    # };
  };
}
