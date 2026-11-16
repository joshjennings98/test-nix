final: prev:

let
  emacsPackages = final.emacsPackagesFor prev.emacs-unstable;
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
      marginalia
      markdown-mode
      markdown-toc
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
  minimalEmacs = final.fetchFromGitHub {
    owner = "jamescherti";
    repo = "minimal-emacs.d";
    rev = "e797e802a1298d5656cfaaf107f59bbf1d6eed00";
    hash = "sha256-Sh4XXZ58To+fGD5Bx1XITOFEJfbmHB76tUvFaMBGdWc=";
  };
  emacsConfig = final.runCommand "emacs2-config" { } ''
    mkdir -p "$out"
    cp ${minimalEmacs}/early-init.el ${minimalEmacs}/init.el "$out/"
    cp ${../../configs/minimal-emacs}/*.el "$out/"
    substituteInPlace "$out/programming.el" \
      --replace-fail '@grammarDirectory@' '${grammars}/lib'
  '';
in
{
  emacs2 = final.writeShellApplication {
    name = "emacs2";
    runtimeInputs = with final; [
      clojure
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
      tests.startup = final.runCommand "emacs2-startup-check" { } ''
        export HOME="$TMPDIR/home"
        export XDG_STATE_HOME="$HOME/.local/state"
        mkdir -p "$HOME"
        ${emacs}/bin/emacs --batch \
          --eval '(setq user-emacs-directory "${emacsConfig}/")' \
          --load ${emacsConfig}/early-init.el \
          --load ${emacsConfig}/init.el \
          --load ${../../tests/emacs2-startup.el} \
          --funcall ert-run-tests-batch-and-exit
        touch "$out"
      '';
    };
  };
}
