# README

This nix flake provides a [home-manager](https://github.com/nix-community/home-manager) set-up for my work laptop with `nix` on top of another operating system that is managed by my work (e.g. Ubuntu).

It means that everything added by work is unaffected (e.g. VPN etc.) but that everything I add is controlled by `nix`.

This should mean that in the event I need the laptop re-imaged (that has happened multiple times), then it is extremely simple to get everything returned to the same exact previous state (give or take).

## Installation

Install single user nix package manager (run these installation commands in Bash, not fish):

```bash
sh <(curl -L https://nixos.org/nix/install) --no-daemon
. "$HOME/.nix-profile/etc/profile.d/nix.sh"
```

Initialise the home-manager config from the flake:

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
mkdir -p "$HOME/.config/home-manager"
cd "$HOME/.config/home-manager"
nix flake init -t github:joshjennings98/test-nix/test#Phobos
```

If using an existing checkout, run from `Phobos/` instead.

Check `aws/config` and `aws/credentials` in the flake directory before switching (see the [AWS notes below](#aws-cli-and-kubectl-configuration)). Back up any existing `~/.aws/*` files so they don't conflict with home-manager. Alternatively remove the two AWS `home.file` entries from `nix/home.nix` and manage them manually.

Run `home-manager` to install everything:

```bash
nix run github:nix-community/home-manager -- switch --flake .#josjen01
```

Finish setting up AWS and kubectl below so the fish prompt stops moaning.

### If that doesn't work

If `nix` isn't found, source the profile script above or open a new Bash session.

Check that you're in the directory containing `flake.nix`. There is no need to run `home-manager init --switch` as that creates a separate starter config.

In a Git checkout, new config files need to be tracked for Nix to see them.

### Updating home manager config

Make any changes in `<config_dir>/nix/home.nix` or the other modules in `nix/` and run from the flake directory:

```sh
home-manager switch --flake .#josjen01
```

## Manual Stuff

Whilst this config attempts to make the most of `nix` and `home-manager`, there are a few things that are too complex to do without using full `nixos`.

### i3 session and screen locking

Install `i3lock` using apt so it can use the system-level auth stuff. `xss-lock` is also needed for automatic locking:

```sh
sudo apt install i3lock xss-lock
```

After the first switch, add the i3 session to the login screen:

```sh
sudo "$HOME/setup.sh" install
```

Log out and select **i3 (Nix)**. Re-run the script after updating i3 so the session points at the new Nix store path.

Make sure `~/.local/bin` and the Nix commands are on the i3 session's PATH, and check that locking and unlocking work.

### Monitors

Use `autorandr` to get the monitor information (from i3):

```sh
autorandr --fingerprint
xrandr --query
```

Use this to update the `autorandr` configuration in `nix/i3.nix`. It is already enabled with `work` and `laptop` profiles. Note, you may need to update the monitor configuration and `workspaceOutputAssign` if different monitors are detected.

After switching, run `monitors --force` to apply the profile and wallpaper.

### Docker

Unfortunately the Docker daemon needs [system-level setup on non-NixOS operating systems](https://nixos.wiki/wiki/Docker#Running_the_docker_daemon_from_nix-the-package-manager_-_not_NixOS) that this home-manager config doesn't handle. Therefore it is recommended to [install docker the normal way :(](https://docs.docker.com/engine/install/).

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

Then run `sudo docker run hello-world` to check everything is set up correctly.

*Note: It is possible that docker is already added to the debian sources. If you get an error about duplicated sources then have a look in `/etc/apt/sources.list.d` and check for duplicates.*

#### Other issues

You may need to add your user to the docker group (do this and log back in). Note that this gives root-level access:

```sh
sudo groupadd -f docker
sudo usermod -aG docker "$USER"
```

After logging back in, verify with `docker run hello-world`.

On some Linux distributions there are more post install steps in order to get the daemon to start on boot. [See this page for details](https://docs.docker.com/engine/install/linux-postinstall/#configure-docker-to-start-on-boot-with-systemd).

### Name service

Sometimes there are issues where you get errors like `Error (initialization): User josjen01 has no home directory` (or when running `nix develop` and dropping into a bash shell) even if it is set in `nix/home.nix`.

To fix this install the _Name Service Non-Caching Daemon_:

```sh
sudo apt install nsncd
systemctl status nsncd
```

Then verify it works via `systemctl status nsncd` and the issue should go away.

#### Why nsncd over nscd?

`nscd` doesn't play nice with `sssd` and `sssd` is used by the host system for authentication.

Puppet will literally delete the `nscd` from the machine soon after installing it.

Traditional nscd passwd/group caching can interfere with SSSD's own caching. So SSSD remains responsible for caching; `nsncd` bridges Nix's glibc to Ubuntu's host NSS stack and implements the NSCD protocol without caching anything.

### AWS CLI and kubectl configuration

Fill in the placeholder `aws/config` and `aws/credentials` files in the flake directory with the ARNs, sessions and profiles we need. Home-manager links these into `~/.aws/`, so both files need to exist before building. `nix flake init` copies the template without creating a Git repo.

The point is to keep the work-specific configuration out of source control, not to use home-manager to secure credentials. Keep the repo copies as placeholders and fill in the local copies after installing the template. These are just profile/SSO settings, not access keys or tokens; AWS stores the actual SSO tokens separately.

To get `kubectl` to work you need to configure the cluster access as per the documentation. Repeat for the profiles/clusters we need:

```sh
aws eks --region us-west-2 update-kubeconfig --name <cluster-name> --profile <profile-name>
kubectl config use-context <context-name>
```

Adjust the region as necessary. The fish prompt needs a current context; afterwards `kctx` can be used to switch between them.

### Firefox

I use the `firefox` that was installed already. This just makes it a bit easier in terms of corporate stuff as I am not fighting with their systems.

### GitHub

The tools should be installed but you probably still need to login and stuff:

```sh
gh auth login
gh auth status
```

### NixGL

Kitty and File Roller are wrapped with NixGL in `nix/home.nix` so they can use the host graphics drivers. Just run them normally, no extra prefix needed.

### AI Proxy

Replace the `baseURL = "placeholder";` in `nix/ai.nix` with the correct work AI endpoint before using OpenCode (or other agents). Use the full API base URL, including its path, not just the hostname, then run `home-manager switch --flake .#josjen01` to apply it.

Keep the repo version as a placeholder and fill in the local copy after installing the template, just like the AWS config. OpenCode reads the API key from `OPENAI_API_KEY`, so set that in its environment rather than putting the key in the config.

### Gnome specific stuff

I use `i3` mainly, but I have a configured Gnome setup too as it is the default desktop environment.

It needs things like wallpapers and monitors set up manually in `gnome-settings`. The wallpaper is at `~/Pictures/Wallpapers/wallpaper.jpg`; in i3 the `monitors` script sets it automatically.

### Backing up history etc.

It is a good idea to back up history and any passwords added to the keepass database in case access is lost to the laptop.

Copy over `fish_history` and put it in `~/.local/share/fish/fish_history`, preferably while fish isn't running. I don't manage this in home-manager itself, just the rest of fish.

### Git Repos

Use the fish `Git` function to clone repos and set up worktrees in `~/Git/`:

```fish
Git <repo>
Git <repo> <branch>
```

This uses the `Arm-Debug` organisation and assumes a `main` branch. `Git` without arguments just takes you to `~/Git/`. There isn't an init script installed there.
