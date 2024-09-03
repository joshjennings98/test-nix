{ pkgs ? import <nixpkgs> { } }:

with pkgs.python312Packages;

buildPythonPackage {
  pname = "detect-secrets";
  version = "1.0.3";
  buildInputs = [ pip requests pyyaml ];
  propagatedBuildInputs = [
    (pkgs.python312.withPackages (pkgs: with pkgs; [ pip requests pyyaml ]))
  ];
  src = pkgs.fetchFromGitHub {
    owner = "Yelp";
    repo = "detect-secrets";
    rev = "v1.0.3";
    sha256 = "sha256-O+V0u9urirhFNC7ExMRv5rO7dWbzPexywDdkLNGISIs=";
  };
}
