#!/usr/bin/env python3
"""Discover KDE System Settings modules and their category hierarchy.

The plasmoid itself owns menu interaction, application/place/session models, and
KCM launching. This helper exists only because System Settings' internal
MenuModel/KPluginMetaData discovery is compiled into the systemsettings
executable and is not exported as a QML API for external plasmoids.
"""

from __future__ import annotations

import configparser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any


def emit(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False))


def integer_value(value: Any, default: int = 100) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def data_roots() -> list[Path]:
    roots: list[Path] = []
    seen: set[Path] = set()

    def add(path: Path) -> None:
        try:
            resolved = path.expanduser().resolve()
        except OSError:
            resolved = path.expanduser()
        if resolved not in seen:
            seen.add(resolved)
            roots.append(resolved)

    add(Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")))
    for item in os.environ.get("XDG_DATA_DIRS", "").split(os.pathsep):
        if item:
            add(Path(item))

    # XDG defaults, retained even if a desktop session omitted them.
    add(Path("/usr/local/share"))
    add(Path("/usr/share"))
    return roots


def read_desktop_file(path: Path) -> configparser.SectionProxy | None:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
        return parser["Desktop Entry"] if "Desktop Entry" in parser else None
    except (OSError, UnicodeError, configparser.Error):
        return None


def available_kcms() -> dict[str, str]:
    """Use System Settings itself as the authority for usable KCM plugin IDs."""
    command = shutil.which("systemsettings")
    if not command:
        return {}

    try:
        result = subprocess.run(
            [command, "--list"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except OSError:
        return {}

    entries: dict[str, str] = {}
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line or line.endswith(":"):
            continue

        match = re.match(r"^(\S+)\s+-\s+(.+)$", line)
        if match:
            entries.setdefault(match.group(1), match.group(2).strip())

    return entries


def qtplugininfo_executable() -> str | None:
    candidates = (
        # Fedora
        shutil.which("qtplugininfo-qt6"),
        # Common distro spellings
        shutil.which("qtplugininfo6"),
        shutil.which("qplugininfo6"),
        shutil.which("qtplugininfo"),
        # Explicit fallbacks
        "/usr/bin/qtplugininfo-qt6",
        "/usr/lib64/qt6/bin/qtplugininfo",
        "/usr/lib/qt6/bin/qtplugininfo",
    )
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    return None


def qt_plugin_roots() -> list[Path]:
    roots: list[Path] = []
    seen: set[Path] = set()

    def add(path: Path) -> None:
        try:
            resolved = path.resolve()
        except OSError:
            resolved = path
        if resolved.is_dir() and resolved not in seen:
            seen.add(resolved)
            roots.append(resolved)

    for item in os.environ.get("QT_PLUGIN_PATH", "").split(os.pathsep):
        if item:
            add(Path(item))

    qtpaths = (
        shutil.which("qtpaths6")
        or shutil.which("qtpaths-qt6")
        or shutil.which("qtpaths")
    )
    if qtpaths:
        try:
            result = subprocess.run(
                [qtpaths, "--plugin-dir"],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            if result.stdout.strip():
                add(Path(result.stdout.strip()))
        except OSError:
            pass

    # Fedora/RHEL family.
    add(Path("/usr/lib64/qt6/plugins"))
    add(Path("/usr/local/lib64/qt6/plugins"))

    # Debian/Ubuntu and generic layouts.
    add(Path("/usr/lib/qt6/plugins"))
    add(Path("/usr/local/lib/qt6/plugins"))
    for candidate in Path("/usr/lib").glob("*/qt6/plugins"):
        add(candidate)
    for candidate in Path("/usr/local/lib").glob("*/qt6/plugins"):
        add(candidate)

    add(Path.home() / ".local/lib64/qt6/plugins")
    add(Path.home() / ".local/lib/qt6/plugins")
    return roots


def plugin_files() -> list[Path]:
    """Match the plugin namespaces searched by KDE System Settings."""
    namespaces = (
        Path("plasma/kcms"),
        Path("plasma/kcms/systemsettings"),
        Path("plasma/kcms/systemsettings_qwidgets"),
    )

    files: list[Path] = []
    seen: set[Path] = set()
    for root in qt_plugin_roots():
        for namespace in namespaces:
            directory = root / namespace
            if not directory.is_dir():
                continue
            for path in directory.glob("*.so"):
                try:
                    resolved = path.resolve()
                except OSError:
                    resolved = path
                if resolved not in seen:
                    seen.add(resolved)
                    files.append(resolved)
    return files


def qt_plugin_metadata(path: Path, tool: str) -> dict[str, Any] | None:
    try:
        result = subprocess.run(
            [tool, "--full-json", str(path)],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except OSError:
        return None

    if result.returncode != 0 or not result.stdout.strip():
        return None

    try:
        document = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None

    if not isinstance(document, dict):
        return None

    metadata = document.get("MetaData")
    return metadata if isinstance(metadata, dict) else None


def category_metadata() -> dict[str, dict[str, Any]]:
    categories: dict[str, dict[str, Any]] = {}

    for root in data_roots():
        directory = root / "systemsettings" / "categories"
        if not directory.is_dir():
            continue

        for path in directory.glob("*.desktop"):
            section = read_desktop_file(path)
            if section is None:
                continue

            category_id = section.get(
                "X-KDE-System-Settings-Category", ""
            ).strip()
            if not category_id or category_id in categories:
                continue

            parent = section.get(
                "X-KDE-System-Settings-Parent-Category-V2", ""
            ).strip() or section.get(
                "X-KDE-System-Settings-Parent-Category", ""
            ).strip()

            categories[category_id] = {
                "type": "category",
                "id": category_id,
                "name": section.get("Name", category_id).strip() or category_id,
                "icon": section.get("Icon", "").strip(),
                "parent": parent,
                "weight": integer_value(section.get("X-KDE-Weight", "100")),
                "children": [],
            }

    return categories


def plugin_kcms(available: dict[str, str]) -> dict[str, dict[str, Any]]:
    tool = qtplugininfo_executable()
    if not tool:
        return {}

    entries: dict[str, dict[str, Any]] = {}
    for path in plugin_files():
        raw = qt_plugin_metadata(path, tool)
        if not raw:
            continue

        plugin = raw.get("KPlugin", {})
        if not isinstance(plugin, dict):
            plugin = {}

        plugin_id = plugin.get("Id", "")
        module_id = plugin_id.strip() if isinstance(plugin_id, str) else ""
        if not module_id:
            module_id = path.stem

        # System Settings already applied authorization/platform/form-factor
        # filtering when producing --list, so use it as the source of truth.
        if available and module_id not in available:
            continue
        if module_id in entries:
            continue

        parent = raw.get("X-KDE-System-Settings-Parent-Category-V2", "")
        if not isinstance(parent, str) or not parent.strip():
            parent = raw.get("X-KDE-System-Settings-Parent-Category", "")
        parent = parent.strip() if isinstance(parent, str) else ""

        if not parent or parent in {"rootcategory", "lost-and-found"}:
            continue

        name = plugin.get("Name", "")
        icon = plugin.get("Icon", "")
        entries[module_id] = {
            "type": "item",
            "id": module_id,
            "name": name.strip() if isinstance(name, str) and name.strip()
            else available.get(module_id, module_id),
            "icon": icon.strip() if isinstance(icon, str) and icon.strip()
            else "preferences-system",
            "parent": parent,
            "weight": integer_value(raw.get("X-KDE-Weight", 100)),
        }

    return entries


def preference_tree() -> list[dict[str, Any]]:
    available = available_kcms()
    categories = category_metadata()
    entries = plugin_kcms(available)

    # If Qt's metadata dumper is unavailable, keep Preferences functional rather
    # than inventing category assignments that System Settings did not expose.
    if not entries:
        fallback_items = [
            {
                "type": "item",
                "id": module_id,
                "name": name,
                "icon": "preferences-system",
                "weight": 100,
            }
            for module_id, name in available.items()
        ]
        fallback_items.sort(key=lambda item: item["name"].casefold())
        if not fallback_items:
            return []
        return [{
            "type": "category",
            "id": "other",
            "name": "Other",
            "icon": "preferences-other",
            "weight": 10000,
            "children": fallback_items,
        }]

    loose: list[dict[str, Any]] = []

    for original in entries.values():
        module = dict(original)
        parent = str(module.pop("parent", "") or "").strip()
        category = categories.get(parent)
        if category is None:
            loose.append(module)
        else:
            category["children"].append(module)

    roots: list[dict[str, Any]] = []
    for category_id, category in categories.items():
        if category_id in {"rootcategory", "lost-and-found"}:
            continue

        parent = str(category.get("parent", "") or "").strip()
        if parent and parent in categories and parent not in {
            "rootcategory",
            "lost-and-found",
        }:
            categories[parent]["children"].append(category)
        else:
            roots.append(category)

    if loose:
        roots.append({
            "type": "category",
            "id": "other",
            "name": "Other",
            "icon": "preferences-other",
            "weight": 10000,
            "children": loose,
        })

    def prune_and_sort(node: dict[str, Any]) -> bool:
        children: list[dict[str, Any]] = []
        for child in node.get("children", []):
            if child.get("type") == "category":
                if prune_and_sort(child):
                    children.append(child)
            else:
                children.append(child)

        children.sort(
            key=lambda item: (
                integer_value(item.get("weight", 100)),
                str(item.get("name", "")).casefold(),
            )
        )
        node["children"] = children
        node.pop("parent", None)
        return bool(children)

    result = [node for node in roots if prune_and_sort(node)]
    result.sort(
        key=lambda item: (
            integer_value(item.get("weight", 100)),
            str(item.get("name", "")).casefold(),
        )
    )
    return result


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "list-kcms":
        emit(preference_tree())
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
