{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: 
let
    config = ./. + "/../config/";
in 
{
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence
  ];

  home.persistence."/persist/home/josh" = {
    directories = [
      "Downloads"
      "Music"
      "Pictures"
      "Documents"
      "Videos"
      "VirtualBox VMs"
      ".gnupg"
      ".ssh"
      ".local/share/keyrings"
      ".local/share/direnv"
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
    ];
    files = [
      ".screenrc"
    ];
    allowOther = true;
  };

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
      # Workaround for https://github.com/nix-community/home-manager/issues/2942
      allowUnfreePredicate = _: true;
    };
  };

  # TODO: Set your username
  home = {
    username = "josh";
    homeDirectory = "/home/josh";
  };

  home.packages = with pkgs; [
    foot
    tofi
  ];

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  # home.packages = with pkgs; [ steam ];

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  wayland = {
    windowManager.sway = {
        enable = true;
        systemd.enable = true;
        config = rec {
            modifier = "Mod1";
            terminal = "foot";
            # should I go back to the i3 style?
            menu = ''
                tofi-run \
                --width 100% \
                --height 100% \
                --fuzzy-match true \
                --font Iosevka \
                --font-size 14 \
                --padding-left 35% \
                --padding-top 30% \
                --border-width 0 \
                --outline-width 0 \
                --result-spacing 15 \
                --num-results 5 \
                --prompt-text 'run: ' \
                --background-color '#000000CC' \
                | xargs swaymsg exec
                '';
            bars = [{
            }];
            startup = [
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
                "${modifier}+c"         = "exec paste";
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

  programs = {
    fish = {
        enable = true;
        interactiveShellInit = builtins.readFile "${config}/config.fish";
    };
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.11";
}
