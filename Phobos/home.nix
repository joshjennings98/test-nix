{ lib, pkgs, ... }:
let
  config = ./.;
  homedir = "/home/josjen01";

  continuous-delivery-scripts = import ./continuous-delivery-scripts.nix { inherit pkgs; };
in
{
  home.username = "josjen01";
  home.homeDirectory = "${homedir}";

  home.packages = with pkgs; [
    awscli2
    black
    continuous-delivery-scripts
    dockerfile-language-server-nodejs
    go
    golangci-lint
    golangci-lint-langserver
    gopls
    iosevka
    keepassxc
    kubectl
    nil
    nixgl.nixGLIntel
    nodePackages.bash-language-server
    pyright
    tree
    yaml-language-server
    yq-go
  ];

  home.file.".aws/config".source = "${config}/aws/config"; 
  home.file.".aws/credentials".source = "${config}/aws/credentials"; 

  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile "${config}/fish/config.fish";
  };
  
  programs.fzf.enable = true;

  programs.git = {
    enable = true;
    userName = "joshjennings98";
    userEmail = "josh.jennings@arm.com";
    extraConfig = {
      push.autoSetupRemote = true;
    };
    difftastic.enable = true;
    # Avoid persisting any secrets in plaintext config files. Go needs git to have the secrets set and it might call git multiple times so it needs to
    # persist throughout the session. Environment variables don't work with .gitconfig so we can't just set it in the environment (also setting it in
    # the environment would only apply to the subprocess since it won't affect the parent). Expect a tmpfs mount (so it is lost on reboot) and extract
    # and store the secret in a file on there. This will be accessible for the whole session so it will only have to be decrypted once. It is not
    # ideal but at least we don't explicitly store the secret in any configuration
    package = pkgs.writeShellScriptBin "git" ''
      #!/bin/sh
      if [ -t 1 ] && [ -e ${homedir}/.secrets ] && [ "$(df --output=fstype ${homedir}/.secrets | tail -n 1)" = "tmpfs" ] && ! [ -e ${homedir}/.secrets/github ]; then
        GITHUB_VAR=$(keepassxc-cli attachment-export ${homedir}/passwords.kdbx env_secrets github --stdout | grep -v '^#' | awk -F= '{print $2}')
        if [ -z $GITHUB_VAR ]; then
          exit 1
        fi
        echo $GITHUB_VAR > ${homedir}/.secrets/github
      fi
      GITHUB_TOKEN=$(cat ${homedir}/.secrets/github 2> /dev/null)
      ${pkgs.git}/bin/git \
        -c url.https://$GITHUB_TOKEN:x-oauth-basic@github.com/Arm-Debug.insteadof=https://github.com/Arm-Debug \
        "$@"
    '';
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings = lib.importTOML "${config}/helix/config.toml";    
    languages = lib.importTOML "${config}/helix/languages.toml";    
  };

  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    theme = "Gruvbox Dark";
    font = {
      name = "Iosevka";
      size = 12;
    };
    # Kitty needs OpenGL to work properly so make the changes to how the binary is executed https://pmiddend.github.io/posts/nixgl-on-ubuntu/
    package = pkgs.writeShellScriptBin "kitty" ''
      #!/bin/sh
      ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.kitty}/bin/kitty "$@"
    '';
    settings = {
      shell = "${pkgs.fish}/bin/fish";
    };
    extraConfig = builtins.readFile "${config}/kitty/kitty.conf";
  };

  xdg = {
    enable = true;
    desktopEntries = {
      kitty = {
        name = "Kitty";
        genericName = "Terminal";
        exec = "kitty";
        icon = "${pkgs.kitty}/share/icons/hicolor/256x256/apps/kitty.png";
        terminal = false;
        categories = [ "Utility" ];
      };
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.stateVersion = "23.11"; # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
}
