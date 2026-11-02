{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.emacs-broker;
  state = "/var/lib/emacs-broker";
  package = pkgs.callPackage ../configs/doom/broker { };
  policy = pkgs.writeText "emacs-broker-policy.json" (
    builtins.toJSON {
      inherit state;
      socket = "/run/emacs-broker/client.sock";
      inherit (cfg) pageHosts;
      modelEndpoint = if cfg.model.endpoint == null then "" else cfg.model.endpoint;
    }
  );
  login = pkgs.writeShellApplication {
    name = "emacs-broker-login";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      environment=${pkgs.coreutils}/bin/env
      broker=${package}/bin/emacs-broker
      policy=${policy}
      github_cli=${pkgs.gh}/bin/gh
      credential_directory=${state}
      login_path=${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.git
        ]
      }
      certificates=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    ''
    + builtins.readFile ../configs/doom/scripts/login.sh;
  };

  # Home Manager owns the editor; NixOS owns the separate credential user.
  editor = (
    {
      config,
      inputs,
      lib,
      pkgs,
      osConfig,
      ...
    }:
    let
      emacsPackage = pkgs.emacs-unstable;
      emacsPackages = pkgs.emacsPackagesFor emacsPackage;
      treeSitterGrammars = emacsPackages.treesit-grammars.with-grammars (
        grammars: with grammars; [
          tree-sitter-bash
          tree-sitter-css
          tree-sitter-go
          tree-sitter-gomod
          tree-sitter-javascript
          tree-sitter-json
          tree-sitter-nix
          tree-sitter-python
          tree-sitter-typescript
          tree-sitter-yaml
        ]
      );
      cfg = config.programs.emacs-sandbox;
      home = config.home.homeDirectory;
      state = "${home}/.local/share/emacs-sandbox";
      tools = pkgs.buildEnv {
        name = "emacs-sandbox-tools";
        paths = with pkgs; [
          bash
          coreutils
          findutils
          gnugrep
          gnused
          gawk
          diffutils
          git
          go
          gopls
          ripgrep
          fd
          curl
          gcc
          gnumake
        ];
        pathsToLink = [ "/bin" ];
      };
      gitConfig = pkgs.writeText "emacs-sandbox-gitconfig" ''
        [user]
          name = ${config.programs.git.settings.user.name}
          email = ${config.programs.git.settings.user.email}
        [push]
          autoSetupRemote = true
        [credential]
          helper =
        [url "http://127.0.0.1:8123/github/"]
          insteadOf = https://github.com/
          insteadOf = git@github.com:
          insteadOf = ssh://git@github.com/
      '';
      inside = pkgs.writeShellApplication {
        name = "emacs-sandbox-inside";
        runtimeInputs = [
          pkgs.socat
          pkgs.curl
          pkgs.coreutils
        ];
        text = builtins.readFile ../configs/doom/scripts/bridge.sh;
      };

      sandboxEnvironment = {
        HOME = home;
        USER = config.home.username;
        PATH = "${tools}/bin";
        SHELL = "${pkgs.bash}/bin/bash";
        LANG = "en_GB.UTF-8";
        LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
        XDG_CONFIG_HOME = "${state}/config";
        XDG_CACHE_HOME = "${state}/cache";
        XDG_DATA_HOME = "${state}/data";
        XDG_STATE_HOME = "${state}/state";
        XDG_RUNTIME_DIR = "/run/emacs";
        DOOMLOCALDIR = "${state}/doom-local";
        EMACS_BROKER_URL = "http://127.0.0.1:8123";
        EMACS_BROKER_MODEL = osConfig.services.emacs-broker.model.name;
        GOPATH = "${home}/go";
        GOCACHE = "${home}/.cache/go-build";
        GOPROXY = "http://127.0.0.1:8123/gomod";
        GOSUMDB = "sum.golang.org http://127.0.0.1:8123/gosum";
        GIT_CONFIG_GLOBAL = "/etc/emacs-gitconfig";
        GIT_CONFIG_NOSYSTEM = "1";
        GIT_TERMINAL_PROMPT = "0";
        LIBGL_ALWAYS_SOFTWARE = "1";
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };

      readOnlyPaths = [
        "/nix/store"
        "/etc/passwd"
        "/etc/group"
        "/etc/fonts"
        "/run/emacs-broker"
      ];
      environmentArgs = lib.concatLists (
        lib.mapAttrsToList (name: value: [
          "--setenv"
          name
          value
        ]) sandboxEnvironment
      );

      stateDirectories = [
        state
        "${home}/go"
        "${home}/.cache/go-build"
      ]
      ++ map (name: "${state}/${name}") [
        "config"
        "cache"
        "data"
        "state"
        "doom-local"
      ];

      launcher = pkgs.writeShellApplication {
        name = "emacs";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          editor_home=${lib.escapeShellArg home}
          bubblewrap=${pkgs.bubblewrap}/bin/bwrap
          bridge_script=${inside}/bin/emacs-sandbox-inside
          emacs=${config.programs.doom-emacs.finalEmacsPackage}/bin/emacs
          state_directories=( ${lib.escapeShellArgs stateDirectories} )
          writable_directories=( ${lib.escapeShellArgs cfg.writableDirectories} )
          editor_state=${lib.escapeShellArg state}
          agent_skills=${../ai/skills}
          git_config=${gitConfig}
          word_list=${pkgs.scowl}/share/dict/wbritish.txt
          read_only_paths=( ${lib.escapeShellArgs readOnlyPaths} )
          environment_args=( ${lib.escapeShellArgs environmentArgs} )
        ''
        + builtins.readFile ../configs/doom/scripts/launch.sh;
      };
    in
    {
      imports = [ inputs.nix-doom-emacs-unstraightened.homeModule ];
      options.programs.emacs-sandbox = {
        enable = lib.mkEnableOption "the main Emacs filesystem and network sandbox";
        writableDirectories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "${home}/Documents"
            "${home}/go"
            "${home}/.cache/go-build"
            "${home}/nix-config"
          ];
          description = "Exact writable roots exposed to Emacs and all its tools. Downloads is intentionally absent.";
        };
        package = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          default = launcher;
        };
      };
      config = lib.mkMerge [
        {
          programs.emacs-sandbox.enable = true;

          home.packages = [
            pkgs.gopls
          ];

          home.file.".agents/skills".source = ../ai/skills;

          home.persistence."/persist".directories = [
            ".cache/doom"
            ".local/share/doom"
            ".local/share/nix-doom"
            ".local/state/doom"
          ];

          home.activation.createDoomOrgDirectory =
            inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ]
              ''
                $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Documents/org"
              '';

          programs.doom-emacs = {
            enable = true;
            doomDir = ../configs/doom;
            doomLocalDir = "${config.xdg.dataHome}/nix-doom";
            emacs = emacsPackage;
            provideEmacs = true;

            emacsPackageOverrides = _self: super: {
              gptel = super.gptel.overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [ ../patches/gptel-oauth.patch ];
                # i3 owns Alt+Return. Change gptel's local minibuffer/menu keys
                # and their displayed hints together, without a global translation.
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace gptel-transient.el gptel-rewrite.el \
                    --replace-fail '"M-RET"' '"C-c RET"'
                '';
              });
              gptel-inline = super.gptel-inline.overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [ ../configs/doom/patches/gptel-inline-header.patch ];
                # The upstream repeat-SPC map consumes Doom's next leader key.
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace gptel-inline.el \
                    --replace-fail "\"SPC\" #'gptel-inline-cycle-reference" "\".\" #'gptel-inline-cycle-reference" \
                    --replace-fail '(propertize "SPC"' '(propertize "."'
                '';
              });
            };

            extraPackages = _epkgs: [
              treeSitterGrammars
            ];

            extraBinPackages = [
              pkgs.fd
              pkgs.git
              pkgs.go
              pkgs.gopls
              pkgs.ripgrep
            ];
          };
        }
        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = osConfig.services.emacs-broker.enable;
              message = "The Emacs sandbox requires the NixOS emacs-broker service.";
            }
          ];
          home.packages = [ (lib.hiPrio launcher) ];
          home.persistence."/persist".directories = [
            ".local/share/emacs-sandbox"
            "go"
            ".cache/go-build"
          ];
          xdg.desktopEntries.emacs = {
            name = "Emacs";
            genericName = "Text Editor";
            exec = "${launcher}/bin/emacs %F";
            icon = "emacs";
            terminal = false;
            categories = [
              "Development"
              "TextEditor"
            ];
            mimeType = [ "text/plain" ];
          };
        })
      ];
    }
  );
