# README

This nix flake provides a [home-manager](https://github.com/nix-community/home-manager) set-up for my work laptop with `nix` on top of another operating system that is managed by my work (e.g. Ubuntu).

It means that everything added by work is unaffected (e.g. VPN etc.) but that everything I add is controlled by `nix`.

This should mean that in the event I need the laptop re-imaged (that has happened multiple times), then it is extremely simple to get everything returned to the same exact previous state (give or take).

## Installation

Install single user nix package manager:

```sh
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

Install from the flake:

```
export NIX_CONFIG="experimental-features = nix-command flakes"
mkdir nix-cfg
nix flake init -t github:joshjennings98/test-nix#Phobos
nix run home-manager switch --flake .#josjen01
```

### If that doesn't work

Install home manager:

```
nix run home-manager/master -- init --switch
```

Copy the files from the above flake into `.config/home-manager` and run:

```
home-manager switch --flake .config/home-manager/
```

### Updating home manager config

Make any changes in `nix-cfg/home.nix` and run (adjust path to flake directory as necessary):

```
home-manager switch --flake ./nix-cfg#josjen01
```

## Manual Stuff

Whilst this config attempts to make the most `nix` and `home-manager`, there are a few thing that it is too complex to do without using full `nixos`.

### AWS CLI and kubectl configuration

For security reasons I won't include any of the configuration for this so you manually need to add the stuff in `${config}/aws/`, then homemanager will manage the files and put them in the correct place.

To get `kubectl` to work you need to configure the cluster access as per the documentation. Then use `kubectl config use-context xxx` to switch to the correct context.

### Tmpfs mounts

Secrets are written to a tmpfs volume when they are first used so that they are available for the session and don't get hardcoded in any configuration files.

This needs a tmpfs mount set up. This can be done manually on every boot or you can add the following to `/etc/fstab`

```
tmpfs <home directory>/.secrets/ tmpfs defaults 0 1
```

This way the tmpfs mount will always be available on boot.

### Wallpaper

I can't seem to easily set this so you must go into the `gnome-settings` and set it manually.

### Backing up history etc.

It is a good idea to backup history and any passwords added to the keepass database in case access is lost to the laptop.
