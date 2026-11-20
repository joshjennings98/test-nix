{ pkgs }:

let
  emacsPackage = pkgs.emacs-unstable.overrideAttrs (old: {
    src = old.src.override {
      url = "https://github.com/emacs-mirror/emacs.git";
    };
  });
  emacsPackages = import ./minimal-emacs-agent-packages.nix {
    emacsPackages = pkgs.emacsPackagesFor emacsPackage;
  };
  agentSource = pkgs.lib.cleanSourceWith {
    src = ../configs/minimal-emacs/agent;
    filter = path: type: pkgs.lib.cleanSourceFilter path type && builtins.baseNameOf path != "bin";
  };
  grammars = emacsPackages.treesit-grammars.with-grammars (
    g: with g; [
      tree-sitter-bash
      tree-sitter-css
      tree-sitter-go
      tree-sitter-gomod
      tree-sitter-html
      tree-sitter-javascript
      tree-sitter-json
      tree-sitter-nix
      tree-sitter-python
      tree-sitter-typescript
      tree-sitter-yaml
    ]
  );
  emacs = emacsPackages.emacsWithPackages (
    e: with e; [
      aggressive-indent
      agent-shell
      apheleia
      avy
      buffer-terminator
      bufferfile
      cape
      cider
      clojure-mode
      consult
      corfu
      crontab-mode
      csv-mode
      diff-hl
      dockerfile-mode
      dumb-jump
      easysession
      elisp-refs
      embark
      embark-consult
      enhanced-evil-paredit
      evil
      evil-collection
      evil-ghostel
      evil-matchit
      evil-surround
      ghostel
      git-modes
      gnuplot
      goto-chg
      hcl-mode
      helpful
      highlight-defined
      indent-bars
      jenkinsfile-mode
      jinja2-mode
      kirigami
      lua-mode
      magit
      marginalia
      markdown-mode
      markdown-toc
      mcp-server
      mermaid-mode
      ob-mermaid
      nginx-mode
      nix-mode
      orderless
      org-appear
      outline-indent
      page-break-lines
      paredit
      rust-mode
      stripspace
      treesit-fold
      undo-fu
      undo-fu-session
      vertico
      vimrc-mode
      fish-mode
      yaml-mode
      yasnippet
      yasnippet-snippets
    ]
  );
  minimalEmacs = pkgs.fetchFromGitHub {
    owner = "jamescherti";
    repo = "minimal-emacs.d";
    rev = "e797e802a1298d5656cfaaf107f59bbf1d6eed00";
    hash = "sha256-Sh4XXZ58To+fGD5Bx1XITOFEJfbmHB76tUvFaMBGdWc=";
  };
  emacsConfig = pkgs.runCommand "minimal-emacs-config" { } ''
    mkdir -p "$out"
    cp ${minimalEmacs}/early-init.el ${minimalEmacs}/init.el "$out/"
    cp ${../configs/minimal-emacs}/*.el "$out/"
    mkdir -p "$out/agent"
    for file in agent-shell-inline agent-shell-permission-transient \
      agent-shell-output-limit agent-shell-completion-notify agent-shell-navigation \
      design-review design-review-fontification design-review-execution design-review-evidence design-review-async design-review-mcp \
      org-mermaid; do
      cp "${agentSource}/$file.el" "$out/agent/"
    done
    cp ${agentSource}/mermaid-config.json "$out/agent/"
    substituteInPlace "$out/programming.el" \
      --replace-fail '@grammarDirectory@' '${grammars}/lib'
  '';
in
pkgs.writeShellApplication {
  name = "emacs";
  runtimeInputs = with pkgs; [
    clojure
    codex-acp
    curl
    mermaid-cli
    socat
    i3
    xclip
    imagemagick
    clojure-lsp
    cljfmt
    jdk
    gopls
    go
    git
    ripgrep
    fd
    coreutils
    findutils
    diffutils
    rcs
    nixfmt
    black
    shfmt
    prettier
  ];
  text = ''
    exec ${emacs}/bin/emacs --init-directory=${emacsConfig} "$@"
  '';
  passthru = {
    inherit emacs emacsConfig grammars;
    tests.startup = pkgs.runCommand "minimal-emacs-startup-check" { } ''
      export HOME="$TMPDIR/home"
      export XDG_STATE_HOME="$HOME/.local/state"
      mkdir -p "$HOME"
      ${emacs}/bin/emacs --batch \
        --eval '(setq user-emacs-directory "${emacsConfig}/")' \
        --load ${emacsConfig}/early-init.el \
        --load ${emacsConfig}/init.el \
        --load ${../tests/emacs2-startup.el} \
        --funcall ert-run-tests-batch-and-exit
      touch "$out"
    '';
    tests.agents =
      pkgs.runCommand "minimal-emacs-agent-check"
        {
          nativeBuildInputs = [
            pkgs.git
            pkgs.go
            pkgs.python3
            pkgs.socat
            pkgs.curl
          ];
        }
        ''
          export HOME="$TMPDIR/home"
          export XDG_STATE_HOME="$HOME/.local/state"
          export XDG_CACHE_HOME="$HOME/.cache"
          export AGENT_SHELL_TEST_PYTHON="${pkgs.python3}/bin/python3"
          mkdir -p "$HOME"
          check_agents() {
            ${emacs}/bin/emacs --batch \
              --eval '(setq user-emacs-directory "${emacsConfig}/")' \
              --load ${emacsConfig}/early-init.el \
              --load ${emacsConfig}/init.el \
              --eval '(require (quote emacs2-agent-setup))' \
              --eval '(agent-shell-navigation-connect)' \
              --load "$1" \
              --funcall ert-run-tests-batch-and-exit
          }
          for suite in permissions inline-scrolling completion-notify output-limit navigation design-review; do
            check_agents "${agentSource}/tests/$suite.el"
          done
          check_agents ${../tests/emacs2-agents.el}
          touch "$out"
        '';
  };
}
