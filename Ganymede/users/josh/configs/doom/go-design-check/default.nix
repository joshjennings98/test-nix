{ lib, buildGoModule }:

buildGoModule {
  pname = "go-design-check";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      lib.cleanSourceFilter path type && builtins.baseNameOf path != "bin";
  };
  vendorHash = "sha256-TSAf1JeCC9SpOaXB6iNawKVn0lFiODygSzR6rNCUwYA=";
  subPackages = [ "cmd/go-design-check" ];
  checkPhase = ''
    runHook preCheck
    go test ./...
    runHook postCheck
  '';
  meta.mainProgram = "go-design-check";
}
