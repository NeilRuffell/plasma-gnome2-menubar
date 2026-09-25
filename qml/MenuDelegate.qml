/*
 * SPDX-FileCopyrightText: 2020 Carson Black <uhhadd@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls

import org.kde.ksvg as KSvg
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

AbstractButton {
    id: controlRoot

    property bool menuIsOpen: false
    property string leadingIcon: ""

    signal activated()

    // QMenu opens on press, so we'll replicate that here
    hoverEnabled: true

    // This will trigger even if hoverEnabled has just became true and the
    // mouse cursor is already hovering.
    //
    // In practice, this never works, at least on X11: when menuIsOpen the
    // hover event would not be delivered. Instead we rely on
    // plasmoid.requestActivateIndex signal to filter
    // QEvent::MouseMove events and tell us when to change the index.
    onHoveredChanged: if (hovered && menuIsOpen) { activated(); }

    // You don't actually have to "close" the menu via click/pressed handlers.
    // Instead, the menu will be closed automatically, as by any
    // other "outside of the menu" click event.
    onPressed: activated()

    enum State {
        Rest,
        Hover,
        Down
    }

    property int menuState: {
        // can't trust hovered state while QMenu is grabbing mouse pointer.
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

    contentItem: Item {
        implicitWidth: menuLabel.implicitWidth
            + (menuIcon.visible ? menuIcon.implicitWidth + Kirigami.Units.smallSpacing : 0)
        implicitHeight: menuLabel.implicitHeight

        Kirigami.Icon {
            id: menuIcon
            visible: controlRoot.leadingIcon.length > 0
            source: controlRoot.leadingIcon
            width: visible ? Kirigami.Units.iconSizes.smallMedium : 0
            height: width
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        PC3.Label {
            id: menuLabel
            anchors.left: menuIcon.visible ? menuIcon.right : parent.left
            anchors.leftMargin: menuIcon.visible ? Kirigami.Units.smallSpacing : 0
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            text: controlRoot.Kirigami.MnemonicData.richTextLabel
            textFormat: Text.StyledText
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: controlRoot.menuState === MenuDelegate.State.Rest ? Kirigami.Theme.textColor : Kirigami.Theme.highlightedTextColor
        }
    }
}
