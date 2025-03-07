{ inputs, lib, pkgs, ... }: 
let
  config = ./. + "/../configs";
in
{
  nixpkgs = {
    overlays = [
      (final: pre: { statusbar = pre.callPackage (import ./statusbar.nix) { inherit pkgs; }; })
      (final: pre: { pythonScripts = pre.callPackage (import ./python-scripts.nix) { inherit pkgs lib; }; })
      (final: pre: { shellScripts = pre.callPackage (import ./shell-scripts.nix) { inherit pkgs lib; }; })
    ]; 
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true; # nix-community/home-manager/issues/2942
    };
  };

  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence

    ./firefox.nix
    ./i3.nix
  ];

  home = {
    username = "josh";
    homeDirectory = "/home/josh";
    pointerCursor = {
      package = pkgs.adwaita-icon-theme;
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
      "Games"
      ".gnupg"
      ".ssh"
      ".local/share/keyrings"
      ".local/share/direnv"
      ".cache/wine"
      ".local/state/wireplumber/" # pipewire (if switching to pulseaudio then save ".config/pulse")
      ".mozilla/firefox/josh" # todo: make this more granular so it just saves enabled extensions, layout, dismissed messages, sessions, etc. instead of everything
      ".local/share/Steam"
      ".local/share/mpd"
      ".local/share/vulkan"
      ".cache/mesa_shader_cache"
      ".config/spotify"
      ".config/gh"
    ];
    files = [
      ".screenrc"
      ".local/share/fish/fish_history" # persist fish history
    ];
    allowOther = true;
  };

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    bat
    black
    cargo
    cookiecutter
    discord
    dockerfile-language-server-nodejs
    fd
    ffmpeg
    gcc
    go
    gopls
    golangci-lint
    golangci-lint-langserver
    gruvbox-dark-gtk
    htop
    #inputs.nix-gaming.packages.${pkgs.system}.star-citizen # pkgs.system has problem with its existence when doing nixos-install
    iosevka
    jq
    keepassxc
    lxappearance-gtk2
    nil
    nodePackages.bash-language-server
    obsidian
    pagefind # TODO: move to dev flake in website
    pyright
    pythonScripts.workspaceNames
    ripgrep
    rustc
    rustlings
    spotify
    statusbar
    tree
    typst
    unzip
    warpd
    xfce.thunar
    yaml-language-server
    yt-dlp
    zip
  ];

  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile "${config}/fish/config.fish";
  };

  programs.fzf.enable = true;

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

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

  programs.sioyek = {
    enable = true;
    config = {
      "custom_color_contrast" = "0.3";
      "custom_color_mode_empty_background_color" = "#1d2021";
      "page_separator_color" = "#1d2021";
      "page_separator_width" = "10";
      "custom_background_color" = "#282828";
      "custom_text_color" = "#fbf1c7";
      "search_highlight_color" = "#7ec16e";
      "status_bar_color" = "#427b58";
      "status_bar_text_color" = "#fbf1c7";
    };
  };

  programs.tmux.enable = true;

  services.mpd = {
    enable = true;
    musicDirectory = "/home/josh/Music";
  };

  services.mpdris2.enable = true; # needed to use mpd with mpris dbus thingy

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

  home.stateVersion = "24.11"; # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
}
