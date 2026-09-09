# Plasma GNOME 2 Menubar

A Plasma 6 panel applet recreating the classic GNOME 2 top-left menubar:

```text
Applications   Places   System
```

The project stays KDE/Plasma-native. It does not run `mate-panel`, `gnome-panel`, keep a hand-written application list, or implement its own popup state machine.

## Architecture

Version `0.8.0` changes the applet from a pure-QML popup implementation to a compiled Plasma applet so its visible menus can use the same **QWidget/QMenu foundation and switching pattern as Plasma's Global Menu applet**.

### Menubar interaction

The native C++ backend follows `plasma-workspace/applets/appmenu/appmenuapplet.cpp`:

- a single persistent `QMenu` is used while moving between top-level headings;
- source-menu `QAction`s are moved into that visible menu and restored when it closes;
- the source menu's `menuAction()` is redirected/restored the same way Global Menu does it;
- the visible `QMenu` installs the same mouse-move event-filter bridge used by Global Menu, allowing the menu to retain the pointer grab while movement over another panel heading changes the active menu;
- the same Qt mouse-ungrab workaround used by Global Menu is retained;
- the `QMenu` is made transient to the panel window and uses the same `_breeze_menu_seamless_edges` property.

This means menu switching, outside-click dismissal, keyboard left/right navigation, pointer grabs, and dropdown appearance come from the same Qt Widgets menu machinery used by Plasma Global Menu rather than `PC3.Menu`/Qt Quick popup windows.

The panel headings use a `MenuDelegate.qml` derived directly from Plasma Global Menu's delegate and the same `widgets/menubaritem` Plasma theme asset.

### Menu data

- **Applications** — KDE Kicker `RootModel`.
- **Places** — KDE Kicker `ComputerModel`, backed by `KFilePlacesModel`.
- **Recent Documents** — KDE Kicker `RecentUsageModel`.
- **Preferences** — discovered in-process with KDE's `KPluginMetaData` and installed `systemsettings/categories` files, following System Settings' platform/form-factor and `KAuthorized` filtering.
- **Administration** — the System application subtree from the Kicker application hierarchy.
- **Session actions** — KDE Kicker `SystemModel`.

KCMs are launched with KDE Frameworks' `org.kde.kcmutils.KCMLauncher` API. There is no Python helper and no `qtplugininfo` dependency in v0.8.0.

## Fedora build requirements

```bash
sudo dnf install cmake ninja-build extra-cmake-modules \
    libplasma-devel kf6-kconfig-devel kf6-kcoreaddons-devel \
    qt6-qtbase-devel qt6-qtdeclarative-devel
```

## Build

```bash
bash build.sh
```

## Install

The native applet is installed through CMake rather than a `.plasmoid` ZIP:

```bash
sudo cmake --install build
```

If an older pure-QML development copy exists in your user profile, remove that copy first so it cannot shadow the compiled system applet:

```bash
rm -rf ~/.local/share/plasma/plasmoids/org.local.plasma.gnome2menubar
```

Then restart Plasma Shell and add **Applications Places System** from **Add Widgets** if necessary.

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

## License

GPL-2.0-or-later.
