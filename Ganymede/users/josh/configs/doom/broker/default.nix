{ lib, buildGoModule }:
buildGoModule {
  pname = "emacs-broker";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  vendorHash = "sha256-izZF7lGHVOornw9rWy3tG3mcBY+GOlzJpALsPAOtDwE=";
  meta.mainProgram = "emacs-broker";
}
