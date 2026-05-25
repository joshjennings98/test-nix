{
  description = "Home Manager configuration for Phobos";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Kitty needs OpenGL to work properly https://pmiddend.github.io/posts/nixgl-on-ubuntu/
    nixgl.url = "github:nix-community/nixGL";
  };

  outputs = { 
    nixgl, 
    nixpkgs, 
    home-manager, 
    ... 
  } @ inputs: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [ nixgl.overlay ];
    };
  in {
    homeConfigurations = {
      josjen01 = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
        extraSpecialArgs = { inherit inputs; };
      };
    };
  };
}
