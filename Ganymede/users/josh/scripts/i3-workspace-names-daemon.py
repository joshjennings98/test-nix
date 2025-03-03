#!/usr/bin/env python3

import argparse
import i3ipc  # This package works for both i3 and Sway


def build_rename(i3, args):
    delim = args.delimiter
    length = args.max_title_length
    uniq = args.uniq

    def get_name(leaf, length):
        for identifier in ["app_id", "name", "window_title"]:
            name = getattr(leaf, identifier, None)
            if name and name.strip():
                return (
                    name[:length]
                    .replace(":", "")
                    .replace("│", "")
                    .replace("&", "+")
                    .lower()
                    .strip()
                )
        return "?"

    def rename(i3, _):
        workspaces = i3.get_tree().workspaces()
        visible_workspaces = {
            workspace.name for workspace in i3.get_workspaces() if workspace.visible
        }
        focused_workspace = next(
            (workspace.name for workspace in i3.get_workspaces() if workspace.focused),
            None,
        )

        commands = []
        for workspace in workspaces:
            names = [get_name(leaf, length) for leaf in workspace.leaves()]
            if uniq:
                names = list(
                    dict.fromkeys(names)
                )  # Remove duplicates while preserving order

            newname = (
                f"{workspace.num}: {delim.join(names)}" if names else f"{workspace.num}"
            )

            if workspace.name != newname:
                old = workspace.name.replace('"', '\\"')
                new = newname.replace('"', '\\"')
                commands.append(f'rename workspace "{old}" to "{new}"')

        if commands:
            i3.command(";".join(commands))

    return rename


def main():
    parser = argparse.ArgumentParser(
        description="Dynamically update Sway workspace names based on the applications running in each."
    )
    parser.add_argument(
        "-d", "--delimiter", help="Delimiter to separate window names.", default=" │ "
    )
    parser.add_argument(
        "-l", "--max_title_length", help="Max title length.", default=32, type=int
    )
    parser.add_argument(
        "-u",
        "--uniq",
        help="Remove duplicate names.",
        action="store_true",
        default=False,
    )
    args = parser.parse_args()

    i3 = i3ipc.Connection()  # Connects to Sway as well
    rename = build_rename(i3, args)
    for event in ["window::move", "window::new", "window::title", "window::close"]:
        i3.on(event, rename)
    i3.main()


if __name__ == "__main__":
    main()
