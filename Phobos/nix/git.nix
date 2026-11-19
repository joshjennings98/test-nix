{ pkgs, ... }:
let
  overlays = ./overlays;
in
{
  nixpkgs = {
    overlays = [
      (import "${overlays}/brrrr.nix")
    ];
  };
    
  home.file."Git/.keep".text = "ensure ~/Git directory exists";

  home.packages = with pkgs; [
    brrrr
  ];
  
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
        email = "josh.jennings@arm.com";
      };
    };
    ignores = [
      ".nudge"
      "plan.feature.md"
    ];
  };

  programs.gh-dash = {
    enable = true;
    settings = {
      defaults = {
        preview = {
          open = false;
        };
      };
      keybindings = {
        universal = [
          {
            key = "g";
            name = "lazygit";
            command = "lazygit";
          }
        ];
        prs = [
          {
            key = "R";
            name = "code review";
            command = "brrrr --repo {{.RepoName}} --pr {{.PrNumber}}";
          }
          {
            key = "C";
            name = "ai code review";
            command = ''
              repo="{{.RepoPath}}"
              pr="{{.PrNumber}}"
              branch="pr-$pr"

              git -C "$repo" fetch origin "pull/$pr/head" || exit 1

              gitdir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)" || exit 1
              root="$(dirname "$gitdir")"
              worktree="$root/$branch"

              if [ ! -d "$worktree" ]; then
                if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
                  git -C "$repo" branch -f "$branch" FETCH_HEAD || exit 1
                  git -C "$repo" worktree add "$worktree" "$branch" || exit 1
                else
                  git -C "$repo" worktree add -b "$branch" "$worktree" FETCH_HEAD || exit 1
                fi
              fi

              cd "$worktree" || exit 1
              exec opencode --prompt '@code-reviewer: review-pr-for-this-branch'
            '';
          }
        ];
      };
      theme = {
        colors = { # gruvbox-dark theme
          text = {
            primary = "#ebdbb2";
            secondary = "#d5c4a1";
            inverted = "#282828";
            faint = "#928374";
            warning = "#fb4934";
            success = "#b8bb26";
          };
          background = {
            selected = "#3c3836";
          };
          border = {
            primary = "#504945";
            secondary = "#689d6a";
            faint = "#3c3836";
          };
        };
        ui = {
          sectionsShowCount = true;
          table = {
            showSeparator = true;
            compact = true;
          };
        };
      };
      pager = {
        confirmQuit = false;
        showAuthorIcons = true;
        smartFilteringAtLaunch = true;
      };
    };
  };

  programs.lazygit = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      git.diffRenderers = [
        { type = "extDiff"; }
      ];
    };
  };

  # NOTE: See this issue is still happening nix-community/home-manager/issues/1654
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true; # should work for private go modules tool
  };
}

