#!/usr/bin/env python3
"""Discovery/launch helper for the Plasma GNOME-2-style menubar.

Applications/Places/session actions are handled directly by Plasma QML models.
This helper discovers KDE System Settings modules and XDG administration apps.
"""

from __future__ import annotations

import configparser
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
from typing import Any


def emit(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False))


def data_roots() -> list[Path]:
    home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    data_dirs = os.environ.get(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share"
    ).split(":")
    return [home, *[Path(item) for item in data_dirs if item]]


def application_dirs() -> list[Path]:
    return [root / "applications" for root in data_roots()]


def read_desktop_file(path: Path) -> configparser.SectionProxy | None:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
        return parser["Desktop Entry"] if "Desktop Entry" in parser else None
    except (OSError, UnicodeError, configparser.Error):
        return None


def bool_value(section: configparser.SectionProxy, key: str) -> bool:
    return section.get(key, "false").strip().lower() in {
        "1", "true", "yes"
    }


def integer_value(value: Any, default: int = 100) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def qtplugininfo_executable() -> str | None:
    candidates = (
        shutil.which("qtplugininfo6"),
        shutil.which("qplugininfo6"),
        shutil.which("qtplugininfo"),
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

    qtpaths = shutil.which("qtpaths6") or shutil.which("qtpaths")
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

    for base in (
        Path("/usr/lib"),
        Path("/usr/local/lib"),
        Path.home() / ".local/lib",
    ):
        add(base / "qt6/plugins")
        if base.is_dir():
            for candidate in base.glob("*/qt6/plugins"):
                add(candidate)

    return roots


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


def localized_json_string(obj: dict[str, Any], key: str) -> str:
    value = obj.get(key, "")
    return value.strip() if isinstance(value, str) else ""


def category_metadata() -> dict[str, dict[str, Any]]:
    """Read KDE System Settings' installed category definitions."""
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
                "name": section.get("Name", category_id).strip()
                or category_id,
                "icon": section.get("Icon", "").strip(),
                "parent": parent,
                "weight": integer_value(
                    section.get("X-KDE-Weight", "100")
                ),
                "children": [],
            }

    return categories


def plugin_kcm_entries() -> dict[str, dict[str, Any]]:
    """Read KCM metadata directly from KDE's System Settings plugin namespaces."""
    entries: dict[str, dict[str, Any]] = {}
    tool = qtplugininfo_executable()
    if not tool:
        return entries

    namespaces = (
        Path("plasma/kcms/systemsettings"),
        Path("plasma/kcms/systemsettings_qwidgets"),
        Path("plasma/kcms"),
    )

    for plugin_root in qt_plugin_roots():
        for namespace in namespaces:
            directory = plugin_root / namespace
            if not directory.is_dir():
                continue

            for path in directory.glob("*.so"):
                raw = qt_plugin_metadata(path, tool)
                if not raw:
                    continue

                plugin = raw.get("KPlugin", {})
                if not isinstance(plugin, dict):
                    plugin = {}

                explicit_id = localized_json_string(plugin, "Id")
                module_id = explicit_id or path.stem
                if not module_id or module_id in entries:
                    continue

                parent = raw.get(
                    "X-KDE-System-Settings-Parent-Category-V2", ""
                )
                if not isinstance(parent, str) or not parent.strip():
                    parent = raw.get(
                        "X-KDE-System-Settings-Parent-Category", ""
                    )
                parent = parent.strip() if isinstance(parent, str) else ""

                if not parent or parent in {"rootcategory", "lost-and-found"}:
                    continue

                entries[module_id] = {
                    "type": "item",
                    "kind": "kcm",
                    "id": module_id,
                    "name": localized_json_string(plugin, "Name")
                    or module_id,
                    "icon": localized_json_string(plugin, "Icon")
                    or "preferences-system",
                    "parent": parent,
                    "weight": integer_value(
                        raw.get("X-KDE-Weight", 100)
                    ),
                }

    return entries


