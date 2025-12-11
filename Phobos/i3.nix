{ config, pkgs, lib, ... }:
{
  nixpkgs = {
    overlays = [
      (final: pre: {
        dmenu = pre.dmenu.overrideAttrs (oldAttrs: { # https://news.ycombinator.com/item?id=30069486
          patches = [
            ./dmenu/fuzzymatch.diff
            ./dmenu/highlight.diff
          ];
          # as of 16/01/2025 the package needs the '-lm' flags set but hasn't done it upstream
          NIX_LDFLAGS = "${oldAttrs.NIX_LDFLAGS or ""} -lm";
        });
      })
      (final: pre: { pythonScripts = pre.callPackage (import ./scripts/python-scripts.nix) { inherit pkgs lib; }; })
    ];
    config.allowUnfree = true;
  };
  
  home.packages = with pkgs; [
    arandr
    blueman
    brightnessctl
    dmenu
    pamixer
    pythonScripts.workspaceNames
    srandrd
    xorg.xrandr
  ];

  programs.feh.enable = true;

  home.file."Pictures/Wallpapers/wallpaper.jpg".source = ./assets/wallpaper.jpg;

  home.file.".config/nix/nix.conf".text = "experimental-features = nix-command flakes";

  home.file."setup.sh" = {
    executable = true;
    text = (import ./setup.nix { pkgs = pkgs; });
  };

  systemd.user.services.nm-applet = {
    Unit = {
      Description = "Network Manager Applet (tray icon)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet";
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [
        "XDG_CURRENT_DESKTOP=i3"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  services.network-manager-applet = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.networkmanagerapplet;
  };

  programs.autorandr = {
    enable = false;
    profiles = {
      "work" = {
        fingerprint = {
          "eDP-1"    = "placeholder";
          "DP-2-2"   = "placeholder";
          "DP-2-1-8" = "placeholder";
        };
        config = {
          "DP-1"     = { enable = false; };
          "HDMI-1"   = { enable = false; };
          "DP-2"     = { enable = false; };
          "DP-3"     = { enable = false; };
          "DP-4"     = { enable = false; };
          "DP-5"     = { enable = false; };
          "DP-2-1"   = { enable = false; };
          "DP-2-1-1" = { enable = false; };
          "DP-2-3"   = { enable = false; };
          "DP-2-2"   = {
            enable   = true;
            crtc     = 2;
            primary  = false;
            position = "0x0";
            mode     = "2560x1440";
            rate     = "59.95";
            rotate   = "left";
          };
          "DP-2-1-8" = {
            enable   = true;
            crtc     = 1;
            primary  = false;
            position = "1440x566";
            mode     = "2560x1440";
            rate     = "59.95";
            rotate   = "normal";
          };
          "eDP-1"    = {
            enable   = true;
            crtc     = 0;
            primary  = true;
            position = "4000x806";
            mode     = "1920x1200";
            rate     = "60.00";
            rotate   = "normal";
          };
        };
      };
      "laptop" = {
        fingerprint = {
          "eDP-1"   = "placeholder";
        };
        config = {
          "eDP-1"    = {
            enable   = true;
            primary  = true;
            position = "0x0";
            mode     = "1920x1200";
            rate     = "60.00";
            rotate   = "normal";
          };
          "DP-1"     = { enable = false; };
          "HDMI-1"   = { enable = false; };
          "DP-2"     = { enable = false; };
          "DP-3"     = { enable = false; };
          "DP-4"     = { enable = false; };
          "DP-5"     = { enable = false; };
          "DP-2-1"   = { enable = false; };
          "DP-2-1-1" = { enable = false; };
          "DP-2-3"   = { enable = false; };
          "DP-2-2"   = { enable = false; };
          "DP-2-1-8" = { enable = false; };
        };
      };
    };
  };

  xsession.windowManager.i3 = {
    enable = true;
    config = rec {
      modifier = "Mod1";
      terminal = "kitty";
      bars = [{ 
        statusCommand = "i3status-rs config-default.toml";
        position = "top";
        fonts = {
          names = [ "Iosevka" ];
          size = 12.0;
        };
      }];
      startup = [ 
        { command = ''exec --no-startup-id "monitors --force"''; }
        { command = "exec --no-startup-id systemctl --user start nm-applet.service"; }
        { command = ''exec --no-startup-id "srandrd monitors --force''; }
        { command = "exec --no-startup-id i3-workspace-names-daemon"; }
        { command = ''exec --no-startup-id "xss-lock -- lock-script"''; }
        { command = "exec --no-startup-id blueman-applet"; }
        { command = "slack"; }
        { command = "firefox"; }
      ];
      assigns = {
        "number 2" = [{ class = "firefox"; }];
        "number 3" = [{ class = "^Slack$"; }];
      };
      workspaceOutputAssign = [
        {
          output = "eDP-1";
          workspace = "3";
        }
        {
          output = "DP-2-2";
          workspace = "2";
        }
        {
          output = "DP-2-1-8";
          workspace = "1";
        }
      ];
      window = {
        border = 2;
        hideEdgeBorders = "smart";
        titlebar = false;
      };
      workspaceAutoBackAndForth = true;
      keybindings = {
        "${modifier}+Shift+z"   = ''exec "i3-nagbar -t warning -m 'Do you want to reboot or shutdown?' -b 'shutdown' 'i3-msg exec shutdown 0' -b 'reboot' 'i3-msg exec reboot'"'';
        "${modifier}+z"         = "exec lock-script";
        "${modifier}+Return"    = "exec ${terminal}";
        "${modifier}+semicolon" = "exec i3-dmenu-desktop --dmenu='dmenu -i -fn Iosevka-14 -nb #000000 -nf #ffffff'";
        "${modifier}+Shift+x"   = "kill";
        "${modifier}+c"         = "exec monitors";
        "${modifier}+Shift+c"   = "exec monitors --force";
        "${modifier}+h"         = "focus left";
        "${modifier}+j"         = "focus down";
        "${modifier}+k"         = "focus up";
        "${modifier}+l"         = "focus right";
        "${modifier}+Shift+h"   = "move left";
        "${modifier}+Shift+j"   = "move down";
        "${modifier}+Shift+k"   = "move up";
        "${modifier}+Shift+l"   = "move right";
        "${modifier}+q"         = "workspace number 1";
        "${modifier}+w"         = "workspace number 2";
        "${modifier}+e"         = "workspace number 3";
        "${modifier}+r"         = "workspace number 4";
        "${modifier}+t"         = "workspace number 5";
        "${modifier}+y"         = "workspace number 6";
        "${modifier}+u"         = "workspace number 7";
        "${modifier}+i"         = "workspace number 8";
        "${modifier}+o"         = "workspace number 9";
        "${modifier}+p"         = "workspace number 10";
        "${modifier}+Shift+q"   = "move container to workspace number 1";
        "${modifier}+Shift+w"   = "move container to workspace number 2";
        "${modifier}+Shift+e"   = "move container to workspace number 3";
        "${modifier}+Shift+r"   = "move container to workspace number 4";
        "${modifier}+Shift+t"   = "move container to workspace number 5";
        "${modifier}+Shift+y"   = "move container to workspace number 6";
        "${modifier}+Shift+u"   = "move container to workspace number 7";
        "${modifier}+Shift+i"   = "move container to workspace number 8";
        "${modifier}+Shift+o"   = "move container to workspace number 9";
        "${modifier}+Shift+p"   = "move container to workspace number 10";
        "XF86AudioMicMute"      = "exec pamixer --default-source -t";
        "XF86AudioMute"         = "exec pamixer -t";
        "XF86AudioRaiseVolume"  = "exec pamixer -i 5";
        "XF86AudioLowerVolume"  = "exec pamixer -d 5";
        "XF86MonBrightnessUp"   = "exec brightnessctl set +10%";
        "XF86MonBrightnessDown" = "exec brightnessctl set 10%-";
      };
    };
  };

  programs.i3status-rust = {
    enable = true;
    bars = {
      default = {
        settings = {
          theme = {
            overrides = {
              good_fg = "#ffffff"; idle_fg = "#ffffff"; info_fg = "#ffffff";
              warning_fg = "#bbbbbb"; critical_fg = "#ff0000"; start_separator = "";    
            };
          };
        };
        blocks = [
          {
            block = "cpu";
            interval = 2;
            format = " CPU: $utilization.eng(w:2,pad_with:0) ";
            format_alt = " CPU: $barchart $frequency ";
            click = [
              { button = "left";  cmd = "kitty -e htop -s PERCENT_CPU"; }
              { button = "right"; action = "toggle_format"; }
            ];
          }
          {
            block = "memory";
            format = " Memory: $mem_used.eng(w:3,u:B,p:Mi) ($mem_total_used_percents.eng(w:2,pad_with:0)) ";
            format_alt = " Memory: used = $mem_used.eng(w:3,u:B,p:Mi) avail =$mem_avail.eng(w:3,u:B,p:Mi) total =$mem_total.eng(w:3,u:B,p:Mi) ";
            click = [
              { button = "left";  cmd = "kitty -e htop -s PERCENT_MEM"; }
              { button = "right"; action = "toggle_format"; }
            ];
          }
          {
            block = "net";
            format = " Network: $ip ";
            click = [ { button = "left"; cmd = "kitty -e nmtui"; } ];
          }
          {
            block = "battery";
            format = " Battery: $percentage {($time_remaining.dur(hms:true, min_unit:m))|} ";
            not_charging_format = " Battery: $percentage {($time_remaining.dur(hms:true, min_unit:m))|} ";
            charging_format = " Battery $percentage ⚡ ";
            full_format = " Battery: 100% ";
          }
          {
            block = "sound";
            format = " Volume: {$volume.eng(w:2)|Muted} ";
          }
          {
            block = "time";
            format = " $timestamp.datetime(f:'%a %d %h - %R') ";
            interval = 10;
            click = [
              { button = "left";  cmd = "lock-script"; }
              { button = "right"; cmd = "i3-nagbar -t warning -m 'Do you want to reboot or shutdown?' -b 'shutdown' 'i3-msg exec shutdown 0' -b 'reboot' 'i3-msg exec reboot'"; }
            ];
          }
        ];
      };
    };
  };

  home.file.".local/bin/monitors" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      if [ -n "$SRANDRD_OUTPUT" && -n "$SRANDRD_EVENT" ]; then
        echo "srandrd: $SRANDRD_OUTPUT $SRANDRD_EVENT"
      fi

      FORCE_FLAG=""
      for arg in "$@"; do
        case "$arg" in
          --force)
            FORCE_FLAG="--force"
            ;;
        esac
      done

      if [ -n "$FORCE_FLAG" ]; then
        ${pkgs.autorandr}/bin/autorandr --change laptop
      fi

      ${pkgs.autorandr}/bin/autorandr --change $FORCE_FLAG
      sleep 0.2
      ${pkgs.feh}/bin/feh --bg-fill ~/Pictures/Wallpapers/wallpaper.jpg
    '';
  };

  home.file.".local/bin/lock-script" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      i3lock -n -c 000000
      sleep 0.5
      monitors --force
    '';
  };
}

