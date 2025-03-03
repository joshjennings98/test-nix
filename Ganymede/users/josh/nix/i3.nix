{ pkgs ? <nixpkgs> {}, lib, config, ... }:
let
  cfg = config.windowManagers.i3;
in
{
  options.windowManagers.i3 = {
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

  config = {
    nixpkgs.overlays = [
     (import ./overlays/dmenu.nix)
    ];

    home.packages = with pkgs; [ 
      dmenu
      shellScripts.xauto_lock_screen
      xautolock # todo: work out why 'services.screen-locker' doesn't work
    ];
    
    home.pointerCursor.x11.enable = true;
  
    programs.feh.enable = true;

    # todo: work out why 'services.screen-locker' doesn't work
    # services.screen-locker = {
    #   enable = true;
    #   xautolock = {
    #     enable = true;
    #   };
    #   lockCmd = "${pkgs.i3lock}/bin/i3lock -c 000000";
    #   inactiveInterval = 1;
    # };

    xsession.windowManager.i3 = {
      enable = true;
      config = rec {
        modifier = "Mod4";
        terminal = "kitty";
        bars = [{ 
          statusCommand = "${pkgs.statusbar}/bin/statusbar";
          position = "top";
          fonts = {
            names = [ "Iosevka" ];
            size = 12.0;
          };
        }];
        startup = [ 
          { command = "feh --bg-scale ${cfg.assetOverride}/wallpaper.png"; }
          { command = "xautolock -time 10 -locker '${pkgs.shellScripts.xauto_lock_screen}/bin/xauto_lock_screen'"; } # todo: work out why 'services.screen-locker' doesn't work
          { command = "i3-workspace-names-daemon"; }
          { command = "xrandr --output DP-0 --mode 3440x1440 --rate 164.90"; } # todo: work out why this doesn't run
        ];
        window = {
          border = 2;
          hideEdgeBorders = "smart";
          titlebar = false;
        };
        workspaceAutoBackAndForth = true;
        keybindings = {
          "${modifier}+Shift+q"   = ''exec "i3-nagbar -t warning -m 'Do you want to reboot or shutdown?' -b 'shutdown' 'i3-msg exec shutdown 0' -b 'reboot' 'i3-msg exec reboot'"'';
          "${modifier}+q"         = ''exec i3lock -c 000000'';
          "${modifier}+Return"    = "exec ${terminal}";
          "${modifier}+semicolon" = "exec i3-dmenu-desktop --dmenu='dmenu -i -fn Iosevka-14 -nb #000000 -nf #ffffff'";
          "${modifier}+Shift+x"   = "kill";
          "${modifier}+h"         = "focus left";
          "${modifier}+j"         = "focus down";
          "${modifier}+k"         = "focus up";
          "${modifier}+l"         = "focus right";
          "${modifier}+Shift+h"   = "move left";
          "${modifier}+Shift+j"   = "move down";
          "${modifier}+Shift+k"   = "move up";
          "${modifier}+Shift+l"   = "move right";
          "${modifier}+1"         = "workspace number 1";
          "${modifier}+2"         = "workspace number 2";
          "${modifier}+3"         = "workspace number 3";
          "${modifier}+4"         = "workspace number 4";
          "${modifier}+5"         = "workspace number 5";
          "${modifier}+6"         = "workspace number 6";
          "${modifier}+7"         = "workspace number 7";
          "${modifier}+8"         = "workspace number 8";
          "${modifier}+9"         = "workspace number 9";
          "${modifier}+0"         = "workspace number 10";
          "${modifier}+Shift+1"   = "move container to workspace number 1";
          "${modifier}+Shift+2"   = "move container to workspace number 2";
          "${modifier}+Shift+3"   = "move container to workspace number 3";
          "${modifier}+Shift+4"   = "move container to workspace number 4";
          "${modifier}+Shift+5"   = "move container to workspace number 5";
          "${modifier}+Shift+6"   = "move container to workspace number 6";
          "${modifier}+Shift+7"   = "move container to workspace number 7";
          "${modifier}+Shift+8"   = "move container to workspace number 8";
          "${modifier}+Shift+9"   = "move container to workspace number 9";
          "${modifier}+Shift+0"   = "move container to workspace number 10";
        };
      };
    };
  };
}
