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
        # command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --user-menu --cmd 'sway'"; # sway
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --user-menu --cmd 'startx ${pkgs.i3}/bin/i3'"; # i3
      };
    };
  };

  # i3 support since wayland isn't great on nvidia GPUs
  services.xserver = {
    enable = true;
    windowManager.i3.enable = true;
    displayManager = {
      startx.enable = true; # don't install xorg or startx manually, this will do all configuration etc.
      setupCommands = "${pkgs.xorg.xrandr}/bin/xrandr --output DP-0 --mode 3440x1440 --rate 164.90";
    };
  };
  services.displayManager = {
    defaultSession = "none+i3";
  };
  # programs.sway.enable = true; # no point enabling whilst it isn't used

  # USB stuff
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  # Audio
  hardware.pulseaudio.enable = true;

  # Homemanager can't manage default system shell
  programs.fish.enable = true;

  # For some reason you need to set steam globally
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  # Disable x11-ssh-askpass
  programs.ssh.enableAskPassword = false;

  # Needed for GTK settings
  programs.dconf.enable = true;

  # Other packages that should be available globally
  environment.systemPackages = with pkgs; [
    pavucontrol # pulse audio mixer
    networkmanager # install the useful software for network manager (nmtui etc.)
  ];

  # Fonts need to be set up in fonts.packages
  fonts.packages = with pkgs; [
    ubuntu_font_family
    iosevka
  ];

  # Global environment variables
  environment.sessionVariables = {
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
