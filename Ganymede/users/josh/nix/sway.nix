{ pkgs ? <nixpkgs> {}, lib, config, ... }:
let
  cfg = config.windowManagers.sway;
in
{
  options.windowManagers.sway = {
    enable = lib.mkEnableOption "sway etc.";
    configOverride = lib.mkOption {
      type = lib.types.path;
      description = "Path to directory containing config files";
      default = ./. + "/../configs";
    };
    assetOverride = lib.mkOption {
      type = lib.types.path;
      description = "Path to directory containing asset files";
      default = ./. + "/../assets";
    };
  };
  
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      tofi
      wl-clipboard
    ];

    home.file.".config/tofi/config".source = "${cfg.configOverride}/tofi/tofi.conf"; # no home-manager options for tofi

    programs.imv.enable = true;

    programs.swaylock = {
      enable = true;
      settings.color = "000000";
    };

    programs.wpaperd = {
      enable = true;
      settings.default.path = "${cfg.assetOverride}/wallpaper.png";
    };

    services.cliphist = {
      enable = true;
      systemdTarget = "sway-session.target";
    };

    services.mako.enable = true;

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
          terminal = "kitty";
          menu = "tofi-run | xargs swaymsg exec"; # todo: improve this so that only actual (.desktop) programs are shown (like i3-dmenu-desktop)
          bars = [{ 
            statusCommand = "${pkgs.statusbar}/bin/statusbar";
            position = "top";
            fonts = {
              names = [ "Iosevka" ];
              size = 12.0;
            };
          }];
          startup = [ 
            { command = "wpaperd"; }
            { command = "cliphist wipe"; }
            { command = "i3-workspace-names-daemon"; }
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
  };
}
