{ lib, pkgs, inputs, ... }: {

  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  boot.initrd.postDeviceCommands = lib.mkAfter ''
  
  # Mount old root
  mkdir /btrfs_tmp
  mount /dev/root_vg/root /btrfs_tmp

  # Backup previous root
  if [[ -e /btrfs_tmp/root ]]; then
    mkdir -p /btrfs_tmp/old_roots
    timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
    mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
  fi

  # Delete backups older than 7 days
  delete_subvolume_recursively() {
    IFS='\n'
    for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
      delete_subvolume_recursively "/btrfs_tmp/$i"
    done
    btrfs subvolume delete "$1"
  }

  for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +7); do
    delete_subvolume_recursively "$i"
  done

  # Create new clean root    
  btrfs subvolume create /btrfs_tmp/root
  umount /btrfs_tmp
  '';

  programs.fuse.userAllowOther = true;

  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/passwords"
      "/var/log"
      "/var/cache/tuigreet"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
    ];
    users.josh = {
      directories = [
        ".local/state/nix/profiles" # needed for home-manager impermanence module to work
        { directory = "nix-config"; user = "josh"; group = "users"; mode = "u=rwx,g=rx,o=rx"; } # persist nix config files
      ];
    };
  };

  security.sudo.extraConfig = ''
    # rollback results in sudo lectures after each reboot
    Defaults lecture = never
  '';
}
