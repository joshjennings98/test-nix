{ ... }:
{
  home-manager.users.josh =
    {
      config,
      inputs,
      pkgs,
      ...
    }:
    let
      emacsPackage = pkgs.emacs-unstable;
      emacsPackages = pkgs.emacsPackagesFor emacsPackage;
      aspell = pkgs.aspellWithDicts (dictionaries: [ dictionaries.en ]);
      englishWords = pkgs.runCommand "british-english-words" { } ''
        ${aspell}/bin/aspell -d en_GB dump master \
          | ${aspell}/bin/aspell -l en expand \
          | tr ' ' '\n' | LC_ALL=C sort -u > "$out"
      '';
      doomConfig = pkgs.runCommand "doom-config" { } ''
        mkdir -p "$out"
        cp -rs ${../configs/doom}/. "$out/"
        ln -s ${englishWords} "$out/english-words"
      '';
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
    in
    {
      imports = [ inputs.nix-doom-emacs-unstraightened.homeModule ];

      home.packages = [
        pkgs.gopls
        pkgs.codex-acp
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
        doomDir = doomConfig;
        doomLocalDir = "${config.xdg.dataHome}/nix-doom";
        emacs = emacsPackage;
        provideEmacs = true;

        extraPackages = _epkgs: [
          treeSitterGrammars
        ];

        extraBinPackages = [
          aspell
          pkgs.codex-acp
          pkgs.fd
          pkgs.git
          pkgs.go
          pkgs.gopls
          pkgs.ripgrep
        ];
      };
    };
}
