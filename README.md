# Plasma GNOME 2 Menubar

A Plasma 6 panel applet recreating the classic GNOME 2 top-left menubar:

```text
Applications   Places   System
```

The project stays KDE/Plasma-native. It does not run `mate-panel`, `gnome-panel`, maintain a hand-written application list, or implement a second popup/menu framework.

## Architecture

Version `0.9.2` is a native Plasma applet and deliberately follows Plasma's own **Global Menu** implementation for top-level menu presentation and switching.

### Menubar interaction and dropdowns

The C++ backend follows `plasma-workspace/applets/appmenu/appmenuapplet.cpp`:

- the visible dropdown is a real Qt Widgets **`QMenu`**, the same menu foundation used by Plasma Global Menu;
- a single persistent visible `QMenu` remains alive while the pointer moves between **Applications / Places / System**;
- each heading has a source `QMenu`; its `QAction`s are transferred into the persistent visible menu when that heading becomes active and restored when switching or closing;
- when another heading becomes active, the existing visible `QMenu` is **moved and repopulated**, not closed and replaced by a second popup;
- the visible `QMenu` installs the same mouse-move event-filter bridge used by Global Menu, because the native menu owns the pointer grab while open;
- source menus stay populated while inactive, so hover switching performs no menu-tree construction in the activation path;
- while a menu is open, the applet uses Plasma Global Menu's `NeedsAttentionStatus` host state;
- the same mouse-ungrab workaround, transient-parent handling, screen-boundary clamping, and `_breeze_menu_seamless_edges` property used by Global Menu are retained;
- left/right keyboard movement uses the same active-index bridge.

The panel headings use `qml/MenuDelegate.qml`, derived directly from Plasma Global Menu's delegate and the same `widgets/menubaritem` Plasma theme asset. The GridLayout also follows the Global Menu layout: zero spacing, RTL mirroring, panel-orientation flow, and the same zero-size filler item.

There is no `PC3.Menu`, Qt Quick `MenuBar`, custom hover timer, or alternate popup state machine in the active implementation.

Qt Widgets treats `&` in `QAction`/`QMenu` text as a mnemonic marker. KDE model labels are display strings, so literal ampersands are escaped when crossing into the native menu layer; labels such as `Input & Output`, `Appearance & Style`, and `Mouse & Touchpad` therefore display unchanged.

### Menu data

- **Applications** — KDE Kicker `RootModel`.
- **Places** — KDE Kicker `ComputerModel`, backed by `KFilePlacesModel`; model roles distinguish actual places from ComputerModel's non-place entries.
- **Recent Documents** — KDE Kicker `RecentUsageModel`; visible filenames come from the model's `Qt.DisplayRole`.
- **Preferences** — discovered in-process with KDE `KPluginMetaData`, KConfig, `KAuthorized`, runtime-platform/form-factor filtering, and the installed System Settings category metadata. Visible module labels come from KDE metadata display names; raw KCM plugin IDs are never shown as labels.
- **Administration** — the live System subtree from the Kicker application hierarchy.
- **Session actions** — KDE Kicker `SystemModel`.

KCMs are launched with KDE Frameworks' `org.kde.kcmutils.KCMLauncher` API.

There is **no Python helper, `qtplugininfo`, distro-specific Qt path probing, or sidecar process**.

## Fedora build requirements

Fedora provides the required Plasma and KDE development packages directly:

```bash
sudo dnf install cmake ninja-build gcc-c++ extra-cmake-modules \
    libplasma-devel kf6-kconfig-devel kf6-kcoreaddons-devel
```

`libplasma-devel` pulls the required Qt 6 base/declarative development dependencies.

## Build

```bash
bash build.sh
```

The build directory is `./build`.

## Install / update

This is a compiled Plasma applet, so install it through CMake rather than `kpackagetool6` or a `.plasmoid` ZIP:

```bash
sudo cmake --install build
```

### Important when upgrading from versions 0.8.x and earlier

Older versions were installed as a user KPackage under the same plugin ID. A user-local copy shadows the compiled system applet, so remove the old package directory after installing 0.9.x:

```bash
rm -rf ~/.local/share/plasma/plasmoids/org.local.plasma.gnome2menubar
```

Then restart Plasma Shell:

```bash
plasmashell --replace &
```

Existing panel configuration uses the same plugin ID (`org.local.plasma.gnome2menubar`), so Plasma can load the native implementation for the existing widget instance once the old user-local package is gone.

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
