/*
    SPDX-FileCopyrightText: 2020 Carson Black <uhhadd@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Derived directly from Plasma's Global Menu applet MenuDelegate.qml.
    Keeping this delegate aligned with Global Menu is intentional.
*/

import QtQuick
import QtQuick.Controls

import org.kde.ksvg as KSvg
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

AbstractButton {
    id: controlRoot

    property bool menuIsOpen: false

    signal activated()

    hoverEnabled: true

    // This is the same front-end behavior used by Plasma's Global Menu. While
    // a native QMenu owns the pointer grab, the C++ backend's event filter also
    // forwards mouse movement over the other panel buttons.
    onHoveredChanged: if (hovered && menuIsOpen) { activated(); }
    onPressed: activated()

    enum State {
        Rest,
        Hover,
        Down
    }

    property int menuState: {
        if (down) {
            return MenuDelegate.State.Down;
        } else if (hovered && !menuIsOpen) {
            return MenuDelegate.State.Hover;
        }
        return MenuDelegate.State.Rest;
    }

    Kirigami.MnemonicData.controlType: Kirigami.MnemonicData.SecondaryControl
    Kirigami.MnemonicData.label: text

    topPadding: rest.margins.top
    leftPadding: rest.margins.left
    rightPadding: rest.margins.right
    bottomPadding: rest.margins.bottom

    Accessible.description: i18nc("@info:usagetip", "Open a menu")

    background: KSvg.FrameSvgItem {
        id: rest
        imagePath: "widgets/menubaritem"
        prefix: switch (controlRoot.menuState) {
            case MenuDelegate.State.Down: return "pressed";
            case MenuDelegate.State.Hover: return "hover";
            case MenuDelegate.State.Rest: return "normal";
        }
    }

    contentItem: PC3.Label {
        text: controlRoot.Kirigami.MnemonicData.richTextLabel
        textFormat: Text.StyledText
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: controlRoot.menuState === MenuDelegate.State.Rest
            ? Kirigami.Theme.textColor
            : Kirigami.Theme.highlightedTextColor
    }
}
