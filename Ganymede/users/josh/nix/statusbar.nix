{ pkgs ? import <nixpkgs> {} }:

pkgs.buildGoModule rec {
    pname = "statusbar";
    version = "0.0.17";
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.alsa-lib ];
    vendorHash = "sha256-JnW9163lf0H3xgsVx7xVtc1BAyLg8bq7FPitzE4wamE=";
    src = ../statusbar;  
    meta = with pkgs.lib; {
        description = "i3/sway bar created using Go with 'github.com/soumya92/barista'";
    };
}
