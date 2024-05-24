{ inputs, lib, pkgs, ... }: 
let
  config = ./. + "/../configs";
in
{
  nixpkgs = {
    overlays = [
      (final: pre: {
        statusbar = pre.callPackage (import ./statusbar.nix) { inherit pkgs; };
      })
    ]; # Add overlays here either from flakes or inline (see https://github.com/Misterio77/nix-starter-configs/blob/main/minimal/nixos/configuration.nix and https://github.com/Misterio77/nix-config/tree/main/overlays) 
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true; # nix-community/home-manager/issues/2942
    };
  };

  # Import other home-manager modules here (either via flakes like inputs.xxx.yyy or directly like ./zzz.nix)
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence

    ./firefox.nix
    ./sway.nix
    ./i3.nix
  ];

  # Custom options for ./wayland.nix and ./xorg.nix
  windowManagers.sway.enable = false;
  windowManagers.i3.enable = true;

  home = {
    username = "josh";
    homeDirectory = "/home/josh";
    pointerCursor = {
      package = pkgs.gnome.adwaita-icon-theme;
      name = "Adwaita";
      size = 16;
    };
  };

  home.persistence."/persist/home/josh" = {
    directories = [
      "Downloads"
      "Music"
      "Pictures"
      "Documents"
      "Videos"
      ".gnupg"
      ".ssh"
      ".local/share/keyrings"
      ".local/share/direnv"
      ".config/pulse" # pulseaudio
      ".mozilla/firefox/josh" # todo: make this more granular so it just saves enabled extensions, layout, dismissed messages, sessions, etc. instead of everything
      ".local/share/Steam"
      ".local/share/vulkan"
      ".cache/mesa_shader_cache"
      ".config/spotify"
    ];
    files = [
      ".screenrc"
      ".local/share/fish/fish_history" # persist fish history
    ];
    allowOther = true;
  };

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    babashka
    black
    clojure-lsp
    discord
    dockerfile-language-server-nodejs
    go
    gopls
    golangci-lint
    golangci-lint-langserver
    gruvbox-dark-gtk
    iosevka
    htop
    jq
    keepassxc
    lxappearance-gtk2
    mockgen
    nil
    nodePackages.bash-language-server
    obsidian
    pyright
    spotify
    statusbar
    tree
    typst
    unzip
    xfce.thunar
    yaml-language-server
    yt-dlp
  ];

  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile "${config}/fish/config.fish";
  };

  programs.fzf.enable = true;

  programs.git = {
    enable = true;
    userName = "Josh";
    userEmail = "josh@joshj.dev";
    extraConfig.push.autoSetupRemote = true;
    difftastic.enable = true;
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
    settings = {
      shell = "${pkgs.fish}/bin/fish";
    };
    extraConfig = builtins.readFile "${config}/kitty/kitty.conf";
  };

  programs.mpv.enable = true;

  programs.ncmpcpp.enable = true;

  programs.tmux.enable = true;

  programs.zathura.enable = true;

  services.mpd = {
    enable = true;
    musicDirectory = "/home/josh/Music";
  };

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

  systemd.user.startServices = "sd-switch"; # Nicely reload system units when changing configs

  home.stateVersion = "23.11"; # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
}
