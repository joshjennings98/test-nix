{ pkgs, ... }:

{
  home.packages = [
    pkgs.iosevka
    pkgs.clojure
    pkgs.jdk
  ];
  fonts.fontconfig.enable = true;
  home.persistence."/persist".directories = [ ".local/state/emacs2" ];

  xdg.desktopEntries.emacs2 = {
    name = "emacs2";
    genericName = "Text Editor";
    exec = "emacs2 %F";
    icon = "emacs";
    terminal = false;
    categories = [
      "Development"
      "TextEditor"
    ];
  };
}
