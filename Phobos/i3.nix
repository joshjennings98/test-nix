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
    brightnessctl
    dmenu
    pamixer
    pythonScripts.workspaceNames
    xorg.xrandr
  ];

  programs.feh.enable = true;

  home.file."Pictures/Wallpapers/wallpaper.jpg".source = ./assets/wallpaper.jpg;

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
        statusCommand = "i3blocks";
        position = "top";
        fonts = {
          names = [ "Iosevka" ];
          size = 12.0;
        };
      }];
      startup = [ 
        { command = "monitors"; }
        { command = "slack"; }
        { command = "exec --no-startup-id systemctl --user start nm-applet.service"; }
        { command = "monitor-watcher"; }
        { command = "i3-workspace-names-daemon"; }
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
        "${modifier}+z"         = "exec i3lock -c 000000";
        "${modifier}+Return"    = "exec ${terminal}";
        "${modifier}+semicolon" = "exec i3-dmenu-desktop --dmenu='dmenu -i -fn Iosevka-14 -nb #000000 -nf #ffffff'";
        "${modifier}+Shift+x"   = "kill";
        "${modifier}+Shift+c"   = "exec monitors";
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
      };
    };
  };

  programs.i3blocks = {
    enable = true;
    bars.config = {
      volume = {
        command = "i3blocks-volume";
        interval = 1;
      };

      battery = lib.hm.dag.entryAfter [ "volume" ] {
        command = "i3blocks-battery";
        interval = 60;
      };

      network = lib.hm.dag.entryAfter [ "battery" ] {
        command = "i3blocks-net";
        interval = 5;
      };
      

      cpu = lib.hm.dag.entryAfter [ "network" ] {
        command = "i3blocks-cpu";
        interval = 2;
      };

      memory = lib.hm.dag.entryAfter [ "cpu" ] {
        command = "i3blocks-mem";
        interval = 10;
      };

      date = lib.hm.dag.entryAfter [ "memory" ] {
        command = "date +' Date: %Y-%m-%d '";
        interval = 10;
      };

      time = lib.hm.dag.entryAfter [ "date" ] {
        command = "date +' Time: %H:%M '";
        interval = 10;
      };
    };
  };

  home.file.".local/bin/i3blocks-volume" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      STEP=5

      case "$BLOCK_BUTTON" in
        1) pamixer -t ;;          # left click: mute/unmute
        4) pamixer -i "$STEP" ;;  # scroll up: volume up
        5) pamixer -d "$STEP" ;;  # scroll down: volume down
      esac

      vol=$(pamixer --get-volume 2>/dev/null || echo 0)
      muted=$(pamixer --get-mute 2>/dev/null || echo false)

      if [ "$muted" = "true" ]; then
        echo "Volume: muted "
        echo "muted"
        echo "#888888"
      else
        echo "Volume: $vol% "
        echo "$vol%"
        echo "#ffffff"
      fi
    '';
  };

  home.file.".local/bin/i3blocks-net" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      if [ "$BLOCK_BUTTON" = "1" ]; then
        exec kitty -e nmtui
      fi

      if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        echo " Network: Up "
        echo "UP"
        echo "#ffffff"
      else
        echo " Network: Down "
        echo "DOWN"
        echo "#ff0000"
      fi
    '';
  };

  home.file.".local/bin/i3blocks-cpu" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      if [ "$BLOCK_BUTTON" = "1" ]; then
        exec kitty -e htop -s PERCENT_CPU
      fi

      PREV=/tmp/.i3blocks_cpu_prev

      read _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
      total=$((user + nice + system + idle + iowait + irq + softirq + steal))

      if [ -f "$PREV" ]; then
        read p_total p_idle < "$PREV"
        diff_total=$((total - p_total))
        diff_idle=$((idle - p_idle))
        if [ "$diff_total" -gt 0 ]; then
          usage=$(( (100 * (diff_total - diff_idle)) / diff_total ))
        else
          usage=0
        fi
      else
        usage=0
      fi

      echo " CPU: $usage% "
      echo "$usage%"
      echo "#ffffff"

      echo "$total $idle" > "$PREV"
    '';
  };

  home.file.".local/bin/i3blocks-mem" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      if [ "$BLOCK_BUTTON" = "1" ]; then
        exec kitty -e htop -s PERCENT_MEM
      fi

      meminfo=$(grep -E "Mem(Total|Available):" /proc/meminfo)
      total=$(echo "$meminfo" | awk "/MemTotal/ {print \$2}")
      avail=$(echo "$meminfo" | awk "/MemAvailable/ {print \$2}")
      used=$((total - avail))
      percent=$((100 * used / total))

      echo " Memory: $percent% "
      echo "$percent%"
      echo "#ffffff"
    '';
  };

  home.file.".local/bin/i3blocks-battery" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      bat=$(ls /sys/class/power_supply | grep -i BAT | head -n 1)
      pct=$(cat /sys/class/power_supply/$bat/capacity)
      stat=$(cat /sys/class/power_supply/$bat/status)

      echo " Battery: $pct% "
      echo "$pct%"

      if (( pct < 20 )); then
        echo "#ff000"
        exit 0
      fi

      if [[ "$stat" == "Discharging" ]]; then      
        echo "#ffff00"
      else
        echo "#ffffff"
      fi
    '';
  };

  home.file.".local/bin/monitors" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      ${pkgs.autorandr}/bin/autorandr --change
      sleep 0.2
      ${pkgs.feh}/bin/feh --bg-fill ~/Pictures/Wallpapers/wallpaper.jpg
    '';
  };

  home.file.".local/bin/monitor-watcher" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      prev=""
      while true; do
        current="$(${pkgs.xorg.xrandr}/bin/xrandr --query 2>/dev/null)"
        if [ -n "$prev" ] && [ "$current" != "$prev" ]; then
          monitors
        fi
        prev="$current"
        sleep 2
      done
    '';
  };
}
