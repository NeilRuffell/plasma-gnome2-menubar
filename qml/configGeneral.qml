import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_showIcons: showIcons.checked
    property alias cfg_showDistributionIcon: showDistributionIcon.checked

    QQC2.CheckBox {
        id: showIcons
        text: i18n("Show icons beside menu items")
    }

    QQC2.CheckBox {
        id: showDistributionIcon
        text: i18n("Show distribution icon before Applications")
    }
}
