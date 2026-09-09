/*
    SPDX-FileCopyrightText: 2020 Carson Black <uhhadd@gmail.com>
    SPDX-FileCopyrightText: 2026 Neil Ruffell

    SPDX-License-Identifier: GPL-2.0-or-later

    Panel menubar delegate derived from Plasma's Global Menu MenuDelegate.qml.
    The visual implementation intentionally stays aligned with the Plasma 6.6
    appmenu widget. The base type is MenuBarItem so Qt Quick Controls owns the
    local-menu interaction semantics.
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.ksvg as KSvg
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

QQC2.MenuBarItem {
    id: controlRoot

    enum State {
        Rest,
        Hover,
        Down
    }

    readonly property int menuState: {
        if (menu && menu.visible) {
            return GlobalMenuDelegate.State.Down
        }
        if (hovered || highlighted) {
            return GlobalMenuDelegate.State.Hover
        }
        return GlobalMenuDelegate.State.Rest
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
        case GlobalMenuDelegate.State.Down:
            return "pressed"
        case GlobalMenuDelegate.State.Hover:
            return "hover"
        case GlobalMenuDelegate.State.Rest:
            return "normal"
        }
    }

    contentItem: PC3.Label {
        text: controlRoot.Kirigami.MnemonicData.richTextLabel
        textFormat: Text.StyledText
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: controlRoot.menuState === GlobalMenuDelegate.State.Rest
            ? Kirigami.Theme.textColor
            : Kirigami.Theme.highlightedTextColor
    }
}
