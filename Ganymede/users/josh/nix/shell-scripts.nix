{ pkgs, lib, ... }:

let
  parseScriptName = filename:
    lib.removeSuffix ".sh" (builtins.baseNameOf filename);

  makeScript = { filename, name ? parseScriptName filename, deps ? [], env ? {} }:
  pkgs.stdenv.mkDerivation {
    pname = name;
    version = "1.0";

    src = filename;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/${name}
      chmod +x $out/bin/${name}

      wrapProgram $out/bin/${name} \
        --prefix PATH : ${lib.makeBinPath deps} \
        ${lib.concatStringsSep " " (
          lib.mapAttrsToList (key: value: ''--set ${key} "${value}"'') env
        )}
    '';
  };
in
{
  tmux-popup = makeScript {
    filename = ../scripts/tmux-popup.sh;
    deps = [ pkgs.tmux pkgs.coreutils ];
  };

  switch-project = makeScript {
    filename = ../scripts/switch-project.sh;
    deps = [
      pkgs.tmux
      pkgs.fzf
      pkgs.findutils
      pkgs.coreutils
      pkgs.tmux
    ];
  };

  switch-open-project = makeScript {
    filename = ../scripts/switch-open-project.sh;
    deps = [
      pkgs.tmux
      pkgs.fzf
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.coreutils
    ];
  };

  password = makeScript {
    filename = ../scripts/password.sh;
    deps = [ pkgs.keepassxc pkgs.fzf pkgs.findutils pkgs.gnugrep pkgs.coreutils ];
  };

  yq2 = makeScript {
    filename = ../scripts/yq2.sh;
    deps = [ pkgs.yq-go pkgs.jq pkgs.fzf pkgs.coreutils ];
  };

  xauto_lock_screen = makeScript {
    filename = ../scripts/xauto_lock_screen.sh;
    deps = [ pkgs.xorg.xprop pkgs.i3lock ];
  };
}
