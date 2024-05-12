{ inputs, lib, config, pkgs, ...}: 
{
  # Import other home-manager modules here (either via flakes like inputs.xxx.yyy or directly like ./zzz.nix)
  imports = [
    ./hardware-configuration.nix
    
    inputs.disko.nixosModules.default
    ./disko.nix

    ./impermanence.nix

    ./nvidia.nix

    ./users.nix
  ];

  # Global nixpkgs settings
  nixpkgs = {
    overlays = [ ]; # Add overlays here either from flakes or inline (see https://github.com/Misterio77/nix-starter-configs/blob/main/minimal/nixos/configuration.nix and https://github.com/Misterio77/nix-config/tree/main/overlays) 
    config = {
      allowUnfree = true;
    };
  };

  # This will add each flake input as a registry to make nix3 commands consistent with this flake
  nix.registry = (lib.mapAttrs (_: flake: {inherit flake;})) ((lib.filterAttrs (_: lib.isType "flake")) inputs);

  # Add the inputs to the system's legacy channels making legacy nix commands consistent as well!
  nix.nixPath = [ "/etc/nix/path" ];
  environment.etc =
    lib.mapAttrs'
    (name: value: {
      name = "nix/path/${name}";
      value.source = value.flake;
    })
    config.nix.registry;

  # Settings for NixOS
  nix.settings = {
    experimental-features = "nix-command flakes"; # Enable flakes and new 'nix' command
    auto-optimise-store = true; # Deduplicate and optimize nix store
  };

  # Setup for GRUB
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  # Kernel options
  boot.kernelParams = [
    "quiet" # Don't print SystemD startup stuff
  ];

  # Use greetd (CLI greeter) for login
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --user-menu --cmd 'sway --unsupported-gpu'"; # --unsupported-gpu for use with nvidia drivers
      };
    };
  };

  # USB daemons
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  # Audio
  hardware.pulseaudio.enable = true;

  # Homemanager can't manage default shell and sway needs to be available for greetd. Steam also needs to be global
  programs.fish.enable = true;
  programs.sway.enable = true;
  programs.steam.enable = true;

  # Other packages that should be available globally
  environment.systemPackages = with pkgs; [
    ncpamixer # ncurses pulse audio mixer
    networkmanager # install the useful software for network manager (nmtui etc.)
  ];

  # Global environment variables
  environment.sessionVariables = rec {
    WLR_NO_HARDWARE_CURSORS = "1"; # fix missing cursors in sway/wayland when using nvidia drivers
    WLR_RENDERER = "vulkan"; # supposedly prevent screen flickering with nvidia drivers in sway/wayland
    XWAYLAND_NO_GLAMOR = "1"; # also supposedly sorts out the screen flickering with nvidia drivers
  };

  # Networking stuff
  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [];
      allowedUDPPorts = [];
    };
    hostName = "Ganymede";
    networkmanager.enable = true;
  };

  # Misc settings
  time.timeZone = "London/Europe";
  i18n = {
    defaultLocale = "en_GB.UTF-8";
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.11";
}
