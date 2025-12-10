{ config, lib, pkgs, ... }:
let
  cfg = ./.;
  overlays = "${cfg}/overlays";
  homedir = "/home/josjen01";
in
{
  nixpkgs = {
    overlays = [
      (final: pre: { 
        continuous-delivery-scripts = pre.callPackage ("${overlays}/continuous-delivery-scripts.nix") { inherit pkgs; }; 
      })
      (final: pre: {
        file-roller = config.lib.nixGL.wrap pre.file-roller;
      })
    ];
    config.allowUnfree = true;
  };

  imports = [
    ./i3.nix
  ];

  home.username = "josjen01";
  home.homeDirectory = "${homedir}";

  home.shell.enableFishIntegration = true;

  home.sessionVariables = {
    GIO_EXTRA_MODULES = "${pkgs.gvfs}/lib/gio/modules";
  };

  home.packages = with pkgs; [
    awscli2
    bat
    continuous-delivery-scripts
    detect-secrets
    delve
    dockerfile-language-server
    fd
    file-roller
    gnome.gvfs
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
    networkmanager
    nil
    nodePackages.bash-language-server
    openapi-generator-cli
    ripgrep
    sops
    terraform
    tflint
    tree
    xclip
    xdotool
    xfce.thunar
    xfce.thunar-archive-plugin
    yaml-language-server
    yq-go
    wmctrl
  ];

  home.file.".aws/config".source = "${cfg}/aws/config"; 
  home.file.".aws/credentials".source = "${cfg}/aws/credentials"; 
  home.file."Git/.keep".text = "ensure ~/Git directory exists";

  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile "${cfg}/fish/config.fish";
    shellInitLast = "source ~/fish/completions/kubectl";
  };
  
  home.file."fish/completions/kubectl".source = "${cfg}/fish/completions/kubectl"; 

  programs.difftastic.enable = true;
  
  programs.fzf.enable = true;

  programs.git = {
    enable = true;
    settings = {
      push.autoSetupRemote = true;
      user = {
        name = "joshjennings98";
        email = "josh.jennings@arm.com";
      };
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true; # should work for private go modules tool
  };

  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    font = {
      name = "Iosevka";
      size = 12;
    };
    package = config.lib.nixGL.wrap pkgs.kitty;
    settings = {
      shell = "${pkgs.fish}/bin/fish";
    };
    extraConfig = builtins.readFile "${cfg}/kitty/kitty.conf";
  };

  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings = lib.importTOML "${cfg}/helix/config.toml";    
    languages = lib.importTOML "${cfg}/helix/languages.toml";    
  };

  nixGL = {
    packages = pkgs.nixgl;
    vulkan.enable = true;
  };

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

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface".show-battery-percentage = true;
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

  home.stateVersion = "25.11"; # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
}
