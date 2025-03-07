{ pkgs, inputs, ... }:
{
  programs.firefox = {
    enable = true;
    profiles.josh = {
      # https://discourse.nixos.org/t/firefox-extensions-with-home-manager/34108
      extensions.packages = with inputs.firefox-addons.packages.${pkgs.system}; [
        darkreader
        ublock-origin
        facebook-container
        gruvbox-dark-theme
        old-reddit-redirect
        reddit-enhancement-suite
        tridactyl
      ];
      bookmarks = [
        {
          name = "Nix";
          toolbar = true;
          bookmarks = [
            {
              name = "Package Search";
              tags = [ "nixos" "nix" ];
              url = "https://search.nixos.org/packages?channel=unstable";
            }
            {
              name = "Function Reference";
              tags = [ "nixos" "nix" ];
              url = "https://ryantm.github.io/nixpkgs/";
            }
            {
              name = "Home Manager";
              tags = [ "nixos" "nix" ];
              url = "https://nix-community.github.io/home-manager/options.xhtml";
            }
          ];
        }
      ];
      settings = {
        "browser.disableResetPrompt" = true;
        "browser.download.panel.shown" = true;
        "browser.download.useDownloadDir" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.shell.checkDefaultBrowser" = false;
        "browser.shell.defaultBrowserCheckCount" = 1;
        "browser.startup.homepage" = "about:Blank";
        "browser.urlbar.placeholderName" = "DuckDuckGo";
        "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"nav-bar":["back-button","forward-button","stop-reload-button","home-button","urlbar-container","downloads-button","library-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["tabbrowser-tabs","new-tab-button","alltabs-button"],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["save-to-pocket-button","developer-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"dirtyAreaCache":["nav-bar","PersonalToolbar","toolbar-menubar","TabsToolbar","widget-overflow-fixed-list"],"currentVersion":18,"newElementCount":4}'';
        "dom.security.https_only_mode" = true;
        "identity.fxaccounts.enabled" = false;
        "privacy.trackingprotection.enabled" = true;
        "signon.rememberSignons" = false;
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
      userChrome = ''
        @import "${
            builtins.fetchGit {
                url = "https://github.com/rockofox/firefox-minima";
                ref = "main";
                rev = "dc40a861b24b378982c265a7769e3228ffccd45a";
            }
          }/userChrome.css";
          '';
    };
  };

  xdg.mimeApps.defaultApplications = {
    "text/html" = [ "firefox.desktop" ];
    "text/xml" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
  };
}
