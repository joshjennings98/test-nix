{ ... }:

{
  programs.firefox = {
    enable = true;

    policies = {
      BlockAboutConfig              = false;
      DisableFirefoxStudies         = true;
      DisableFirefoxAccounts        = true;
      DisableFirefoxScreenshots     = true;
      DisableForgetButton           = true;
      DisableMasterPasswordCreation = true;
      DisableProfileImport          = true;
      DisableProfileRefresh         = true;
      DisableSetDesktopBackground   = true;
      DisablePocket                 = true;
      DisableTelemetry              = true;
      ExtensionSettings = let
        moz = short: "https://addons.mozilla.org/firefox/downloads/latest/${short}/latest.xpi";
      in {
        "*".installation_mode = "blocked";

        "uBlock0@raymondhill.net" = {
          install_url       = moz "ublock-origin";
          installation_mode = "force_installed";
          updates_disabled  = false;
          private_browsing  = true;
        };
        "addon@darkreader.org" = {
          install_url       = moz "darkreader";
          installation_mode = "force_installed";
          updates_disabled  = false;
          private_browsing  = true;
        };
        "jid1-xUfzOsOFlzSOXg@jetpack" = {
          install_url       = moz "reddit-enhancement-suite";
          installation_mode = "force_installed";
          updates_disabled  = false;
          private_browsing  = true;
        };
        "{9063c2e9-e07c-4c2c-9646-cfe7ca8d0498}" = {
          install_url       = moz "old-reddit-redirect";
          installation_mode = "force_installed";
          updates_disabled  = false;
          private_browsing  = true;
        };
        "@contain-facebook" = {
          install_url       = moz "facebook-container";
          installation_mode = "force_installed";
          updates_disabled  = false;
          private_browsing  = true;
        };
      };
      Preferences = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "browser.ml.chat.enabled" = false;
        "browser.ml.chat.page" = false;
        "browser.ml.linkPreview.enabled" = false;
        "browser.tabs.groups.smart.enabled" = false;
        "browser.tabs.groups.smart.userEnabled" = false;
        "browser.translations.enable" = false;
        "extensions.ml.enabled" = false;
        "pdfjs.enableAltText" = false;
        "browser.ai.control.default" = "blocked";
        "browser.ai.control.linkPreviewKeyPoints" = "blocked";
        "browser.ai.control.pdfjsAltText" = "blocked";
        "browser.ai.control.sidebarChatbot" = "blocked";
        "browser.ai.control.smartTabGroups" = "blocked";
        "browser.ai.control.translations" = "blocked";
        "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"nav-bar":["back-button","forward-button","stop-reload-button","home-button","urlbar-container","downloads-button","library-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["tabbrowser-tabs","new-tab-button","alltabs-button"],"PersonalToolbar":["personal-bookmarks"]},"seen":["save-to-pocket-button","developer-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"dirtyAreaCache":["nav-bar","PersonalToolbar","toolbar-menubar","TabsToolbar","widget-overflow-fixed-list"],"currentVersion":18,"newElementCount":4}'';
      };
      ManagedBookmarks = [
        {
          toplevel_name = "Nix";
        }
        {
          name = "Package Search";
          url = "https://search.nixos.org/packages?channel=unstable";
        }
        {
          name = "Function Reference";
          url = "https://ryantm.github.io/nixpkgs/";
        }
        {
          name = "Home Manager";
          url = "https://nix-community.github.io/home-manager/options.xhtml";
        }
      ];
      FirefoxHome = {
        TopSites          = false;
        SponsoredTopSites = false;
        Highlights        = false;
        Pocket            = false;
        Stories           = false;
        SponsoredPocket   = false;
        SponsoredStories  = false;
        Snippets          = false;
        Locked            = false;
      };
      Homepage = {
        Locked    = true;
        StartPage = "previous-session";
      };
    };
  };

  xdg.mimeApps.defaultApplications = {
    "text/html" = [ "firefox.desktop" ];
    "text/xml" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
  };
}
