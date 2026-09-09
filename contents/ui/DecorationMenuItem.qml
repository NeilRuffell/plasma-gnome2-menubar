/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Plasma MenuItem adapter for model decorations that are QIcon/QVariant values.
 * KFilePlacesModel exposes Qt.DecorationRole as QIcon; Kirigami.Icon accepts
 * that value directly, while QQuickIcon's name/source properties do not.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

PC3.MenuItem {
    id: control

    property var decoration
    property bool showDecoration: true

    contentItem: RowLayout {
        Item {
            Layout.preferredWidth:
                (control.ListView.view && control.ListView.view.hasCheckables)
                || control.checkable
                ? control.indicator.width
                : Kirigami.Units.smallSpacing
        }

        Kirigami.Icon {
            visible: control.showDecoration
            source: control.showDecoration ? control.decoration : ""

            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: Math.max(
                label.height,
                Kirigami.Units.iconSizes.small
            )
            Layout.preferredWidth: control.showDecoration
                ? Layout.preferredHeight
                : 0
        }

        PC3.Label {
            id: label

            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true

            text: control.Kirigami.MnemonicData.richTextLabel
            textFormat: Text.StyledText
            font: control.font
            elide: Text.ElideRight
            visible: control.text.length > 0
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }
    }
}
