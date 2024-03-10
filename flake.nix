{
  description = "Josh's NixOS + home-manager config flake with installation script";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
  };

  outputs = { nixpkgs, ... }: let
    forAllSystems = nixpkgs.lib.genAttrs [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  in {
    templates = {
      minimal = {
        description = ''
          Minimal flake, based off of https://github.com/Misterio77/nix-starter-configs
          TODO: rename this from minimal to something else.
        '';
        path = ./minimal;
      };
    };
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
