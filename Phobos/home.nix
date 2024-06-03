{ lib, pkgs, ... }:
let
  config = ./.;
  homedir = "/home/josjen01";

  # TODO: make these overlays
  continuous-delivery-scripts = import ./continuous-delivery-scripts.nix { inherit pkgs; };
  detect-secrets-1-0-3 = pkgs.python312Packages.buildPythonPackage {
      pname = "detect-secrets";
      version = "1.0.3";
      buildInputs = with pkgs.python312Packages; [ pip requests pyyaml ];
      propagatedBuildInputs = [
        (pkgs.python312.withPackages (ps: with ps; [ pip requests pyyaml ]))
      ];
      src = pkgs.fetchFromGitHub {
        owner = "Yelp";
        repo = "detect-secrets";
        rev = "v1.0.3";
        sha256 = "sha256-O+V0u9urirhFNC7ExMRv5rO7dWbzPexywDdkLNGISIs=";
      };
    };
in
{
  home.username = "josjen01";
  home.homeDirectory = "${homedir}";

  home.packages = with pkgs; [
    awscli2
    black
    continuous-delivery-scripts
    # python312Packages.detect-secrets
    detect-secrets-1-0-3
    dockerfile-language-server-nodejs
    go
    golangci-lint
    golangci-lint-langserver
    gopls
    goreleaser
    gruvbox-dark-gtk
    iosevka
    keepassxc
    kubectl
    mockgen
    nil
    nixgl.nixGLIntel
    nodePackages.bash-language-server
    pyright
    sops
    tree
    xfce.thunar
    yaml-language-server
    yq-go
  ];

  home.file.".aws/config".source = "${config}/aws/config"; 
  home.file.".aws/credentials".source = "${config}/aws/credentials"; 

  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile "${config}/fish/config.fish";
  };
  
  programs.fzf.enable = true;

  programs.git = {
    enable = true;
    userName = "joshjennings98";
    userEmail = "josh.jennings@arm.com";
    extraConfig = {
      push.autoSetupRemote = true;
    };
    difftastic.enable = true;
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true; # should work for private go modules tool
  };

  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings = lib.importTOML "${config}/helix/config.toml";    
    languages = lib.importTOML "${config}/helix/languages.toml";    
  };

  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    theme = "Gruvbox Dark";
    font = {
      name = "Iosevka";
      size = 12;
    };
    # Kitty needs OpenGL to work properly so make the changes to how the binary is executed https://pmiddend.github.io/posts/nixgl-on-ubuntu/
    package = pkgs.writeShellScriptBin "kitty" ''
      #!/bin/sh
      ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.kitty}/bin/kitty "$@"
    '';
    settings = {
      shell = "${pkgs.fish}/bin/fish";
    };
    extraConfig = builtins.readFile "${config}/kitty/kitty.conf";
  };

  xdg = {
    enable = true;
    desktopEntries = {
      kitty = {
        name = "Kitty";
        genericName = "Terminal";
        exec = "kitty";
        icon = "${pkgs.kitty}/share/icons/hicolor/256x256/apps/kitty.png";
        terminal = false;
        categories = [ "Utility" ];
      };
    };
  };

  # This will need the equivalen of 'programs.dconf.enable = true;' on whatever system this is run on
  gtk = {
    enable = true;
    font = {
      name = "Iosevka";
      size = 10;
    };
    theme = {
      name = "gruvbox-dark";
      package = "${pkgs.gruvbox-dark-gtk}";
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.stateVersion = "23.11"; # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
}
