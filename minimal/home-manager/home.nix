{ inputs, lib, config, pkgs, ... }: 
let
    config = ./. + "/../config/";
in 
{
  # Import other home-manager modules here (either via flakes like inputs.xxx.yyy or directly like ./zzz.nix)
  imports = with inputs; [
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

  home.packages = with pkgs; [
    tofi
    iosevka
    wl-clipboard
  ];

  home.file.".config/tofi/config".source = "${config}/config.tofi";

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "Josh";
    userEmail = "josh@joshj.dev";
    extraConfig = {
      push = {
        autoSetupRemote = true; 
      };
    };
  };

  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    theme = "Gruvbox Dark";
  };

  programs.fzf = {
    enable = true;
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile "${config}/config.fish";
  };

  programs.wpaperd = {
    enable = true;
    settings.default.path = "${assets}/wallpaper.jpg"
  }

  services.cliphist = {
    enable = true;
    systemdTarget = "sway-session.target";
  }

  wayland = {
    windowManager.sway = {
      enable = true;
      systemd.enable = true;
      config = rec {
        modifier = "Mod1";
        terminal = "LIBGL_ALWAYS_SOFTWARE=true GALLIUM_DRIVER=llvmpipe kitty"; # so kitty works in virtualbox
        menu = "tofi-run | xargs swaymsg exec";
        bars = [{ }];
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
          "${modifier}+Shift+q"   = "exec power";
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

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.11";
}
