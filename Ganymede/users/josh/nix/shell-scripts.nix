{ pkgs, lib, ... }:

let
  parseScriptName = filename: (lib.removeSuffix ".sh" (builtins.baseNameOf filename));

  makeScript = { filename, deps ? [] }: pkgs.stdenv.mkDerivation {
    name = parseScriptName filename;
    src = builtins.dirOf filename;
    buildInputs = deps;

    installPhase = ''
      mkdir -p $out/bin
      cp ${filename} $out/bin/${parseScriptName filename}
      chmod +x $out/bin/${parseScriptName filename}
    '';

    meta = {
      description = "A script called ${parseScriptName filename}";
    };
  };
in
{
  tmux-sessioniser = makeScript { filename = ../scripts/tmux-sessioniser.sh; deps = [ pkgs.tmux ]; };
  xauto_lock_screen = makeScript { filename = ../scripts/xauto_lock_screen.sh; deps = [ pkgs.xorg.xprop pkgs.i3lock ]; };
}
