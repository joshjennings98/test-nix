{
  description = "Josh's NixOS configs";
  outputs = { self }: {
    templates = {
      Ganymede = {
        path = ./Ganymede;
        description = "NixOS configuration for Ganymede";
      };
    };
    defaultTemplate = self.templates.Ganymede;
  };
}
