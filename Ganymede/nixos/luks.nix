{
  boot.initrd.luks.devices."crypted".device = "/dev/disk/by-partlabel/root";

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;
}
