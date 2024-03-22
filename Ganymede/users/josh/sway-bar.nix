{ pkgs ? import <nixpkgs> {} }:

pkgs.buildGoModule rec {
    pname = "sway-bar";
    version = "0.0.1";
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.alsaLib ];
    vendorHash = "sha256-yqPgFhoibZoCkBF7XzDFgZS7ScqsAEPCcX7baknRO1E=";
    src = ./barista;  
    meta = with pkgs.lib; {
        description = "i3/sway bar created using Go with 'github.com/soumya92/barista'";
    };
}
