{ lib, pkgs, ... }:
let
  config = ./.;
  overlays = "${config}/overlays";
  homedir = "/home/josjen01";
in
{
  nixpkgs = {
    overlays = [
      (final: pre: { 
        continuous-delivery-scripts = pre.callPackage ("${overlays}/continuous-delivery-scripts.nix") { inherit pkgs; }; 
      })
      (final: pre: { 
        detect-secrets-1-0-3 = pre.callPackage ("${overlays}/detect-secrets-1-0-3.nix") { inherit pkgs; };
      })
    ];
    config.allowUnfree = true;
  };

  imports = [
    ./nvim
  ];

  home.username = "josjen01";
  home.homeDirectory = "${homedir}";

  home.packages = with pkgs; [
    awscli2
    bat
    black
    continuous-delivery-scripts
    dbeaver-bin
    detect-secrets-1-0-3
    delve
    dockerfile-language-server-nodejs
    emacs
    fd
    go
    golangci-lint
    golangci-lint-langserver
    gopls
    goreleaser
    gruvbox-dark-gtk
    iosevka
    keepassxc
    kubectl
    kubernetes-helm
    mockgen
    nil
    nixgl.nixGLIntel
    nsjail
    nodePackages.bash-language-server
    openapi-generator-cli
    python3
    pipenv # for ease of use with existing projects
    pyright
    ripgrep
    sops
    terraform
    tflint
    tilt
    tree
    typst
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
  
  home.file."fish/completions/kubectl".source = "${config}/fish/completions/kubectl"; 

  programs.firefox.enable = true;
  
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

  programs.sioyek.enable = true;

  xdg = {
    enable = true;
    mime.enable = true;
    systemDirs.data = [ "${homedir}/.nix-profile/share/applications" ];
    desktopEntries = {
      kitty = {
        name = "Kitty";
        genericName = "Terminal";
        exec = "kitty";
        icon = "${pkgs.kitty}/share/icons/hicolor/256x256/apps/kitty.png";
        terminal = false;
        categories = [ "Utility" ];
      };
      firefox = {
        name = "Firefox";
        genericName = "Web Browser";
        exec = "firefox %U";
        icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
        terminal = false;
        categories = [ "Utility" ];
      };
    };
  };

  # This will need the equivalent of 'programs.dconf.enable = true;' on whatever system this is run on
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

  # Enable settings to make home-manager work better on non-nixos systems
  targets.genericLinux.enable = true;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.stateVersion = "24.05"; # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
}
