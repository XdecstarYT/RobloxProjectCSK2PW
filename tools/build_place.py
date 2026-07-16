#!/usr/bin/env python3
"""
build_place.py — convert the Nexus source tree into a Roblox .rbxlx place file
WITHOUT Rojo (no toolchain required beyond Python 3).

Usage:
    python3 tools/build_place.py            # writes ./Nexus.rbxlx
    python3 tools/build_place.py out.rbxlx  # custom output path

It mirrors Rojo's folder mapping so the produced place is identical in structure
to `rojo build`:

  * a directory with init.server.luau  -> Script       (named after the dir)
  * a directory with init.client.luau  -> LocalScript
  * a directory with init.luau         -> ModuleScript
  * any other directory                -> Folder
  * a  *.server.luau file              -> Script
  * a  *.client.luau file              -> LocalScript
  * a  *.luau file                     -> ModuleScript

Top-level placement matches default.project.json:
  ReplicatedStorage.Nexus                   <- src/shared
  ServerScriptService.Nexus                 <- src/server
  StarterPlayer.StarterPlayerScripts.Nexus  <- src/client

Double-click the resulting .rbxlx to open it directly in Roblox Studio.
"""

import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "Nexus.rbxlx")

_ref = 0


def ref() -> str:
    global _ref
    _ref += 1
    return f"RBX{_ref:08d}"


def esc(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def script_item(cls: str, name: str, source: str) -> str:
    return (
        f'<Item class="{cls}" referent="{ref()}">'
        f"<Properties>"
        f'<string name="Name">{esc(name)}</string>'
        f'<ProtectedString name="Source">{esc(source)}</ProtectedString>'
        f"</Properties>"
        f"</Item>"
    )


def build_from_file(path: str) -> str:
    fn = os.path.basename(path)
    if fn.endswith(".server.luau"):
        return script_item("Script", fn[: -len(".server.luau")], read(path))
    if fn.endswith(".client.luau"):
        return script_item("LocalScript", fn[: -len(".client.luau")], read(path))
    if fn.endswith(".luau"):
        return script_item("ModuleScript", fn[: -len(".luau")], read(path))
    return ""


def build_from_dir(path: str, name: str) -> str:
    entries = sorted(os.listdir(path))
    cls, init_file = "Folder", None
    if "init.server.luau" in entries:
        cls, init_file = "Script", "init.server.luau"
    elif "init.client.luau" in entries:
        cls, init_file = "LocalScript", "init.client.luau"
    elif "init.luau" in entries:
        cls, init_file = "ModuleScript", "init.luau"

    children = []
    for e in entries:
        if e == init_file:
            continue
        full = os.path.join(path, e)
        if os.path.isdir(full):
            children.append(build_from_dir(full, e))
        elif e.endswith(".luau"):
            children.append(build_from_file(full))

    props = f'<string name="Name">{esc(name)}</string>'
    if init_file:
        props += f'<ProtectedString name="Source">{esc(read(os.path.join(path, init_file)))}</ProtectedString>'
    return (
        f'<Item class="{cls}" referent="{ref()}">'
        f"<Properties>{props}</Properties>"
        f'{"".join(children)}'
        f"</Item>"
    )


def service(cls: str, extra_props: str = "", children_xml: str = "") -> str:
    return (
        f'<Item class="{cls}" referent="{ref()}">'
        f"<Properties>{extra_props}</Properties>"
        f"{children_xml}"
        f"</Item>"
    )


def container(cls: str, name: str, children_xml: str) -> str:
    return (
        f'<Item class="{cls}" referent="{ref()}">'
        f'<Properties><string name="Name">{esc(name)}</string></Properties>'
        f"{children_xml}"
        f"</Item>"
    )


def main() -> None:
    shared = build_from_dir(os.path.join(REPO, "src", "shared"), "Nexus")
    server = build_from_dir(os.path.join(REPO, "src", "server"), "Nexus")
    client = build_from_dir(os.path.join(REPO, "src", "client"), "Nexus")

    body = (
        service("ReplicatedStorage", "", shared)
        + service("ServerScriptService", "", server)
        + service("StarterPlayer", "", container("StarterPlayerScripts", "StarterPlayerScripts", client))
        + service("Workspace", '<bool name="StreamingEnabled">true</bool>')
        + service("Players", '<bool name="CharacterAutoLoads">false</bool>')
    )

    doc = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        '<Meta name="ExplicitAutoJoints">true</Meta>\n'
        "<External>null</External>\n"
        "<External>nil</External>\n"
        f"{body}\n"
        "</roblox>\n"
    )
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(doc)
    print(f"wrote {OUT} ({len(doc)} bytes, {_ref} instances)")


if __name__ == "__main__":
    main()
