/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * GNOME 2-style Applications / Places / System menu bar for Plasma 6.
 * Applications, Places and session actions come from KDE's live Kicker models.
 * Preferences and Administration are discovered from the current machine.
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

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

    Component {
        id: menuComponent
        PC3.Menu { }
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

    function addActionItem(menu, objects, text, callback, enabled) {
        const item = menuItemComponent.createObject(menu, {
            "text": text,
            "enabled": enabled === undefined ? true : enabled
        })
        if (!item) {
            return null
        }
        if (callback) {
            item.clicked.connect(callback)
        }
        menu.addItem(item)
        objects.push(item)
        return item
    }

    function appendKickerModel(menu, sourceModel, objects, depth) {
        if (!sourceModel || depth > 8) {
            return
        }

        for (let row = 0; row < sourceModel.count; ++row) {
            const text = sourceModel.labelForRow(row)
            const childModel = sourceModel.modelForRow(row)

            if (childModel) {
                const submenu = menuComponent.createObject(menu, {"title": text})
                if (submenu) {
                    objects.push(submenu)
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
                })
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
            })
        }

        addSeparator(menu, placesObjects)

        const recentMenu = menuComponent.createObject(menu, {"title": i18n("Recent Documents")})
        if (recentMenu) {
            placesObjects.push(recentMenu)
            if (recentDocumentsModel.count === 0) {
                addActionItem(recentMenu, placesObjects, i18n("No Recent Documents"), null, false)
            } else {
                for (let row = 0; row < recentDocumentsModel.count; ++row) {
                    const text = recentDocumentsModel.labelForRow(row)
                    const capturedRow = row
                    addActionItem(recentMenu, placesObjects, text, function() {
                        recentDocumentsModel.trigger(capturedRow, "", null)
                    })
                }
            }
            menu.addMenu(recentMenu)
        }
    }

    function appendDiscoveredSubmenu(menu, objects, title, entries, kind) {
        const submenu = menuComponent.createObject(menu, {"title": title})
        if (!submenu) {
            return
        }
        objects.push(submenu)

        if (!discoveryReady) {
            addActionItem(submenu, objects, i18n("Loading…"), null, false)
        } else if (!entries || entries.length === 0) {
            addActionItem(submenu, objects, i18n("No entries found"), null, false)
        } else {
            for (let i = 0; i < entries.length; ++i) {
                const entry = entries[i]
                if (kind === "kcm") {
                    const moduleId = entry.id
                    addActionItem(submenu, objects, entry.name, function() {
                        executable.exec(helperCommand("launch-kcm", moduleId))
                    })
                } else {
                    const desktopPath = entry.path
                    addActionItem(submenu, objects, entry.name, function() {
                        executable.exec(helperCommand("launch-desktop", desktopPath))
                    })
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
            })
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

    Component.onCompleted: refreshDiscovery()

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.refreshDiscovery()
    }

    compactRepresentation: Item {
        id: compactRoot

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
                    applicationsMenu.open()
                }

                PC3.Menu {
                    id: applicationsMenu
                    x: 0
                    y: applicationsButton.height
                }
            }

            PC3.ToolButton {
                id: placesButton
                text: i18n("Places")
                display: PC3.AbstractButton.TextOnly

                onClicked: {
                    root.rebuildPlaces(placesMenu)
                    placesMenu.open()
                }

                PC3.Menu {
                    id: placesMenu
                    x: 0
                    y: placesButton.height
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
                    systemMenu.open()
                }

                PC3.Menu {
                    id: systemMenu
                    x: 0
                    y: systemButton.height
                }
            }
        }
    }
}
