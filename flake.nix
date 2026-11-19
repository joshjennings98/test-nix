{
  description = "Josh's NixOS configs";
  outputs = { self }: {
    templates = {
      Ganymede = {
        path = ./Ganymede;
        description = "NixOS configuration for Ganymede";
      };
      Phobos = {
        path = ./Phobos;
        description = "NixOS configuration for Phobos (work laptop using Nix on Ubuntu)";
      };
    };
    defaultTemplate = self.templates.Ganymede;
  };
}
