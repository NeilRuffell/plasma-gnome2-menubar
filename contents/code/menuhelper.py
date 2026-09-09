#!/usr/bin/env python3
"""Discovery/launch helper for the Plasma GNOME-2-style menu bar.

It never stores a menu. It discovers KDE System Settings metadata and XDG
system applications from the current machine each time it is asked.
"""

from __future__ import annotations

import configparser
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Any


def emit(value: Any) -> None:
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


def bool_value(section: configparser.SectionProxy, key: str) -> bool:
    return section.get(key, "false").strip().lower() in {"1", "true", "yes"}


def integer_value(value: Any, default: int = 100) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def available_kcms() -> dict[str, str]:
    """Return KCM ids exposed by kcmshell6 and its human-readable fallback text."""
    try:
        result = subprocess.run(
            ["kcmshell6", "--list"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        return {}

    entries: dict[str, str] = {}
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line:
            continue
        match = re.match(r"^(\S+)\s+-\s+(.+)$", line)
        if not match:
            match = re.match(r"^(\S+)\s*:\s*(.+)$", line)
        if match:
            entries.setdefault(match.group(1), match.group(2).strip())
    return entries


def localized_json_string(obj: dict[str, Any], key: str) -> str:
    # KDE metadata always carries the untranslated base key. Using it also keeps
    # this helper independent of Qt/KF localization libraries.
    value = obj.get(key, "")
    return value.strip() if isinstance(value, str) else ""


def category_metadata() -> dict[str, dict[str, Any]]:
    """Read the same System Settings category desktop files that systemsettings uses."""
    categories: dict[str, dict[str, Any]] = {}

    for root in data_roots():
        directory = root / "systemsettings" / "categories"
        if not directory.is_dir():
            continue

        for path in directory.glob("*.desktop"):
            section = read_desktop_file(path)
            if section is None:
                continue

            category_id = section.get("X-KDE-System-Settings-Category", "").strip()
            if not category_id or category_id in categories:
                continue

            parent_v2 = section.get("X-KDE-System-Settings-Parent-Category-V2", "").strip()
            parent = parent_v2 or section.get(
                "X-KDE-System-Settings-Parent-Category", ""
            ).strip()

            categories[category_id] = {
                "type": "category",
                "id": category_id,
                "name": section.get("Name", category_id).strip() or category_id,
                "icon": section.get("Icon", "").strip(),
                "parent": parent,
                "weight": integer_value(section.get("X-KDE-Weight", "100")),
                "categoryModule": section.get(
                    "X-KDE-System-Settings-Category-Module", ""
                ).strip(),
                "children": [],
            }

    return categories


def metadata_json_candidates() -> list[Path]:
    """Find installed KPackage KCM metadata without scanning all of /usr/share."""
    found: list[Path] = []
    seen: set[Path] = set()

    for root in data_roots():
        for base in (root / "kpackage" / "kcms", root / "plasma" / "kcms"):
            if not base.is_dir():
                continue
            for path in base.rglob("metadata.json"):
                if path not in seen:
                    seen.add(path)
                    found.append(path)
    return found


def kcm_metadata_entries(available: dict[str, str]) -> list[dict[str, Any]]:
    """Discover System Settings KCMs from their KDE plugin metadata."""
    entries: dict[str, dict[str, Any]] = {}

    for path in metadata_json_candidates():
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            continue
        if not isinstance(raw, dict):
            continue

        plugin = raw.get("KPlugin", {})
        if not isinstance(plugin, dict):
            plugin = {}

        parent_v2 = raw.get("X-KDE-System-Settings-Parent-Category-V2", "")
        parent = parent_v2 or raw.get("X-KDE-System-Settings-Parent-Category", "")
        if not isinstance(parent, str) or not parent.strip():
            # This also excludes KInfoCenter-only KCMs.
            continue
        parent = parent.strip()

        candidates = []
        plugin_id = plugin.get("Id", "")
        if isinstance(plugin_id, str) and plugin_id.strip():
            candidates.append(plugin_id.strip())
        if path.name == "metadata.json":
            candidates.append(path.parent.name)
        else:
            candidates.append(path.stem)

        module_id = next((item for item in candidates if item in available), "")
        if not module_id:
            # A metadata entry not exposed by kcmshell6 can be platform-inapplicable.
            continue
        if module_id in entries:
            continue

        name = localized_json_string(plugin, "Name") or available[module_id]
        icon = localized_json_string(plugin, "Icon")
        entries[module_id] = {
            "type": "item",
            "kind": "kcm",
            "id": module_id,
            "name": name,
            "icon": icon or "preferences-system",
            "parent": parent,
            "weight": integer_value(raw.get("X-KDE-Weight", 100)),
        }

    # Some distributions/external KCMs still expose desktop metadata.
    desktop_dirs: list[Path] = []
    for root in data_roots():
        desktop_dirs.extend(
            (
                root / "kservices6",
                root / "applications",
                root / "plasma" / "systemsettings" / "externalmodules",
            )
        )

    for directory in desktop_dirs:
        if not directory.is_dir():
            continue
        for path in directory.rglob("*.desktop"):
            section = read_desktop_file(path)
            if section is None:
                continue

            parent_v2 = section.get(
                "X-KDE-System-Settings-Parent-Category-V2", ""
            ).strip()
            parent = parent_v2 or section.get(
                "X-KDE-System-Settings-Parent-Category", ""
            ).strip()
            if not parent:
                continue

            identifiers = [
                section.get("X-KDE-PluginInfo-Name", "").strip(),
                section.get("X-KDE-Library", "").strip(),
                path.stem,
            ]
            module_id = next((item for item in identifiers if item in available), "")

            if module_id:
                if module_id in entries:
                    continue
                entries[module_id] = {
                    "type": "item",
                    "kind": "kcm",
                    "id": module_id,
                    "name": section.get("Name", available[module_id]).strip()
                    or available[module_id],
                    "icon": section.get("Icon", "").strip() or "preferences-system",
                    "parent": parent,
                    "weight": integer_value(section.get("X-KDE-Weight", "100")),
                }
                continue

            # Match KDE's external System Settings module support.
            if section.get("Type", "") == "Application" and section.get("Exec", "").strip():
                key = f"desktop:{path}"
                if key in entries:
                    continue
                entries[key] = {
                    "type": "item",
                    "kind": "desktop",
                    "path": str(path),
                    "name": section.get("Name", path.stem).strip() or path.stem,
                    "icon": section.get("Icon", "").strip()
                    or "preferences-system",
                    "parent": parent,
                    "weight": integer_value(section.get("X-KDE-Weight", "100")),
                }

    return list(entries.values())


def preference_tree() -> list[dict[str, Any]]:
    """Build the KDE System Settings category hierarchy for the Preferences menu."""
    available = available_kcms()
    if not available:
        return []

    categories = category_metadata()
    modules = kcm_metadata_entries(available)

    # Put modules into their declared category.
    loose: list[dict[str, Any]] = []
    for module in modules:
        parent = module.pop("parent", "")
        if parent in {"rootcategory", "lost-and-found"}:
            # Landing page/lost-and-found are System Settings UI plumbing, not useful
            # entries in a classic Preferences menu.
            continue
        category = categories.get(parent)
        if category is not None:
            category["children"].append(module)
        else:
            loose.append(module)

    # Nest categories using KDE's own parent metadata.
    roots: list[dict[str, Any]] = []
    for category_id, category in categories.items():
        if category_id in {"rootcategory", "lost-and-found"}:
            continue
        parent = category.get("parent", "")
        if parent and parent in categories and parent not in {"rootcategory", "lost-and-found"}:
            categories[parent]["children"].append(category)
        elif parent not in {"rootcategory", "lost-and-found"}:
            roots.append(category)

    # If a distro has a valid System Settings KCM whose category desktop file is
    # missing, keep it reachable in a final "Other" submenu.
    if loose:
        roots.append(
            {
                "type": "category",
                "id": "other",
                "name": "Other",
                "icon": "preferences-other",
                "weight": 10000,
                "children": loose,
            }
        )

    def prune_and_sort(node: dict[str, Any]) -> bool:
        children = node.get("children", [])
        kept: list[dict[str, Any]] = []
        for child in children:
            if child.get("type") == "category":
                if prune_and_sort(child):
                    kept.append(child)
            else:
                kept.append(child)
        kept.sort(
            key=lambda item: (
                integer_value(item.get("weight", 100)),
                str(item.get("name", "")).casefold(),
            )
        )
        node["children"] = kept
        node.pop("parent", None)
        node.pop("categoryModule", None)
        return bool(kept)

    result = [node for node in roots if prune_and_sort(node)]
    result.sort(
        key=lambda item: (
            integer_value(item.get("weight", 100)),
            str(item.get("name", "")).casefold(),
        )
    )
    return result


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
        emit(preference_tree())
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
