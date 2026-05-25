# README

This nix flake provides a [home-manager](https://github.com/nix-community/home-manager) set-up for my work laptop with `nix` on top of another operating system that is managed by my work (e.g. Ubuntu).

It means that everything added by work is unaffected (e.g. VPN etc.) but that everything I add is controlled by `nix`.

This should mean that in the event I need the laptop re-imaged (that has happened multiple times), then it is extremely simple to get everything returned to the same exact previous state (give or take).

## Installation

Install single user nix package manager:

```sh
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

Initialise the home-manager config from the flake

```sh
mkdir .config/home-manager
nix flake init -t github:joshjennings98/test-nix/test#Phobos
```

Setup `~/.aws/*` by modifying the `aws/*` in `.config/home-manager` so that home manager is aware of them, otherwise you will get conflicts. Alternatively remove them from home manager completely and do it manually.

Run `home-manager` to install everything:

```sh
nix run home-manager -- switch --flake .#josjen01 --extra-experimental-features nix-command --extra-experimental-features flakes
```

Finish setting up AWS so the fish prompt stops moaning:

```sh
aws eks --region us-west-2 update-kubeconfig ... # for as many profiles that we have
```

From here any changes to the config will just require:

```sh
home-manager switch --flake .#josjen01
```

Use `autorandr` to get the monitor information:

```sh
autorandr --fingerprint
```

Use this to update the `autorandr` placeholder configuration in `i3.nix`. Make sure to enable the `autorandr` section as well. Note, you may need to update the monitor configuration itself if different monitors are detected.

Copy over `fish_history` and put it in `~/.local/share/fish/fish_history`. I don't manage this in home-manager itself, just the rest of fish.

_Note: make sure that `i3lock` is installed through the standard package manager not home-manager so that it can determine the user correctly._

### Updating home manager config

Make any changes in `~/.config/home.nix` and run (adjust path to flake directory as necessary):

```
home-manager switch --flake .#josjen01
```

## Manual Stuff

Whilst this config attempts to make the most `nix` and `home-manager`, there are a few thing that it is too complex to do without using full `nixos`.

## `i3lock`

Install `i3lock` using apt so it can use the system-level auth stuff.

### Docker

Unfortunately systemd modules need to be set up to use the docker dameon and on [non-nixos operating systems this is not supported since it needs system level access](https://nixos.wiki/wiki/Docker#Running_the_docker_daemon_from_nix-the-package-manager_-_not_NixOS). Therefore it is recommended to [install docker the normal way :(](https://docs.docker.com/engine/install/).

For Ubuntu:

```sh
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Then run `docker run hello-world` to check everything is setup correctly.

*Note: It is possible that docker is already added to the debian sources. If you get an error about duplicated sources then have a look in `/etc/apt/sources.list.d` and check for duplicates.*

#### Other issues

You may need to add your user to the docker group (do this and log back in):

```sh
sudo groupadd docker
sudo usermod -aG docker $USER
```

On some Linux distributions there are more post install steps in order to get the daemon to start on boot. [See this page for details](https://docs.docker.com/engine/install/linux-postinstall/#configure-docker-to-start-on-boot-with-systemd).

### AWS CLI and kubectl configuration

For security reasons I won't include any of the configuration for this so you manually need to add the stuff in `.config/aws/`, then homemanager will manage the files and put them in the correct place. This file is `.gitignored` so it is safe to put stuff in it.

To get `kubectl` to work you need to configure the cluster access as per the documentation. Then use `kubectl config use-context xxx` to switch to the correct context.

### Firefox

I use the `firefox` that was installed already. This just makes it a bit easier in terms of corporate stuff as I am not fighting with their systems.

### Github

The tools should be installed but you probably still need to login and stuff.

## NixGL

_TODO: this section._

## Gnome specific stuff

I use `i3` mainly, but I have a configured Gnome setup too as it is the default desktop environment.

It would need things like wallpapers and monitors set up manually though.

_TODO: rest of this section._