in
{
  options.services.emacs-broker = {
    enable = lib.mkEnableOption "restricted Emacs network and credential broker";
    user = lib.mkOption {
      type = lib.types.str;
      default = "josh";
    };
    model = {
      endpoint = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Complete stateless Responses endpoint (public HTTPS, port 443). Null keeps ChatGPT subscription sign-in.";
      };
      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Absolute runtime path to a private bearer-token file, outside the Nix store and editor mounts. Loaded by systemd; never use builtins.readFile.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = "gpt-5.6-sol";
        description = "Model identifier offered by the configured Responses service.";
      };
    };
    pageHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "go.dev"
        "pkg.go.dev"
        "nixos.org"
        "wiki.nixos.org"
        "nix.dev"
        "www.gnu.org"
        "orgmode.org"
        "docs.github.com"
      ];
      description = "Exact HTTPS page hosts; no subdomain wildcard. Page queries and fragments are removed.";
    };
  };

  config = lib.mkMerge [
    {
      services.emacs-broker.enable = true;
      home-manager.users.${cfg.user} = editor;
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = (cfg.model.endpoint == null) == (cfg.model.tokenFile == null);
          message = "emacs-broker: model.endpoint and model.tokenFile must be configured together.";
        }
        {
          assertion =
            cfg.model.tokenFile == null
            || (lib.hasPrefix "/" cfg.model.tokenFile && !lib.hasPrefix "/nix/store/" cfg.model.tokenFile);
          message = "emacs-broker: model.tokenFile must be an absolute runtime path outside the Nix store.";
        }
      ];
      users.groups.emacs-broker-clients = { };
      users.users.emacs-broker = {
        isSystemUser = true;
        group = "emacs-broker-clients";
        home = state;
      };
      users.users.${cfg.user}.extraGroups = [ "emacs-broker-clients" ];
      environment.systemPackages = [ login ];
      environment.persistence."/persist".directories = [
        {
          directory = state;
          user = "emacs-broker";
          group = "emacs-broker-clients";
          mode = "0700";
        }
      ];
      systemd.services.emacs-broker = {
        description = "Restricted Emacs network and credential broker";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ pkgs.gh ];
        environment = {
          HOME = state;
          GH_CONFIG_DIR = "${state}/github";
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        };
        serviceConfig = {
          ExecStart = "${package}/bin/emacs-broker --config ${policy}";
          User = "emacs-broker";
          Group = "emacs-broker-clients";
          LoadCredential = lib.optional (cfg.model.tokenFile != null) "model-token:${cfg.model.tokenFile}";
          StateDirectory = "emacs-broker";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "emacs-broker";
          RuntimeDirectoryMode = "0750";
          # Keep the directory inode mounted by running editors across restarts.
          RuntimeDirectoryPreserve = "restart";
          UMask = "0077";
          Restart = "on-failure";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
          CapabilityBoundingSet = "";
          LimitCORE = 0;
        };
      };
    })
  ];
}
