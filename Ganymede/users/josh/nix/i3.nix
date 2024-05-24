{ pkgs ? <nixpkgs> {}, lib, config, ... }:
let
  cfg = config.windowManagers.i3;
in
{
  options.windowManagers.i3 = {
    enable = lib.mkEnableOption "i3 etc.";
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
    nixpkgs.overlays = [
     (import ./overlays/dmenu.nix)
    ];

    home.packages = with pkgs; [ 
      dmenu
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
        modifier = "Mod1";
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
          { command = "xautolock -time 10 -locker 'i3lock -c 000000'"; } # todo: work out why 'services.screen-locker' doesn't work
          { command = "i3-workspace-names-daemon"; }
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
}
