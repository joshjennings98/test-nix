{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.packages = [
    (import ./minimal-emacs-package.nix {
      inherit pkgs;
      codexPackage = config.programs.codex.package;
    })
    pkgs.iosevka
    pkgs.clojure
    pkgs.jdk
  ];
  fonts.fontconfig.enable = true;
  home.persistence."/persist".directories = [ ".local/state/emacs2" ];

  home.file.".agents/skills".source = ../ai/skills;

  home.activation.createEmacsOrgDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Documents/org"
  '';

  xdg.desktopEntries.emacs = {
    name = "Emacs";
    genericName = "Text Editor";
    exec = "emacs %F";
    icon = "emacs";
    terminal = false;
    categories = [
      "Development"
      "TextEditor"
    ];
  };
}
