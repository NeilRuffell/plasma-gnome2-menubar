# Plasma GNOME 2 Menubar

A Plasma 6 panel widget that recreates the classic GNOME 2 top-left menu bar:

```text
Applications   Places   System
```

The widget stays KDE/Plasma-native. It does **not** run `mate-panel`, `gnome-panel`, or maintain a hand-written application list.

## Architecture

Version `0.8.0` aligns the panel-side implementation with Plasma's own **Global Menu** applet wherever that implementation is reusable for local menus.

### Top-level menubar

- The three headings are a Qt Quick Controls `MenuBar`, so local menu ownership, keyboard handling, press behavior, and menu switching remain in Qt rather than in a plasmoid-specific timer/state machine.
- The `MenuBarItem` delegate is derived directly from Plasma 6.6's Global Menu `MenuDelegate.qml` and uses the same Plasma theme asset: `widgets/menubaritem`.
- Rest, hover, pressed visuals, padding, mnemonic rendering, label colors, and zero-spacing panel layout are intentionally kept aligned with Global Menu.
- The Global Menu applet's C++ `AppMenuApplet` transport layer is **not** copied. That backend exists to manipulate another application's exported `QAction/QMenu` tree over the appmenu protocol, including QMenu/X11 mouse-grab workarounds. This widget owns its menus locally, so importing that transport layer would add a binary backend and dependencies without providing useful functionality.

### Menu data

- **Applications** — KDE Kicker `RootModel`, the same application hierarchy used by Plasma launchers.
- **Places** — KDE Kicker `ComputerModel`, backed by `KFilePlacesModel` for bookmarks, devices, and locations.
- **Recent Documents** — KDE Kicker `RecentUsageModel`.
- **Preferences** — KDE System Settings' available-module list, compiled KCM plugin metadata, and installed `systemsettings/categories` hierarchy.
- **Administration** — the live **System** subtree from the same Kicker application model used by Applications.
- **Session actions** — KDE Kicker `SystemModel` for the actions Plasma reports as valid, such as Lock, Log Out, Switch User, Suspend, Hibernate, Restart, and Shut Down.

KCMs are launched through KDE Frameworks' native `org.kde.kcmutils.KCMLauncher` QML API.

`KFilePlacesModel` exposes its decoration role as `QIcon`. `DecorationMenuItem.qml` follows KDE Kickoff's approach and feeds that decoration directly to `Kirigami.Icon.source`, preserving the actual Places icons without guessing icon names.

## Dependencies

Runtime:

- KDE Plasma 6
- KDE KCMUtils QML module
- Plasma Kicker QML module
- `python3`
- `systemsettings`
- Qt 6 `qtplugininfo` for categorized Preferences metadata

Fedora:

```bash
sudo dnf install qt6-qttools-devel
```

The helper recognizes Fedora's `qtplugininfo-qt6` and `/usr/lib64/qt6` layout.

Debian/Ubuntu-family systems commonly provide the equivalent tool through `qt6-tools-dev-tools`.

If plugin metadata cannot be read, Preferences remains usable but unmatched modules fall back to **Other** rather than receiving invented category assignments.

Build-only:

- `zip`

## Build

```bash
bash build.sh
```

This creates:

```text
dist/gnome2-menubar-plasma6.plasmoid
```

## Install

After building:

```bash
kpackagetool6 --type Plasma/Applet --install dist/gnome2-menubar-plasma6.plasmoid
```

Then enter Plasma **Edit Mode**, choose **Add Widgets**, search for **Applications Places System**, and add it to the panel.

For an existing development installation:

```bash
kpackagetool6 --type Plasma/Applet --upgrade dist/gnome2-menubar-plasma6.plasmoid
```

## Remove

```bash
kpackagetool6 --type Plasma/Applet --remove org.local.plasma.gnome2menubar
```

## Target layout

```text
Applications
├── Accessories
├── Graphics
├── Internet
├── Office
└── ...

Places
├── KDE places/bookmarks
├── devices/network locations
└── Recent Documents

System
├── Preferences
│   ├── Appearance & Style
│   ├── Workspace
│   ├── Personalization
│   ├── Apps & Windows
│   ├── Security & Privacy
│   ├── Network
│   ├── Input & Output
│   └── System
├── Administration
├──────────────
└── Plasma session/power actions
```

No application/category list is stored in the widget itself.

## License

GPL-2.0-or-later.
