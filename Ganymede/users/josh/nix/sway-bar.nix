{ pkgs ? import <nixpkgs> {} }:

pkgs.buildGoModule rec {
    pname = "sway-bar";
    version = "0.0.1";
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.alsaLib ];
    vendorHash = "sha256-RjpaTV0emYYzgM3uXi+c8AZqDivQLHhh72scgrJuOoU=";
    src = ../barista;  
    meta = with pkgs.lib; {
        description = "i3/sway bar created using Go with 'github.com/soumya92/barista'";
    };
}
