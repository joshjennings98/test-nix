{ pkgs }:
''
#!/bin/sh

set -e

USAGE="Usage: $0 {install|uninstall}"

I3_NIX_BIN="/usr/bin/i3-nix-session"
I3_NIX_XSESSION="/usr/share/xsessions/i3-nix.desktop"

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1
    fi
}

install_i3_session() {
    echo "Installing i3 (Nix) session for GDM…"

    # Wrapper used as the X session command
    cat <<EOF >"$I3_NIX_BIN"
#!/bin/sh
exec ${pkgs.i3}/bin/i3 "\$@"
EOF
    chmod +x "$I3_NIX_BIN"

    # X session entry so it appears in the GDM session list
    mkdir -p "$(dirname "$I3_NIX_XSESSION")"
    cat <<EOF >"$I3_NIX_XSESSION"
[Desktop Entry]
Name=i3 (Nix)
Comment=i3 session using Nix-installed i3
Exec=$I3_NIX_BIN
TryExec=$I3_NIX_BIN
Type=Application
DesktopNames=i3
EOF

    echo "i3 (Nix) GDM session installed."
    echo "Log out and select \"i3 (Nix)\" on the GDM login screen."
}

install_all() {
    install_i3_session
    echo "Install complete."
}

uninstall_files() {
    echo "Uninstalling i3 (Nix) session…"

    rm -f "$I3_NIX_BIN"
    rm -f "$I3_NIX_XSESSION"

    echo "Uninstall complete."
}

### Main ###

check_root

case "$1" in
    install)
        install_all
        ;;
    uninstall)
        uninstall_files
        ;;
    *)
        echo "$USAGE"
        exit 1
        ;;
esac
''
