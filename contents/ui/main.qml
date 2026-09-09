/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * GNOME 2-style Applications / Places / System menu bar for Plasma 6.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

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
    property bool systemDirty: true

    property var applicationObjects: []
    property var placesObjects: []
    property var systemObjects: []

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

    function clearGenerated(objects) {
        while (objects.length > 0) {
            const object = objects.pop()
            if (object) {
                object.destroy()
            }
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

    function addSeparator(menu, objects) {
        const separator = separatorComponent.createObject(menu)
        if (separator) {
            menu.addItem(separator)
            objects.push(separator)
        }
    }

    function addActionItem(menu, objects, text, callback, enabled, iconValue) {
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
        objects.push(item)
        return item
    }

    function createSubmenu(menu, objects, title, iconValue) {
        const submenu = menuComponent.createObject(menu, {"title": title})
        if (!submenu) {
            return null
        }
        applyIcon(submenu, iconValue)
        objects.push(submenu)
        return submenu
    }

    function appendKickerModel(menu, sourceModel, objects, depth) {
        if (!sourceModel || depth > 8) {
            return
        }

        for (let row = 0; row < sourceModel.count; ++row) {
            const text = sourceModel.labelForRow(row)
            const childModel = sourceModel.modelForRow(row)
            const iconValue = modelIcon(sourceModel, row)

            if (childModel) {
                const submenu = createSubmenu(menu, objects, text, iconValue)
                if (submenu) {
                    appendKickerModel(submenu, childModel, objects, depth + 1)
                    menu.addMenu(submenu)
                }
            } else if (!text || String(text).trim().length === 0) {
                addSeparator(menu, objects)
            } else {
                const capturedModel = sourceModel
                const capturedRow = row
                addActionItem(menu, objects, text, function() {
                    capturedModel.trigger(capturedRow, "", null)
                }, true, iconValue)
            }
        }
    }

    function rebuildApplications(menu) {
        clearGenerated(applicationObjects)
        appendKickerModel(menu, applicationsModel, applicationObjects, 0)
        applicationsDirty = false
    }

    function rebuildPlaces(menu) {
        clearGenerated(placesObjects)

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
            addActionItem(menu, placesObjects, text, function() {
                computerModel.trigger(capturedRow, "", null)
            }, true, modelIcon(computerModel, row))
        }

        addSeparator(menu, placesObjects)

        const recentMenu = createSubmenu(menu, placesObjects, i18n("Recent Documents"), "document-open-recent")
        if (recentMenu) {
            if (recentDocumentsModel.count === 0) {
                addActionItem(recentMenu, placesObjects, i18n("No Recent Documents"), null, false, "")
            } else {
                for (let row = 0; row < recentDocumentsModel.count; ++row) {
                    const text = recentDocumentsModel.labelForRow(row)
                    const capturedRow = row
                    addActionItem(recentMenu, placesObjects, text, function() {
                        recentDocumentsModel.trigger(capturedRow, "", null)
                    }, true, modelIcon(recentDocumentsModel, row))
                }
            }
            menu.addMenu(recentMenu)
        }
    }

    function appendDiscoveredSubmenu(menu, objects, title, entries, kind) {
        const submenuIcon = kind === "kcm" ? "preferences-system" : "preferences-system-administration"
        const submenu = createSubmenu(menu, objects, title, submenuIcon)
        if (!submenu) {
            return
        }

        if (!discoveryReady) {
            addActionItem(submenu, objects, i18n("Loading…"), null, false, "")
        } else if (!entries || entries.length === 0) {
            addActionItem(submenu, objects, i18n("No entries found"), null, false, "")
        } else {
            for (let i = 0; i < entries.length; ++i) {
                const entry = entries[i]
                if (kind === "kcm") {
                    const moduleId = entry.id
                    addActionItem(submenu, objects, entry.name, function() {
                        executable.exec(helperCommand("launch-kcm", moduleId))
                    }, true, entry.icon || "preferences-system")
                } else {
                    const desktopPath = entry.path
                    addActionItem(submenu, objects, entry.name, function() {
                        executable.exec(helperCommand("launch-desktop", desktopPath))
                    }, true, entry.icon || "preferences-system-administration")
                }
            }
        }

        menu.addMenu(submenu)
    }

    function rebuildSystem(menu) {
        clearGenerated(systemObjects)

        appendDiscoveredSubmenu(menu, systemObjects, i18n("Preferences"), kcmEntries, "kcm")
        appendDiscoveredSubmenu(menu, systemObjects, i18n("Administration"), adminEntries, "admin")
        addSeparator(menu, systemObjects)

        for (let row = 0; row < systemActionsModel.count; ++row) {
            const text = systemActionsModel.labelForRow(row)
            const capturedRow = row
            addActionItem(menu, systemObjects, text, function() {
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
    }

    Kicker.RecentUsageModel {
        id: recentDocumentsModel
        shownItems: Kicker.RecentUsageModel.OnlyDocs
        ordering: Kicker.RecentUsageModel.Recent
    }

    Kicker.SystemModel {
        id: systemActionsModel
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
                }
            }

            PC3.ToolButton {
                id: placesButton
                text: i18n("Places")
                display: PC3.AbstractButton.TextOnly
                onClicked: {
                    root.rebuildPlaces(placesMenu)
                    placesMenu.popup(placesButton, 0, placesButton.height)
                }

                PC3.Menu {
                    id: placesMenu
                    popupType: QQC2.Popup.Window
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
                }
            }
        }
    }
}
