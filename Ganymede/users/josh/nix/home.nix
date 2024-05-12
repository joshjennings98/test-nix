{ inputs, lib, config, pkgs, ... }: 
let
  config = ./. + "/../configs/";
  assets = ./. + "/../assets/";

  sway-bar = import ./sway-bar.nix { inherit pkgs; };
in 
{
  # Import other home-manager modules here (either via flakes like inputs.xxx.yyy or directly like ./zzz.nix)
  imports = with inputs; [
    inputs.impermanence.nixosModules.home-manager.impermanence

    ./firefox.nix
  ];

  nixpkgs = {
    overlays = [ ]; # Add overlays here either from flakes or inline (see https://github.com/Misterio77/nix-starter-configs/blob/main/minimal/home-manager/home.nix and https://github.com/Misterio77/nix-config/tree/main/overlays) 
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true; # nix-community/home-manager/issues/2942
    };
  };

  home = {
    username = "josh";
    homeDirectory = "/home/josh";
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
      ".config/pulse" # let pulseaudio maintain its cache for things like volume etc. (even though it is .config...)
      ".mozilla/firefox/josh" # todo: make this more granular so it just saves enabled extensions, layout, dismissed messages, sessions, etc. instead of everything
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
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
    discord
    go
    iosevka
    jq
    obsidian
    sway-bar
    tofi
    tree
    typst
    wl-clipboard
    yt-dlp
  ];

  home.file.".config/tofi/config".source = "${config}/tofi/tofi.conf"; # no home-manager options for tofi

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
  };

  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings = lib.importTOML "${config}/helix/config.toml";    
    languages = lib.importTOML "${config}/helix/languages.toml";    
    #themes = lib.importTOML "${config}/helix/themes/gruvbox.toml";    
  };

  programs.imv.enable = true;

  programs.joshuto = {
    enable = true;
    settings = {
      show_icons = false;
    };
    mimetype = {
      class = {
        image_default = [{
          command = "${pkgs.imv}/bin/imv";
          args = [];
          fork = true;
          silent = true;
        }];
      };
      extension = {
        png."inherit" = "image_default";
        jpg."inherit" = "image_default";
      };
    };
  };

  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    theme = "Gruvbox Dark";
    font = {
      name = "Iosevka";
      size = 12;
    };
  };

  programs.mpv.enable = true;

  programs.ncmpcpp.enable = true;

  programs.swaylock = {
    enable = true;
    settings.color = "000000";
  };

  programs.tmux.enable = true;

  programs.wpaperd = {
    enable = true;
    settings.default.path = "${assets}/wallpaper.jpg";
  };

  programs.zathura.enable = true;

  services.cliphist = {
    enable = true;
    systemdTarget = "sway-session.target";
  };

  services.mako.enable = true;

  services.mpd = {
    enable = true;
    musicDirectory = "/home/josh/Music";
  };

  services.swayidle = {
    enable = true;
    systemdTarget = "sway-session.target";
    timeouts = [
      { timeout = 300; command = "${pkgs.swaylock}/bin/swaylock"; }
    ];
  };

  wayland = {
    windowManager.sway = {
      enable = true;
      systemd.enable = true;
      config = rec {
        modifier = "Mod1";
        terminal = "LIBGL_ALWAYS_SOFTWARE=true GALLIUM_DRIVER=llvmpipe kitty"; # so kitty works in virtualbox
        menu = "tofi-run | xargs swaymsg exec";
        bars = [{ 
          statusCommand = "${sway-bar}/bin/sway-bar";
          position = "top";
          fonts = {
            names = [ "Iosevka" ];
            size = 12.0;
          };
        }];
        startup = [ 
          { command = "wpaperd"; }
          { command = "cliphist wipe"; }
        ];
        window = {
          border = 2;
          hideEdgeBorders = "smart";
          titlebar = false;
        };
        workspaceAutoBackAndForth = true;
        keybindings = {
          "${modifier}+Shift+q"   = ''exec echo -e "Lock\nShutdown\nReboot" | tofi | sh -c 'read action; case $action in "Lock") swaylock ;; "Shutdown") shutdown 0 ;; "Reboot") reboot ;; esac' '';
          "${modifier}+Return"    = "exec ${terminal}";
          "${modifier}+Semicolon" = "exec ${menu}";
          "${modifier}+Shift+x"   = "kill";
          "${modifier}+c"         = "exec cliphist list | tofi | cliphist decode | wl-copy";
          "${modifier}+h"         = "focus left";
          "${modifier}+j"         = "focus down";
          "${modifier}+k"         = "focus up";
          "${modifier}+l"         = "focus right";
          "${modifier}+Shift+h"   = "move left";
          "${modifier}+Shift+j"   = "move down";
          "${modifier}+Shift+k"   = "move up";
          "${modifier}+Shift+l"   = "move right";
          "${modifier}+a"         = "workspace number 1";
          "${modifier}+s"         = "workspace number 2";
          "${modifier}+d"         = "workspace number 3";
          "${modifier}+f"         = "workspace number 4";
          "${modifier}+g"         = "workspace number 5";
          "${modifier}+Shift+a"   = "move container to workspace number 1";
          "${modifier}+Shift+s"   = "move container to workspace number 2";
          "${modifier}+Shift+d"   = "move container to workspace number 3";
          "${modifier}+Shift+f"   = "move container to workspace number 4";
          "${modifier}+Shift+g"   = "move container to workspace number 5";
        };
      };
    };
  };

  systemd.user.startServices = "sd-switch"; # Nicely reload system units when changing configs

  home.stateVersion = "23.11"; # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
}
