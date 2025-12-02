{ pkgs, inputs, ... }:
{
  programs.firefox = {
    enable = true;
    profiles.josh = {
      # https://discourse.nixos.org/t/firefox-extensions-with-home-manager/34108
      extensions.packages = with inputs.firefox-addons.packages.${pkgs.system}; [
        darkreader
        ublock-origin
      ];
      settings = {
        "browser.disableResetPrompt" = true;
        "browser.download.panel.shown" = true;
        "browser.download.useDownloadDir" = false;
        "browser.ml.chat.enabled" = false;
        "browser.ml.chat.menu" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.shell.checkDefaultBrowser" = false;
        "browser.shell.defaultBrowserCheckCount" = 1;
        "browser.toolbars.bookmarks.visibility" = "never";
        "browser.startup.homepage" = "about:blank";
        "browser.urlbar.placeholderName" = "DuckDuckGo";
        "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["addon_darkreader_org-browser-action","_41f9e51d-35e4-4b29-af66-422ff81c8b41_-browser-action"],"nav-bar":["back-button","forward-button","stop-reload-button","vertical-spacer","home-button","urlbar-container","ublock0_raymondhill_net-browser-action","addon_darkreader_org-browser-action","reset-pbm-toolbar-button","unified-extensions-button","bookmarks-menu-button","downloads-button"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["tabbrowser-tabs","new-tab-button","alltabs-button"],"vertical-tabs":[],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["save-to-pocket-button","developer-button","ublock0_raymondhill_net-browser-action","addon_darkreader_org-browser-action","screenshot-button","_41f9e51d-35e4-4b29-af66-422ff81c8b41_-browser-action"],"dirtyAreaCache":["nav-bar","PersonalToolbar","toolbar-menubar","TabsToolbar","widget-overflow-fixed-list","unified-extensions-area","vertical-tabs"],"currentVersion":23,"newElementCount":7}'';
        "dom.security.https_only_mode" = true;
        "identity.fxaccounts.enabled" = true;
        "privacy.trackingprotection.enabled" = true;
        "signon.rememberSignons" = false;
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
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

