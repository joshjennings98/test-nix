{ pkgs ? import <nixpkgs> { } }:
with pkgs.python311Packages;

buildPythonPackage rec {
  pname = "continuous-delivery-scripts";
  version = "3.2.0";
  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-fYCeyX4w6HhEngSyUVzuHEYCwtsM5VHDVwjYk64tEZE=";
  };
  doCheck = false;
  format = "setuptools";
  propagatedBuildInputs = [ gitpython packaging python-dotenv toml wcmatch ];
}
