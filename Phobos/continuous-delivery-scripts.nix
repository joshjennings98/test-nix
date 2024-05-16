{ pkgs ? import <nixpkgs> { } }:
  with pkgs.python3Packages;

buildPythonPackage rec {
  pname = "continuous-delivery-scripts";
  version = "3.2.0";
  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-fYCeyX4w6HhEngSyUVzuHEYCwtsM5VHDVwjYk64tEZE=";
  };
  doCheck = false;
  propagatedBuildInputs = [ gitpython packaging python-dotenv toml wcmatch ];
}
