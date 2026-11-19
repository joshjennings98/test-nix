{
  # LUKS device "crypted" is declared by disko (see install.sh). /persist is
  # marked neededForBoot in impermanence.nix; /nix lives on the same LVM and
  # needs the same flag so the store is available before user services start.
  fileSystems."/nix".neededForBoot = true;
}
