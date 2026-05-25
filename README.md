# README

Boot the NixOS live ISO, then run:

```sh
curl -o install.sh https://raw.githubusercontent.com/joshjennings98/test-nix/main/install.sh
sh install.sh
```

To install from a non-default branch (e.g. while iterating on changes), fetch
the script from that branch *and* tell it which ref to pull the flake template
from:

```sh
curl -o install.sh https://raw.githubusercontent.com/joshjennings98/test-nix/test/install.sh
sh install.sh --ref test
```

Pass `--no-lock` to drop `flake.lock` before `nixos-install` and let nix
re-resolve every input to its latest revision.

## Acknowledgements

The following pages helped me a lot:

* https://github.com/Misterio77/nix-starter-configs
* https://discourse.nixos.org/t/firefox-extensions-with-home-manager/34108
* https://cmacr.ae/blog/managing-firefox-on-macos-with-nix/
* https://ertt.ca/nix/shell-scripts/
* https://www.youtube.com/watch?v=YPKwkWtK7l0
* https://nixos.asia/en/nixos-install-disko
* https://guekka.github.io/nixos-server-1/
