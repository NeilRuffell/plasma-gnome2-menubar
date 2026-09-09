#!/usr/bin/env python3
"""Discovery/launch helper for the Plasma GNOME-2-style menu bar.

It never stores a menu. It discovers KDE KCMs and XDG system applications
from the current machine each time it is asked.
"""

from __future__ import annotations

import configparser
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def emit(value) -> None:
    print(json.dumps(value, ensure_ascii=False))


def data_roots() -> list[Path]:
    home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    return [home, *[Path(d) for d in data_dirs if d]]


def application_dirs() -> list[Path]:
    return [root / "applications" for root in data_roots()]


def read_desktop_file(path: Path) -> configparser.SectionProxy | None:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
        if "Desktop Entry" not in parser:
            return None
        return parser["Desktop Entry"]
    except (OSError, configparser.Error, UnicodeError):
        return None


def kcm_icon_map() -> dict[str, str]:
    """Map KCM ids to theme icon names where KDE desktop metadata exposes them."""
    icons: dict[str, str] = {}
    search_dirs: list[Path] = []
    for root in data_roots():
        search_dirs.extend((root / "kservices6", root / "applications"))

    for directory in search_dirs:
        if not directory.is_dir():
            continue
        for path in directory.rglob("*.desktop"):
            section = read_desktop_file(path)
            if section is None:
                continue
            icon = section.get("Icon", "").strip()
            if not icon:
                continue

            identifiers = {
                path.stem,
                section.get("X-KDE-PluginInfo-Name", "").strip(),
                section.get("X-KDE-Library", "").strip(),
            }
            for identifier in identifiers:
                if identifier:
                    icons.setdefault(identifier, icon)

    return icons


def list_kcms() -> list[dict[str, str]]:
    try:
        result = subprocess.run(
            ["kcmshell6", "--list"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        return []

    icons = kcm_icon_map()
    entries: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line:
            continue

        # Current kcmshell6 output is normally: module_id - Human readable name
        match = re.match(r"^(\S+)\s+-\s+(.+)$", line)
        if not match:
            match = re.match(r"^(\S+)\s*:\s*(.+)$", line)
        if not match:
            continue

        module_id, name = match.group(1), match.group(2).strip()
        if module_id in seen:
            continue
        seen.add(module_id)
        entries.append(
            {
                "id": module_id,
                "name": name,
                "icon": icons.get(module_id, "preferences-system"),
            }
        )

    entries.sort(key=lambda item: item["name"].casefold())
    return entries


def bool_value(section: configparser.SectionProxy, key: str) -> bool:
    return section.get(key, "false").strip().lower() in {"1", "true", "yes"}


def list_admin_apps() -> list[dict[str, str]]:
    # XDG precedence: the first desktop file with a given relative id wins.
    desktop_files: dict[str, Path] = {}
    for directory in application_dirs():
        if not directory.is_dir():
            continue
        for path in directory.rglob("*.desktop"):
            rel = str(path.relative_to(directory)).replace(os.sep, "-")
            desktop_files.setdefault(rel, path)

    entries: list[dict[str, str]] = []
    seen_names: set[str] = set()

    for path in desktop_files.values():
        section = read_desktop_file(path)
        if section is None:
            continue

        if section.get("Type", "") != "Application":
            continue
        if bool_value(section, "Hidden") or bool_value(section, "NoDisplay"):
            continue

        categories = {c for c in section.get("Categories", "").split(";") if c}

        # GNOME 2's Administration menu was for system-management applications.
        # XDG's System category is the portable source for those installed apps.
        # Settings/KCM items are intentionally kept in Preferences instead.
        if "System" not in categories:
            continue
        if any(c.startswith("X-KDE-settings-") for c in categories):
            continue

        name = section.get("Name", "").strip()
        if not name or name in seen_names:
            continue
        seen_names.add(name)
        entries.append(
            {
                "name": name,
                "path": str(path),
                "icon": section.get("Icon", "").strip(),
            }
        )

    entries.sort(key=lambda item: item["name"].casefold())
    return entries


def launch_kcm(module_id: str) -> int:
    try:
        subprocess.Popen(
            ["kcmshell6", module_id],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return 0
    except OSError:
        return 1


def launch_desktop(path: str) -> int:
    if not Path(path).is_file():
        return 1
    try:
        subprocess.Popen(
            ["gio", "launch", path],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return 0
    except OSError:
        return 1


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        return 2

    command = argv[1]
    if command == "list-kcms":
        emit(list_kcms())
        return 0
    if command == "list-admin":
        emit(list_admin_apps())
        return 0
    if command == "launch-kcm" and len(argv) == 3:
        return launch_kcm(argv[2])
    if command == "launch-desktop" and len(argv) == 3:
        return launch_desktop(argv[2])
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
