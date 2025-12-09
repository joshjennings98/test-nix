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
    ];
    config.allowUnfree = true;
  };
  
  home.packages = with pkgs; [
    i3blocks
    pamixer
  ];

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

  xsession.windowManager.i3 = {
    enable = true;
    config = rec {
      modifier = "Mod4";
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
        { command = "autorandr -c"; }
        { command = "feh --bg-fill ~/Pictures/Wallpaper/wallpaper.jpg"; }
        { command = "exec --no-startup-id systemctl --user start nm-applet.service"; }
        { command = "i3-workspace-names-daemon"; } # TODO: make part of a service
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
        command = ''
          #!/usr/bin/env sh
          STEP=5

          case "$BLOCK_BUTTON" in
            1) pamixer -t ;;          # left click: mute/unmute
            4) pamixer -i "$STEP" ;;  # scroll up: volume up
            5) pamixer -d "$STEP" ;;  # scroll down: volume down
          esac

          vol=$(pamixer --get-volume 2>/dev/null || echo 0)
          muted=$(pamixer --get-mute 2>/dev/null || echo false)

          if [ "$muted" = "true" ]; then
            text="Mute"
            color="#ff5555"
          else
            text="$vol%"
            color=""
          fi
          
          echo "$text"
          echo "$color"
        '';
        interval = 1;
      };

      network = lib.hm.dag.entryAfter [ "volume" ] {
        command = ''
          #!/usr/bin/env sh
          if [ "$BLOCK_BUTTON" = "1" ]; then # left click opens nmtui in a terminal
            for term in alacritty kitty gnome-terminal xterm; do
              if command -v "$term" >/dev/null 2>&1; then
                "$term" -e nmtui &
                exit 0
              fi
            done
          fi

          if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
            echo "UP"
            echo "UP"
            echo "#a3be8c"  # green
          else
            echo "DOWN"
            echo "DOWN"
            echo "#bf616a"  # red
          fi
        '';
        interval = 5;
      };

      cpu = lib.hm.dag.entryAfter [ "network" ] {
        command = ''
          #!/usr/bin/env sh
          PREV="/tmp/.i3blocks_cpu_prev"

          set -- $(grep '^cpu ' /proc/stat)

          user=$2 nice=$3 system=$4 idle=$5 iowait=$6 irq=$7 softirq=$8 steal=$9
          total=$((user + nice + system + idle + iowait + irq + softirq + steal))

          if [ -f "$PREV" ]; then
            set -- $(cat "$PREV")
            p_total=$1
            p_idle=$2

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

          echo "CPU $usage%"
          echo "$usage%"
          echo ""

          echo "$total $idle" > "$PREV"
        '';
        interval = 2;
      };

      memory = lib.hm.dag.entryAfter [ "cpu" ] {
        command = ''
          #!/usr/bin/env sh
          meminfo=$(grep -E "Mem(Total|Available):" /proc/meminfo)
          total=$(echo "$meminfo" | awk '/MemTotal/ {print $2}')
          avail=$(echo "$meminfo" | awk '/MemAvailable/ {print $2}')
          used=$((total - avail))
          percent=$((100 * used / total))

          echo "Mem $percent%"
          echo "$percent%"
          echo ""
        '';
        interval = 5;
      };

      time = lib.hm.dag.entryAfter [ "memory" ] {
        command = "date '+%Y-%m-%d %H:%M'";
        interval = 60;
      };
    };
  };
}
