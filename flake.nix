{
  description = "Base flake";
  outputs = { self }: {
    templates = {
      nix-cfg = {
        path = ./nix-cfg;
        description = "Nix configuration";
      };
    };
    defaultTemplate = self.templates.nix-cfg;
  };
}
