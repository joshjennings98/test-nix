#!/usr/bin/env python3

import os.path
import argparse
import i3ipc  # This package works for both i3 and Sway


def build_rename(i3, args):
    delim = args.delimiter
    length = args.max_title_length
    uniq = args.uniq

    def get_name(leaf, length):
        """
        Get the name of a window.
        """
        for identifier in ["app_id", "name", "window_title"]:
            name = getattr(leaf, identifier, None)
            if name is None:
                continue
            if name == "foot":
                return "terminal"
            return name[:length] if name else "?"
        return "?"

    def rename(i3, e):
        workspaces = i3.get_tree().workspaces()
        workdicts = i3.get_workspaces()
        visible = [workdict.name for workdict in workdicts if workdict.visible]
        visworkspaces = []
        focus = (
            [workdict.name for workdict in workdicts if workdict.focused] or [None]
        )[0]
        focusname = None

        commands = []
        for workspace in workspaces:
            names = [
                get_name(leaf, length).replace(":", "").replace("│", "").lower().strip()
                for leaf in workspace.leaves()
            ]

            if uniq:
                seen = set()
                names = [x for x in names if x not in seen and not seen.add(x)]
            names = delim.join(names)

            newname = f"{workspace.num}: {names} " if names else f"{workspace.num}"
            if workspace.name in visible:
                visworkspaces.append(newname)
            if workspace.name == focus:
                focusname = newname

            if workspace.name != newname:
                old = workspace.name.replace('"', '\\"')
                new = newname.replace('"', '\\"')
                commands.append(f'rename workspace "{old}" to "{new}"')

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
