/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * GNOME 2-style Applications / Places / System menu bar for Plasma 6.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window

import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation

    property var kcmEntries: []
    property var adminEntries: []
    property bool discoveryReady: false
    property bool applicationsDirty: true
    property bool placesDirty: true
    property bool systemDirty: true

    // Keep popup menus within the usable screen height. Plasma's Menu content is
    // a ListView; once the popup is capped, its built-in scrolling is enabled.
    readonly property real maxMenuHeight: Math.max(160, Screen.desktopAvailableHeight - 24)

    function localFilePath(url) {
        let value = String(url)
        if (value.indexOf("file://") === 0) {
            value = value.substring(7)
        }
        return decodeURIComponent(value)
    }

    readonly property string helperPath: localFilePath(Qt.resolvedUrl("../code/menuhelper.py"))

    function shellDoubleQuote(value) {
        return "\"" + String(value).replace(/\\/g, "\\\\").replace(/\"/g, "\\\"") + "\""
    }

    function helperCommand(subcommand, argument) {
        let cmd = "python3 " + shellDoubleQuote(helperPath) + " " + subcommand
        if (argument !== undefined && argument !== null) {
            cmd += " " + shellDoubleQuote(argument)
        }
        return cmd
    }

    // QML destroy() is deferred. Explicitly remove each item/menu from the Menu
    // model first so a rebuild cannot leave disabled "ghost" duplicates behind.
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

            // Defensive escape in case a future Qt Menu content type is neither.
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
        PC3.MenuItem { }
    }

    Component {
        id: separatorComponent
        PC3.MenuSeparator { }
    }

    function addSeparator(menu) {
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
                if (submenu) {
                    appendKickerModel(submenu, childModel, depth + 1)
                    menu.addMenu(submenu)
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

    function rebuildPlaces(menu) {
        clearMenu(menu)

        let firstPlace = 0
        if (computerModel.count > 0 && computerModel.labelForRow(0) === i18n("Show KRunner")) {
            firstPlace = 1
        }

        for (let row = firstPlace; row < computerModel.count; ++row) {
            const text = computerModel.labelForRow(row)
            if (!text || String(text).trim().length === 0) {
                continue
            }
            const capturedRow = row
            addActionItem(menu, text, function() {
                computerModel.trigger(capturedRow, "", null)
            }, true, modelIcon(computerModel, row))
        }

        addSeparator(menu)

        const recentMenu = createSubmenu(menu, i18n("Recent Documents"), "document-open-recent")
        if (recentMenu) {
            if (recentDocumentsModel.count === 0) {
                addActionItem(recentMenu, i18n("No Recent Documents"), null, false, "")
            } else {
                for (let row = 0; row < recentDocumentsModel.count; ++row) {
                    const text = recentDocumentsModel.labelForRow(row)
                    const capturedRow = row
                    addActionItem(recentMenu, text, function() {
                        recentDocumentsModel.trigger(capturedRow, "", null)
                    }, true, modelIcon(recentDocumentsModel, row))
                }
            }
            menu.addMenu(recentMenu)
        }

        placesDirty = false
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
                if (submenu) {
                    appendPreferenceNodes(submenu, node.children || [], depth + 1)
                    menu.addMenu(submenu)
                }
                continue
            }

            if (node.kind === "desktop") {
                const desktopPath = node.path
                addActionItem(menu, node.name, function() {
                    executable.exec(helperCommand("launch-desktop", desktopPath))
                }, true, node.icon || "preferences-system")
                continue
            }

            const moduleId = node.id
            addActionItem(menu, node.name, function() {
                executable.exec(helperCommand("launch-kcm", moduleId))
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

    function appendAdministrationSubmenu(menu) {
        const submenu = createSubmenu(
            menu,
            i18n("Administration"),
            "preferences-system-administration"
        )
        if (!submenu) {
            return
        }

        if (!discoveryReady) {
            addActionItem(submenu, i18n("Loading…"), null, false, "")
        } else if (!adminEntries || adminEntries.length === 0) {
            addActionItem(submenu, i18n("No entries found"), null, false, "")
        } else {
            for (let i = 0; i < adminEntries.length; ++i) {
                const entry = adminEntries[i]
                const desktopPath = entry.path
                addActionItem(submenu, entry.name, function() {
                    executable.exec(helperCommand("launch-desktop", desktopPath))
                }, true, entry.icon || "preferences-system-administration")
            }
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

    function refreshDiscovery() {
        let pending = 2
        function completedOne() {
            pending -= 1
            if (pending === 0) {
                discoveryReady = true
                systemDirty = true
            }
        }

        executable.exec(helperCommand("list-kcms"), function(stdout, stderr, exitCode) {
            try {
                kcmEntries = JSON.parse(stdout || "[]")
            } catch (e) {
                kcmEntries = []
            }
            completedOne()
        })

        executable.exec(helperCommand("list-admin"), function(stdout, stderr, exitCode) {
            try {
                adminEntries = JSON.parse(stdout || "[]")
            } catch (e) {
                adminEntries = []
            }
            completedOne()
        })
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
        onRefreshed: root.applicationsDirty = true
    }

    Kicker.ComputerModel {
        id: computerModel
        appletInterface: root
        systemApplications: []
        onCountChanged: root.placesDirty = true
    }

    Kicker.RecentUsageModel {
        id: recentDocumentsModel
        shownItems: Kicker.RecentUsageModel.OnlyDocs
        ordering: Kicker.RecentUsageModel.Recent
        onCountChanged: root.placesDirty = true
    }

    Kicker.SystemModel {
        id: systemActionsModel
        onCountChanged: root.systemDirty = true
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        property var callbacks: ({})

        function uniqueCommand(command) {
            let candidate = command
            while (connectedSources.indexOf(candidate) !== -1) {
                candidate += " "
            }
            return candidate
        }

        function exec(command, callback) {
            const commandId = uniqueCommand(command)
            if (callback) {
                callbacks[commandId] = callback
            }
            connectSource(commandId)
        }

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            const callback = callbacks[sourceName]
            if (callback) {
                delete callbacks[sourceName]
                callback(
                    data["stdout"] || "",
                    data["stderr"] || "",
                    data["exit code"] === undefined ? -1 : data["exit code"]
                )
            }
        }
    }

    Connections {
        target: Plasmoid.configuration
        function onShowIconsChanged() {
            root.applicationsDirty = true
            root.placesDirty = true
            root.systemDirty = true
        }
    }

    Component.onCompleted: refreshDiscovery()

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.refreshDiscovery()
    }

    fullRepresentation: Item {
        id: menuBarRoot

        implicitWidth: menuRow.implicitWidth
        implicitHeight: menuRow.implicitHeight
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight

        Row {
            id: menuRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            PC3.ToolButton {
                id: applicationsButton
                text: i18n("Applications")
                display: PC3.AbstractButton.TextOnly
                onClicked: {
                    if (root.applicationsDirty || applicationsMenu.count === 0) {
                        root.rebuildApplications(applicationsMenu)
                    }
                    applicationsMenu.popup(applicationsButton, 0, applicationsButton.height)
                }

                PC3.Menu {
                    id: applicationsMenu
                    popupType: QQC2.Popup.Window
                    height: Math.min(implicitHeight, root.maxMenuHeight)
                }
            }

            PC3.ToolButton {
                id: placesButton
                text: i18n("Places")
                display: PC3.AbstractButton.TextOnly
                onClicked: {
                    if (root.placesDirty || placesMenu.count === 0) {
                        root.rebuildPlaces(placesMenu)
                    }
                    placesMenu.popup(placesButton, 0, placesButton.height)
                }

                PC3.Menu {
                    id: placesMenu
                    popupType: QQC2.Popup.Window
                    height: Math.min(implicitHeight, root.maxMenuHeight)
                }
            }

            PC3.ToolButton {
                id: systemButton
                text: i18n("System")
                display: PC3.AbstractButton.TextOnly
                onClicked: {
                    if (root.systemDirty || systemMenu.count === 0) {
                        root.rebuildSystem(systemMenu)
                    }
                    systemMenu.popup(systemButton, 0, systemButton.height)
                }

                PC3.Menu {
                    id: systemMenu
                    popupType: QQC2.Popup.Window
                    height: Math.min(implicitHeight, root.maxMenuHeight)
                }
            }
        }
    }
}
