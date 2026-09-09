/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * GNOME 2-style Applications / Places / System menubar for Plasma 6.
 *
 * Top-level panel presentation is intentionally aligned with Plasma's Global
 * Menu applet. Local menu switching remains owned by Qt Quick Controls
 * MenuBar; do not add a parallel hover/click state machine here.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: root

    Plasmoid.constraintHints: Plasmoid.CanFillArea
    preferredRepresentation: fullRepresentation

    property var kcmEntries: []
    property bool discoveryReady: false
    property bool applicationsDirty: true
    property bool systemDirty: true

    readonly property real maxMenuHeight: Math.max(
        Kirigami.Units.gridUnit * 8,
        Screen.desktopAvailableHeight - Kirigami.Units.smallSpacing * 2
    )

    function localFilePath(url) {
        let value = String(url)
        if (value.startsWith("file://")) {
            value = value.substring(7)
        }
        return decodeURIComponent(value)
    }

    readonly property string helperPath: localFilePath(Qt.resolvedUrl("../code/menuhelper.py"))

    function shellDoubleQuote(value) {
        return "\"" + String(value)
            .replace(/\\/g, "\\\\")
            .replace(/\"/g, "\\\"") + "\""
    }

    readonly property string discoveryCommand:
        "python3 " + shellDoubleQuote(helperPath) + " list-kcms"

    function clearMenu(menu) {
        while (menu && menu.count > 0) {
            const submenu = menu.menuAt(0)
            if (submenu) {
                const removedMenu = menu.takeMenu(0)
                if (removedMenu) {
                    removedMenu.destroy()
                }
                continue
            }

            const removedItem = menu.takeItem(0)
            if (removedItem) {
                removedItem.destroy()
                continue
            }

            break
        }
    }

    function modelIcon(sourceModel, row) {
        if (!Plasmoid.configuration.showIcons || !sourceModel) {
            return ""
        }

        try {
            return sourceModel.data(sourceModel.index(row, 0), Qt.DecorationRole) || ""
        } catch (e) {
            return ""
        }
    }

    function applyIcon(target, iconValue) {
        if (!Plasmoid.configuration.showIcons || !target || !iconValue) {
            return
        }

        if (typeof iconValue === "string") {
            target.icon.name = iconValue
        } else {
            target.icon.source = iconValue
        }
    }

    Component {
        id: menuComponent

        PC3.Menu {
            popupType: QQC2.Popup.Window
            height: Math.min(implicitHeight, root.maxMenuHeight)
        }
    }

    Component {
        id: menuItemComponent

        PC3.MenuItem {}
    }

    Component {
        id: separatorComponent

        PC3.MenuSeparator {}
    }

    function addSeparator(menu) {
        if (!menu || menu.count === 0) {
            return
        }

        const separator = separatorComponent.createObject(menu)
        if (separator) {
            menu.addItem(separator)
        }
    }

    function addActionItem(menu, text, callback, enabled, iconValue) {
        const item = menuItemComponent.createObject(menu, {
            "text": text,
            "enabled": enabled === undefined ? true : enabled
        })
        if (!item) {
            return null
        }

        applyIcon(item, iconValue)

        if (callback) {
            item.clicked.connect(callback)
        }

        menu.addItem(item)
        return item
    }

    function createSubmenu(menu, title, iconValue) {
        const submenu = menuComponent.createObject(menu, {"title": title})
        if (!submenu) {
            return null
        }

        applyIcon(submenu, iconValue)
        return submenu
    }

    function appendKickerModel(menu, sourceModel, depth) {
        if (!sourceModel || depth > 8) {
            return
        }

        for (let row = 0; row < sourceModel.count; ++row) {
            const text = sourceModel.labelForRow(row)
            const childModel = sourceModel.modelForRow(row)
            const iconValue = modelIcon(sourceModel, row)

            if (childModel) {
                const submenu = createSubmenu(menu, text, iconValue)
                if (!submenu) {
                    continue
                }

                appendKickerModel(submenu, childModel, depth + 1)
                if (submenu.count > 0) {
                    menu.addMenu(submenu)
                } else {
                    submenu.destroy()
                }
            } else if (!text || String(text).trim().length === 0) {
                addSeparator(menu)
            } else {
                const capturedModel = sourceModel
                const capturedRow = row
                addActionItem(menu, text, function() {
                    capturedModel.trigger(capturedRow, "", null)
                }, true, iconValue)
            }
        }
    }

    function rebuildApplications(menu) {
        clearMenu(menu)
        appendKickerModel(menu, applicationsModel, 0)
        applicationsDirty = false
    }

    function appendPreferenceNodes(menu, nodes, depth) {
        if (!nodes || depth > 8) {
            return
        }

        for (let i = 0; i < nodes.length; ++i) {
            const node = nodes[i]

            if (node.type === "category") {
                const submenu = createSubmenu(
                    menu,
                    node.name || node.id || i18n("Other"),
                    node.icon || "preferences-system"
                )
                if (!submenu) {
                    continue
                }

                appendPreferenceNodes(submenu, node.children || [], depth + 1)
                if (submenu.count > 0) {
                    menu.addMenu(submenu)
                } else {
                    submenu.destroy()
                }
                continue
            }

            const moduleId = node.id
            addActionItem(menu, node.name || moduleId, function() {
                KCMUtils.KCMLauncher.openSystemSettings(moduleId)
            }, true, node.icon || "preferences-system")
        }
    }

    function appendPreferencesSubmenu(menu) {
        const submenu = createSubmenu(menu, i18n("Preferences"), "preferences-system")
        if (!submenu) {
            return
        }

        if (!discoveryReady) {
            addActionItem(submenu, i18n("Loading…"), null, false, "")
        } else if (!kcmEntries || kcmEntries.length === 0) {
            addActionItem(submenu, i18n("No entries found"), null, false, "")
        } else {
            appendPreferenceNodes(submenu, kcmEntries, 0)
        }

        menu.addMenu(submenu)
    }

    function findApplicationsCategoryModel(label) {
        for (let row = 0; row < applicationsModel.count; ++row) {
            const childModel = applicationsModel.modelForRow(row)
            if (childModel && applicationsModel.labelForRow(row) === label) {
                return childModel
            }
        }
        return null
    }

    function appendAdministrationSubmenu(menu) {
        const submenu = createSubmenu(
            menu,
            i18n("Administration"),
            "preferences-system-administration"
        )
        if (!submenu) {
            return
        }

        const systemApplicationsModel = findApplicationsCategoryModel(i18n("System"))
        if (systemApplicationsModel) {
            appendKickerModel(submenu, systemApplicationsModel, 0)
        }

        if (submenu.count === 0) {
            addActionItem(submenu, i18n("No entries found"), null, false, "")
        }

        menu.addMenu(submenu)
    }

    function rebuildSystem(menu) {
        clearMenu(menu)

        appendPreferencesSubmenu(menu)
        appendAdministrationSubmenu(menu)
        addSeparator(menu)

        for (let row = 0; row < systemActionsModel.count; ++row) {
            const text = systemActionsModel.labelForRow(row)
            const capturedRow = row
            addActionItem(menu, text, function() {
                systemActionsModel.trigger(capturedRow, "", null)
            }, true, modelIcon(systemActionsModel, row))
        }

        systemDirty = false
    }

    Kicker.RootModel {
        id: applicationsModel

        autoPopulate: true
        appletInterface: root
        flat: false
        sorted: true
        showSeparators: true
        showTopLevelItems: true
        showAllApps: false
        showAllAppsCategorized: true
        showRecentApps: false
        showRecentDocs: false
        showPowerSession: false

        onRefreshed: {
            root.applicationsDirty = true
            root.systemDirty = true
        }
    }

    Kicker.ComputerModel {
        id: computerModel

        appletInterface: root
        systemApplications: []
    }

    Kicker.RecentUsageModel {
        id: recentDocumentsModel

        shownItems: Kicker.RecentUsageModel.OnlyDocs
        ordering: Kicker.RecentUsageModel.Recent
    }

    Kicker.SystemModel {
        id: systemActionsModel

        onCountChanged: root.systemDirty = true
    }

    Plasma5Support.DataSource {
        id: preferenceDiscovery

        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)

            try {
                root.kcmEntries = JSON.parse(data["stdout"] || "[]")
            } catch (e) {
                root.kcmEntries = []
            }

            root.discoveryReady = true
            root.systemDirty = true
        }
    }

    Component.onCompleted: preferenceDiscovery.connectSource(discoveryCommand)

    Connections {
        target: Plasmoid.configuration

        function onShowIconsChanged() {
            root.applicationsDirty = true
            root.systemDirty = true
        }
    }

    fullRepresentation: QQC2.MenuBar {
        id: menuBar

        delegate: GlobalMenuDelegate {}

        spacing: 0
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        background: null

        LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft

        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight

        PC3.Menu {
            id: applicationsMenu

            title: i18n("Applications")
            popupType: QQC2.Popup.Window
            height: Math.min(implicitHeight, root.maxMenuHeight)

            onAboutToShow: {
                if (root.applicationsDirty || count === 0) {
                    root.rebuildApplications(applicationsMenu)
                }
            }
        }

        PC3.Menu {
            id: placesMenu

            title: i18n("Places")
            popupType: QQC2.Popup.Window
            height: Math.min(implicitHeight, root.maxMenuHeight)

            property int insertedPlaceItems: 0

            Instantiator {
                model: computerModel

                delegate: DecorationMenuItem {
                    required property int index
                    required property var model

                    readonly property int sourceRow: index
                    readonly property string rowGroup: String(model.group || "")
                    readonly property bool includeInPlaces:
                        rowGroup !== i18n("Applications")

                    visible: includeInPlaces
                    enabled: includeInPlaces && String(model.display || "").length > 0
                    text: String(model.display || "")
                    decoration: model.decoration
                    showDecoration: Plasmoid.configuration.showIcons

                    onClicked: computerModel.trigger(sourceRow, "", null)
                }

                onObjectAdded: function(index, object) {
                    if (!object.includeInPlaces) {
                        return
                    }

                    placesMenu.insertItem(placesMenu.insertedPlaceItems, object)
                    placesMenu.insertedPlaceItems += 1
                }

                onObjectRemoved: function(index, object) {
                    if (!object.includeInPlaces) {
                        return
                    }

                    placesMenu.removeItem(object)
                    placesMenu.insertedPlaceItems = Math.max(
                        0,
                        placesMenu.insertedPlaceItems - 1
                    )
                }
            }

            PC3.MenuSeparator {
                visible: placesMenu.insertedPlaceItems > 0
            }

            PC3.Menu {
                id: recentDocumentsMenu

                title: i18n("Recent Documents")
                icon.name: Plasmoid.configuration.showIcons ? "document-open-recent" : ""
                popupType: QQC2.Popup.Window
                height: Math.min(implicitHeight, root.maxMenuHeight)

                PC3.MenuItem {
                    visible: recentDocumentsModel.count === 0
                    enabled: false
                    text: i18n("No Recent Documents")
                }

                Instantiator {
                    model: recentDocumentsModel

                    delegate: DecorationMenuItem {
                        required property int index
                        required property var model

                        readonly property int sourceRow: index

                        text: String(model.display || "")
                        decoration: model.decoration
                        showDecoration: Plasmoid.configuration.showIcons

                        onClicked: recentDocumentsModel.trigger(sourceRow, "", null)
                    }

                    onObjectAdded: function(index, object) {
                        recentDocumentsMenu.insertItem(index, object)
                    }

                    onObjectRemoved: function(index, object) {
                        recentDocumentsMenu.removeItem(object)
                    }
                }
            }
        }

        PC3.Menu {
            id: systemMenu

            title: i18n("System")
            popupType: QQC2.Popup.Window
            height: Math.min(implicitHeight, root.maxMenuHeight)

            onAboutToShow: {
                if (root.systemDirty || count === 0) {
                    root.rebuildSystem(systemMenu)
                }
            }
        }
    }
}
