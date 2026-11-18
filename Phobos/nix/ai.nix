{ cfg, ...}: { config, pkgs, lib, ... }:
{
  programs.mcp = {
    enable = true;
    servers = {
      # modelsmcp = {
      #   url = "https://mcp.api.devplatform.arm.com/ai-portal";
      # };
    };
  };

  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    package = (pkgs.writeShellScriptBin "opencode" ''
      export OPENCODE_DISABLE_AUTOUPDATE=true
      export OPENCODE_DISABLE_DEFAULT_PLUGINS=true # stop blank screen on start (due to suspected lack of proxy setup for internal NPM)
      exec ${pkgs.opencode}/bin/opencode "$@"
    '');
    settings = {
      share = "disabled";
      theme = "gruvbox";
      disabled_providers = [
        "openai"
        "opencode"
        "zen"
      ];
      permission = {
        external_directory = {
          "~/Git/**"        = "allow";
          "~/References/**" = "allow";
          "~/go/pkg/mod/**" = "allow";
        };
        edit = {
          "~/Git/**"        = "deny";
          "~/References/**" = "deny";
        };
        bash = {
          "*"                  = "ask";
          "ls *"               = "allow";
          "jq *"               = "allow";
          "rg *"               = "allow";
          "wc *"               = "allow";
          "git diff *"         = "allow";
          "git status *"       = "allow";
          "git branch *"       = "allow";
          "git log *"          = "allow";
          "git remote *"       = "allow";
          "git ls-tree *"      = "allow";
          "git rev-parse *"    = "allow";
          "git show *"         = "allow";
          "gofmt *"            = "allow";
          "gofix *"            = "allow";
          "go test *"          = "allow";
          "go vet *"           = "allow";
          "go env *"           = "allow";
          "go tag *"           = "allow";
          "go list *"          = "allow";
          "golangci-lint *"    = "allow";
          "go mod tidy"        = "allow";
          "gh pr *"            = "allow";
          "gh api *comments *" = "allow";
          "gh api *pulls* *"   = "allow";
          "gh run view *"      = "allow";
          "gh stack *"         = "allow";
          "gh repo view *"     = "allow";
          "gh search code *"   = "allow";
        };
      };
      small_model = "arm-proxy-openai/gpt-5.6-luna"; # remember to update if deprecated
      provider = {
        arm-proxy-openai = {
          npm = "@ai-sdk/openai";
          name = "arm-proxy-openai";
          options = {
            baseURL = "placeholder";
            apiKey  = "{env:OPENAI_API_KEY}";
          };
          models = {
            "gpt-5.6-luna" = {
              id = "gpt-5.6-luna";
              options = {
                reasoningEffort = "none";
                textVerbosity = "low";
              };
              cost = {
                input = 0.2;
                output = 1.2;
                cache_read = 0.02;
                cache_write = 0.25;
              };
            };
            "gpt-5.6-terra" = {
              id = "gpt-5.6-terra";
              options = {
                reasoningEffort = "high";
                textVerbosity = "low";
                reasoningSummary = "auto";
              };
              cost = {
                input = 2.0;
                output = 12.0;
                cache_read = 0.20;
                cache_write = 2.5;
              };
            };
            "gpt-5.6-sol" = {
              id = "gpt-5.6-sol";
              options = {
                  reasoningEffort  = "medium";
                  reasoningSummary = "auto";
                  include = ["reasoning.encrypted_content"];
              };
              cost = {
                input = 4.0;
                output = 20.0;
                cache_read = 0.4;
                cache_write = 5.0;
              };
              variants = {
                "high" = {
                  reasoningEffort  = "high";
                  reasoningSummary = "auto";
                  include = ["reasoning.encrypted_content"];
                };
                "big brain mode" = {
                  reasoningEffort  = "xhigh";
                  reasoningSummary = "auto";
                  include = ["reasoning.encrypted_content"];
                };
              };
            };
            "gpt-6-astra" = {
              id = "gpt-6-astra";
              options = {
                  reasoningEffort  = "medium";
                  reasoningSummary = "auto";
                  include = ["reasoning.encrypted_content"];
              };
              cost = {
                input = 10.0;
                output = 50.0;
                cache_read = 1.0;
                cache_write = 12.5;
              };
              variants = {
                "high" = {
                  reasoningEffort  = "high";
                  reasoningSummary = "auto";
                  include = ["reasoning.encrypted_content"];
                };
                "big brain mode" = {
                  reasoningEffort  = "xhigh";
                  reasoningSummary = "auto";
                  include = ["reasoning.encrypted_content"];
                };
              };
            };
          };
        };
      };
      keybinds = {
        agent_cycle   = "shift+tab";
        variant_cycle = "tab";
        messages_page_up = "pageup,ctrl+u";
        messages_page_down = "ctrl+d";
      };
      agent = {
        code-reviewer = {
          description = "Reviews code for best practices and potential issues";
          mode = "subagent";
          model = "arm-proxy-openai/gpt-6-astra";
          prompt = builtins.readFile "${cfg}/ai/agent/code-reviewer.md";
          permission = {
            "edit" = "deny";
          };
        };
        architecture-planner = {
          description = "Decides on the best architecture to solve a problem";
          mode = "subagent";
          model = "arm-proxy-openai/gpt-6-astra";
          prompt = "You are an agent to help with deciding the architecture to solve a problem. Look at the files within `architecture-catalogue` and look at the current project and choose the the one that fits best";
          permission = {
            "edit" = "deny";
          };
        };
      };
      references = {
        architecture-catalogue = {
          # replace this with a git repo?
          path = "~/References/architecture-catalog/";
          description = "A catalog of architectural patterns in software engineering";
        };
      };
      formatter = {
        gofix = {
          command = [
            "golangci-lint" "run"
            "--max-same-issues" "0"
            "--max-issues-per-linter" "0"
            "--color" "never"
            "$FILE"
          ];
          extensions = [".go"];
        };
      };
    };
    skills = {
      plan-what             = "${cfg}/ai/skills/plan-what/";
      # prototype             = "${cfg}/ai/skills/prototype/";
    };
    context = builtins.readFile "${cfg}/ai/AGENTS.md";
  };

  home.file."References" = {
    source = "${cfg}/ai/references";
    recursive = true;
  };
}
