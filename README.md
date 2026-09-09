# Plasma GNOME 2 Menubar

A Plasma 6 panel widget that recreates the classic GNOME 2 top-left menu bar:

```text
Applications   Places   System
```

The widget stays KDE/Plasma-native. It does **not** run `mate-panel`, `gnome-panel`, or maintain a hand-written application list.

## Architecture

Version `0.7.0` removes the widget's custom top-level menu state machine. The three headings are a real **Qt Quick Controls `MenuBar`**, so click, hover switching, keyboard focus, menu ownership, and popup transitions use Qt's standard menubar implementation rather than plasmoid-specific timers or hover logic.

Menu contents use KDE/Plasma models:

- **Applications** — KDE Kicker `RootModel`, the same application hierarchy used by Plasma launchers.
- **Places** — KDE Kicker `ComputerModel`, backed by `KFilePlacesModel` for bookmarks, devices, and locations.
- **Recent Documents** — KDE Kicker `RecentUsageModel`.
- **Preferences** — KDE System Settings' own available-module list, compiled KCM plugin metadata, and installed `systemsettings/categories` hierarchy.
- **Administration** — the live **System** subtree from the same Kicker application model used by Applications; no second desktop-file scanner or launcher is maintained.
- **Session actions** — KDE Kicker `SystemModel` for the actions Plasma reports as valid, such as Lock, Log Out, Switch User, Suspend, Hibernate, Restart, and Shut Down.

KCMs are launched through KDE Frameworks' `org.kde.kcmutils.KCMLauncher` QML API.

`KFilePlacesModel` exposes its decoration role as `QIcon`. `DecorationMenuItem.qml` is a small adapter that follows KDE Kickoff's approach and feeds that value directly to `Kirigami.Icon.source`, preserving the actual Places icons without guessing icon names.

## Dependencies

Runtime:

- KDE Plasma 6
- KDE KCMUtils QML module (normally installed with Plasma/System Settings)
- Plasma Kicker QML module
- `python3`
- `systemsettings`
- Qt 6 `qtplugininfo` for categorized Preferences metadata

Fedora:

```bash
sudo dnf install qt6-qttools-devel
```

Fedora provides the tool as `qtplugininfo-qt6`.

Debian/Ubuntu-family systems commonly provide it through `qt6-tools-dev-tools`.

If `qtplugininfo` is unavailable, Preferences remains usable but falls back to a single **Other** category rather than inventing category assignments.

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
