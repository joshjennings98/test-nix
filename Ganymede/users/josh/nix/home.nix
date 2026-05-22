{ inputs, lib, pkgs, ... }: 
let
  config = ./. + "/../configs";
in
{
  nixpkgs = {
    overlays = [
      (final: pre: { pythonScripts = pre.callPackage (import ./python-scripts.nix) { inherit pkgs lib; }; })
      (final: pre: { shellScripts = pre.callPackage (import ./shell-scripts.nix) { inherit pkgs lib; }; })
    ]; 
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true; # nix-community/home-manager/issues/2942
    };
  };

  imports = [
    inputs.impermanence.nixosModules.impermanence

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

  home.persistence."/persist" = {
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
      ".mozilla/firefox" # todo: make this more granular so it just saves enabled extensions, layout, dismissed messages, sessions, etc. instead of everything
      ".local/share/Steam"
      ".local/share/mpd"
      ".config/helix/runtime/grammars"
      ".local/share/vulkan"
      ".cache/mesa_shader_cache"
      ".config/spotify"
      ".config/gh"
    ];
    files = [
      ".screenrc"
      ".local/share/fish/fish_history" # persist fish history
    ];
  };

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    anki-bin
    bat
    bash-language-server
    black
    cargo
    cookiecutter
    delve
    discord
    dockerfile-language-server
    fd
    ffmpeg
    gcc
    go
    gopls
    golangci-lint
    golangci-lint-langserver
    go-tools
    graphviz
    gruvbox-dark-gtk
    htop
    #inputs.nix-gaming.packages.${pkgs.system}.star-citizen # pkgs.system has problem with its existence when doing nixos-install
    iosevka
    jq
    kak-tree-sitter
    keepassxc
    lxappearance-gtk2
    nil
    obsidian
    pagefind # TODO: move to dev flake in website
    pyright
    pythonScripts.workspaceNames
    ripgrep
    rustc
    rustlings
    spotify
    shellScripts.switch-open-project
    shellScripts.switch-project
    shellScripts.tmux-popup
    tree
    typst
    unzip
    warpd
    vis
    xclip
    thunar
    yaml-language-server
    yt-dlp
    yq
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

  programs.difftastic = {
    enable = true;
    git.enable = true;
  };

  programs.git = {
    enable = true;
    settings = {
      push.autoSetupRemote = true;
      user = {
        name = "joshjennings98";
        email = "josh@joshj.dev";
      };
    };
  };

  programs.lazygit = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      git.pagers = [
        { useExternalDiffGitConfig = true; }
      ];
    };
  };

  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings = lib.importTOML "${config}/helix/config.toml";    
    languages = lib.importTOML "${config}/helix/languages.toml";    
  };

  programs.kitty = {
    enable = false;
    shellIntegration.enableFishIntegration = false;
    settings = {
      shell = "${pkgs.fish}/bin/fish";
    };
    extraConfig = builtins.readFile "${config}/kitty/kitty.conf";
  };

  programs.mcp = {
    enable = true;
    servers = {
      # nudge = {
      #   command = "/home/josh/Documents/planner/test4/nudge";
      #   args = [
      #     "mcp"
      #   ];
      # };
    };
  };

  programs.claude-code = {
    enable = true;
    enableMcpIntegration = true;
    skills = {
      brainstorming = "${config}/ai/skills/brainstorming";
    };
  };

  programs.codex = {
    enable = true;
    enableMcpIntegration = true;
    context = builtins.readFile "${config}/ai/AGENTS.md";
  };

  programs.mpv.enable = true;

  programs.ncmpcpp.enable = true;

  programs.obsidian.enable = true;

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

  programs.tmux = {
    enable = true;
    mouse  = true;
    shell  = "${pkgs.fish}/bin/fish";
    extraConfig = ''
      # Misc stuff
      set -g default-terminal "tmux-256color"
      set -g status off
      setw -g mouse on
      set -g set-titles on
      set -g set-titles-string 'tmux #S'
      # Exit highlight when mouse lifted but don't go to the bottom
      # Note: this will only work for X11 (use wl-copy or something for wayland)
      bind-key -T copy-mode MouseDragEnd1Pane \
        send-keys -X copy-pipe-no-clear '${pkgs.xclip}/bin/xclip -selection clipboard -in' \; \
        send-keys -X clear-selection
      unbind C-b
      # Change prefix to C-a
      set-option -g prefix C-a
      bind-key C-a send-prefix
      # Keybinds etc.
      bind -n WheelUpPane if -F '#{mouse_any_flag}' 'send-keys -M' 'copy-mode -e; send-keys -X scroll-up'           
      bind -n WheelDownPane if -F '#{mouse_any_flag}' 'send-keys -M' 'copy-mode -e; send-keys -X scroll-down'
      bind-key - split-window -v
      bind-key | split-window -h
      # Make sure escape key handled straight away
      set -sg escape-time 0
      # Ensure undercurl works in tmux+st etc.
      set -as terminal-features ',*:usstyle'
      set -as terminal-features ',*:RGB'
      # Make sure that shift+enter can return actual shift+enter not just enter
      set -s extended-keys on
      set -as terminal-features ',xterm-kitty:extkeys,tmux-256color:extkeys,st-256color:extkeys'
      set -s extended-keys-format csi-u
    '';
  };

  programs.zed-editor = {
    enable = true;
    extensions = [ "golangci-lint" ];
    extraPackages = [ pkgs.delve pkgs.bat pkgs.ripgrep ];
    userKeymaps = [
      {
        context = "vim_mode == helix_normal";
        bindings = {
          "g O" = "pane::GoForward";
          "g o" = "pane::GoBack";
          "G" = "vim::HelixJumpToWord";
          ";" = "vim::RepeatFind";
          "," = "vim::RepeatFindReversed";
          "w" = "editor::SelectLargerSyntaxNode";
          "W" = "editor::SelectSmallerSyntaxNode";
          "s n" = "editor::SelectNext";
          "s p" = "editor::UndoSelection";
          "s s" = "editor::SelectAllMatches";
          # "space /" = "workspace::NewSearch";
          "space /" = [ "task::Spawn" { task_name = "Text Search"; reveal_target = "center"; } ];
          "space b" = "tab_switcher::Toggle";
          "space g" = "git_panel::ToggleFocus";
          "space s" = "outline::Toggle";
          "space S" = "outline_panel::ToggleFocus";
          "space d" = "diagnostics::Deploy";
          "space e" = "project_panel::ToggleFocus";
          "space q" = "pane::CloseActiveItem";
          "space p" = "pane::ActivatePreviousItem";
          "space n" = "pane::ActivateNextItem";
          "space l" = "lsp_tool::ToggleMenu";
          "space t" = "terminal_panel::ToggleFocus";
          "space G" = "debug_panel::ToggleFocus";
          "space A" = "agent::ToggleFocus";
          "space f" = [ "task::Spawn" { task_name = "File Finder"; reveal_target = "center"; } ];
          "] d" = "editor::GoToDiagnostic";
          "[ d" = "editor::GoToPreviousDiagnostic";
          "b c" = "pane::CloseActiveItem";
          "g t" = "editor::ToggleFold";
        };
      }
      {
        context = "ProjectSearchBar";
        bindings = {
          "escape escape" = "pane::CloseActiveItem";
        };
      }
      {
        context = "Editor && !multibuffer";
        bindings = {
          "n" = "search::SelectNextMatch";
          "N" = "search::SelectPreviousMatch";
        };
      }
      {
        context = "Editor && multibuffer";
        bindings = {
          "space q" = "pane::CloseActiveItem";
          "n" = "editor::MoveToStartOfNextExcerpt";
          "N" = "editor::MoveToEndOfPreviousExcerpt";
        };
      }
      {
        context = "Diagnostics";
        bindings = {
          "space q" = "pane::CloseActiveItem";
        };
      }
      {
        context = "OutlinePanel";
        bindings = {
          "space S" = "outline_panel::ToggleFocus";
          "escape" = "workspace::ToggleLeftDock";
        };
      }
      {
        context = "ProjectPanel";
        bindings = {
          "space e" = "project_panel::ToggleFocus";
          "escape" = "workspace::ToggleLeftDock";
        };
      }
      {
        context = "GitPanel";
        bindings = {
          "space g" = "git_panel::ToggleFocus";
          "escape" = "workspace::ToggleLeftDock";
        };
      }
      {
        context = "(CommitEditor > Editor) && vim_mode == helix_normal";
        bindings = {
          "escape" = "git_panel::FocusChanges";
        };
      }
      {
        context = "DebugPanel";
        bindings = {
          # need to work out the editor stuff and come up with good keybindings
          "escape" = "workspace::ToggleBottomDock";
        };
      }
      {
        context = "AgentPanel";
        bindings = {
          "space A" = "editor::ToggleFocus";
          "escape" = "workspace::ToggleRightDock";
        };
      }
      {
        context = "(MessageEditor > Editor) && vim_mode == helix_normal";
        bindings = {
          "escape" = "workspace::ToggleRightDock";
        };
      }
    ];
    userTasks = [
      {
        label = "File Finder";
        command = ''
          fzf --ansi \
          --layout=reverse \
          --border \
          --preview 'bat --style=numbers --color=always --theme=gruvbox-dark --paging=never {}' \
          --preview-window 'right:70%:wrap' \
          --multi \
          --scrollbar ' ' \
      | xargs -r -I{} zeditor "./{}"
        '';
        hide = "always";
        allow_concurrent_runs = true;
        use_new_terminal = true;
      }
      {
        label = "Text Search";
        command = ''
          printf "" | fzf \
            --layout=reverse \
            --border \
            --disabled \
            --query "" \
            --bind "start:reload:rg --column --line-number --no-heading --color=never --smart-case {q} . || true" \
            --bind "change:reload:rg --column --line-number --no-heading --color=never --smart-case {q} . || true" \
            --delimiter : \
            --preview 'set -l line {2}; set -l start (math "max(1, $line - 20)"); set -l end (math "$line + 100"); bat --style=numbers,plain --color=always --theme=gruvbox-dark --paging=never --highlight-line "$line" --line-range "$start:$end" {1}' \
            --preview-window 'right:50%:wrap' \
            --scrollbar ' ' \
          | read -l selected

          if test -n "$selected"
            set -l parts (string split -m 3 ":" -- $selected)
            set -l file $parts[1]
            set -l line $parts[2]
            set -l col $parts[3]

            zeditor "$file:$line:$col"
          end
        '';
        hide = "always";
        allow_concurrent_runs = true;
        use_new_terminal = true;
      }
    ];
    userSettings = {
      ui_font_size = 14;
      buffer_font_size = 14;
      ui_font_family = "Iosevka";
      theme = {
        mode = "dark";
        light = "Gruvbox Light";
        dark = "Gruvbox Dark";
      };
      helix_mode = true;
      title_bar = {
        show_sign_in = false;
        show_onboarding_banner = false;
        show_user_picture = false;
      };
      tab_bar = {
        show = true;
        show_nav_history_buttons = false;
        show_tab_bar_buttons = true;
      };
      tabs = {
        file_icons = true;
        show_diagnostics = "all";
        git_status = true;
      };
      collaboration_panel = {
        button = false;
      };
      buffer_font_features = {
        calt = false; # Disable ligatures
      };
      soft_wrap = "editor_width";
      wrap_guides = [80 120];
      diagnostics = {
        include_warnings = true;
        inline = {
          enabled = true;
        };
      };
      inlay_hints = {
        enabled = true;
        show_type_hints = true;
        show_parameter_hints = true;
        show_other_hints = true;
        show_background = false;
      };
      restore_on_startup = "none";
      search = {
        regex = true;
      };
      telemetry = {
        diagnostics = false;
        metrics = false;
      };
      project_panel = {
        starts_open = false;
      };
      terminal = {
        cursor_shape = "bar";
      };
      features = {
        edit_prediction_provider = "none";
      };
      notification_panel = {
        button = false;
      };
      # run with steam-run until this works
      # dap = {
      #   Delve = {
      #     binary = "${pkgs.delve}/bin/dlv-dap";
      #   };
      # };
    };
    # package = pkgs.writeShellScriptBin "zeditor" ''
    #   # use steam-run to sort out the paths until the debugger adapter thingy works for go, see zed/issues/36045
    #   # set TMPDIR to the same location so that the unix sockets will match during IPC (steam-run seems to create different tmp sandboxes)
    #   TMPDIR="$HOME/.cache/zed" /run/current-system/sw/bin/steam-run ${pkgs.zed-editor}/bin/zeditor "$@"
    # '';
  };

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

  home.stateVersion = "26.05"; # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
}
