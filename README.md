# Plasma GNOME 2 Menubar

A Plasma 6 panel widget that recreates the classic GNOME 2 top-left menu bar:

```text
Applications   Places   System
```

The widget stays KDE/Plasma-native. It does **not** run `mate-panel`, `gnome-panel`, or maintain a hand-written list of installed applications.

## Current status

Early Plasma 6 implementation (`0.1.0`). Applications, Places, Recent Documents, KDE settings modules, system/admin applications, and session actions are discovered dynamically from the current Plasma system.

## Dynamic data sources

- **Applications** — KDE Kicker `RootModel`, the same application-menu infrastructure used by Plasma launchers.
- **Places** — KDE Kicker `ComputerModel`, backed by KDE's `KFilePlacesModel` for bookmarks, devices, and locations.
- **Recent Documents** — KDE Kicker `RecentUsageModel`.
- **Preferences** — detected from installed KDE KCM modules using `kcmshell6 --list`.
- **Administration** — detected from installed XDG `.desktop` applications in the `System` category.
- **Session actions** — KDE Kicker `SystemModel`, exposing the actions Plasma reports as valid, such as Lock, Log Out, Switch User, Suspend, Hibernate, Restart, and Shut Down.

## Requirements

- KDE Plasma 6
- `python3`
- `kcmshell6`
- `gio`
- `zip` (to build the `.plasmoid` archive)
- Plasma's Kicker QML module

The widget intentionally uses Plasma's private Kicker QML API because Plasma's own Application Menu and Kickoff use those models as well.

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

## Design goal

The target is the classic GNOME 2 / Ubuntu-era panel behavior while retaining Plasma as the desktop shell:

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
├── Administration
├──────────────
└── Plasma session/power actions
```

No application/category list is stored in the widget itself.

## License

GPL-2.0-or-later.