def desktop_kcm_entries(
    existing: dict[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """Fallback to generated KCM .desktop launchers.

    Plasma/KCMUtils installs these even though they generally do not contain
    category metadata. Unknown-category entries are retained and later placed
    in an automatic Other submenu rather than silently disappearing.
    """
    entries = dict(existing)

    desktop_files: dict[str, Path] = {}
    for directory in application_dirs():
        if not directory.is_dir():
            continue
        for path in directory.glob("*.desktop"):
            desktop_files.setdefault(path.name, path)

    for path in desktop_files.values():
        section = read_desktop_file(path)
        if section is None:
            continue

        exec_line = section.get("Exec", "").strip()
        alias = section.get("X-KDE-AliasFor", "").strip()
        looks_like_kcm = (
            path.stem.startswith("kcm_")
            or alias == "systemsettings"
            or exec_line.startswith("systemsettings ")
            or exec_line.startswith("kcmshell6 ")
        )
        if not looks_like_kcm:
            continue

        module_id = path.stem
        if exec_line:
            try:
                argv = shlex.split(exec_line)
            except ValueError:
                argv = []
            if argv:
                command_name = Path(argv[0]).name
                if command_name in {"systemsettings", "kcmshell6"}:
                    for arg in argv[1:]:
                        if not arg.startswith("-"):
                            module_id = arg
                            break

        if not module_id or module_id in entries:
            continue

        parent = section.get(
            "X-KDE-System-Settings-Parent-Category-V2", ""
        ).strip() or section.get(
            "X-KDE-System-Settings-Parent-Category", ""
        ).strip()

        entries[module_id] = {
            "type": "item",
            "kind": "kcm",
            "id": module_id,
            "name": section.get("Name", module_id).strip() or module_id,
            "icon": section.get("Icon", "").strip()
            or "preferences-system",
            "parent": parent,
            "weight": integer_value(
                section.get("X-KDE-Weight", "100")
            ),
        }

    return entries


def preference_tree() -> list[dict[str, Any]]:
    """Build a live System Settings category tree."""
    categories = category_metadata()
    modules = list(
        desktop_kcm_entries(plugin_kcm_entries()).values()
    )

    if not modules:
        return []

    loose: list[dict[str, Any]] = []
    for module in modules:
        parent = module.pop("parent", "")
        category = categories.get(parent)
        if category is not None:
            category["children"].append(module)
        else:
            loose.append(module)

    roots: list[dict[str, Any]] = []
    for category_id, category in categories.items():
        if category_id in {"rootcategory", "lost-and-found"}:
            continue

        parent = category.get("parent", "")
        if (
            parent
            and parent in categories
            and parent not in {"rootcategory", "lost-and-found"}
        ):
            categories[parent]["children"].append(category)
        else:
            roots.append(category)

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
        kept: list[dict[str, Any]] = []
        for child in node.get("children", []):
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
    desktop_files: dict[str, Path] = {}
    for directory in application_dirs():
        if not directory.is_dir():
            continue
        for path in directory.rglob("*.desktop"):
            relative_id = str(
                path.relative_to(directory)
            ).replace(os.sep, "-")
            desktop_files.setdefault(relative_id, path)

    entries: list[dict[str, str]] = []
    seen_names: set[str] = set()

    for path in desktop_files.values():
        section = read_desktop_file(path)
        if section is None:
            continue
        if section.get("Type", "") != "Application":
            continue
        if bool_value(section, "Hidden") or bool_value(
            section, "NoDisplay"
        ):
            continue

        categories = {
            item
            for item in section.get("Categories", "").split(";")
            if item
        }
        if "System" not in categories:
            continue
        if any(
            item.startswith("X-KDE-settings-")
            for item in categories
        ):
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
    command = shutil.which("kcmshell6")
    if command:
        try:
            subprocess.Popen(
                [command, module_id],
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return 0
        except OSError:
            pass

    command = shutil.which("systemsettings")
    if command:
        try:
            subprocess.Popen(
                [command, module_id],
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return 0
        except OSError:
            pass
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
