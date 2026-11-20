{ emacsPackages }:

# Agent Shell, ACP and Shell Maker come from the locked Emacs package set.
# This MCP server is not packaged there; pin its source explicitly.
emacsPackages.overrideScope (
  final: _prev: {
    mcp-server = final.trivialBuild {
      pname = "mcp-server";
      version = "0.7.0";
      src = builtins.fetchTree {
        type = "github";
        owner = "rhblind";
        repo = "emacs-mcp-server";
        rev = "a5d749cf9880598f66308545985526fd4460627f";
        narHash = "sha256-ugaOqSnphgUKVm0+sem6oNthOFHIB5uIpksyTuGSsxE=";
      };
      postPatch = ''
        cp tools/*.el .
      '';
    };
  }
)
