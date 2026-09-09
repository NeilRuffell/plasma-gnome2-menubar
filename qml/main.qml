/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQml

import org.kde.kcmutils as KCMUtils
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import plasma.applet.org.local.plasma.gnome2menubar

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.constraintHints: Plasmoid.CanFillArea

    property var kcmEntries: []
    property bool applicationsDirty: true
    property bool placesDirty: true
    property bool systemDirty: true

    property var actionTargets: ({})
    property var menuTokens: [[], [], []]
    property int actionSerial: 0

    function resetTargets(menuIndex) {
        const tokens = menuTokens[menuIndex]
        for (let i = 0; i < tokens.length; ++i) {
            delete actionTargets[tokens[i]]
        }
        menuTokens[menuIndex] = []
    }

    function registerTarget(menuIndex, modelObject, row) {
        const token = "model:" + menuIndex + ":" + (++actionSerial)
        actionTargets[token] = {"model": modelObject, "row": row}
        menuTokens[menuIndex].push(token)
        return token
    }

    function modelText(sourceModel, row) {
        try {
            return String(sourceModel.data(sourceModel.index(row, 0), Qt.DisplayRole) || "")
        } catch (e) {
            return ""
        }
    }

    function modelIcon(sourceModel, row) {
        try {
            return sourceModel.data(sourceModel.index(row, 0), Qt.DecorationRole)
        } catch (e) {
            return ""
        }
    }

    function appendKickerModel(topIndex, parentHandle, sourceModel, depth) {
        if (!sourceModel || depth > 8) {
            return
        }

        for (let row = 0; row < sourceModel.count; ++row) {
            const text = sourceModel.labelForRow(row)
            const childModel = sourceModel.modelForRow(row)
            const iconValue = modelIcon(sourceModel, row)

            if (childModel) {
                const submenuHandle = Plasmoid.addSubmenu(topIndex, parentHandle, text, iconValue)
                if (submenuHandle >= 0) {
                    appendKickerModel(topIndex, submenuHandle, childModel, depth + 1)
                }
            } else if (!text || String(text).trim().length === 0) {
                Plasmoid.addSeparator(topIndex, parentHandle)
            } else {
                const token = registerTarget(topIndex, sourceModel, row)
                Plasmoid.addAction(topIndex, parentHandle, text, iconValue, token, true)
            }
        }
    }

    function appendPreferenceNodes(topIndex, parentHandle, nodes, depth) {
        if (!nodes || depth > 8) {
            return
        }

        for (let i = 0; i < nodes.length; ++i) {
            const node = nodes[i]
            if (node.type === "category") {
                const submenuHandle = Plasmoid.addSubmenu(
                    topIndex,
                    parentHandle,
                    node.name || node.id || i18n("Other"),
                    node.icon || "preferences-system"
                )
                if (submenuHandle >= 0) {
                    appendPreferenceNodes(topIndex, submenuHandle, node.children || [], depth + 1)
                }
            } else {
                const moduleId = String(node.id || "")
                if (moduleId.length > 0) {
                    Plasmoid.addAction(
                        topIndex,
                        parentHandle,
                        node.name || moduleId,
                        node.icon || "preferences-system",
                        "kcm:" + moduleId,
                        true
                    )
                }
            }
        }
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

    function rebuildApplications() {
        const topIndex = 0
        resetTargets(topIndex)
        Plasmoid.clearMenu(topIndex)
        appendKickerModel(topIndex, 0, applicationsModel, 0)
        applicationsDirty = false
    }

    function rebuildPlaces() {
        const topIndex = 1
        resetTargets(topIndex)
        Plasmoid.clearMenu(topIndex)

        let addedPlaces = 0
        for (let row = 0; row < computerModel.count; ++row) {
            const text = modelText(computerModel, row)
            const iconValue = modelIcon(computerModel, row)

            // ComputerModel prepends KRunner. Its icon role is a stable model
            // value, unlike the translated visible label.
            if (!text || (typeof iconValue === "string" && iconValue === "plasma-search")) {
                continue
            }

            const token = registerTarget(topIndex, computerModel, row)
            Plasmoid.addAction(topIndex, 0, text, iconValue, token, true)
            addedPlaces += 1
        }

        if (addedPlaces > 0) {
            Plasmoid.addSeparator(topIndex, 0)
        }

        const recentHandle = Plasmoid.addSubmenu(
            topIndex,
            0,
            i18n("Recent Documents"),
            "document-open-recent"
        )

        if (recentDocumentsModel.count === 0) {
            Plasmoid.addAction(topIndex, recentHandle, i18n("No Recent Documents"), "", "", false)
        } else {
            for (let row = 0; row < recentDocumentsModel.count; ++row) {
                const text = recentDocumentsModel.labelForRow(row)
                const token = registerTarget(topIndex, recentDocumentsModel, row)
                Plasmoid.addAction(
                    topIndex,
                    recentHandle,
                    text,
                    modelIcon(recentDocumentsModel, row),
                    token,
                    true
                )
            }
        }

        placesDirty = false
    }

    function rebuildSystem() {
        const topIndex = 2
        resetTargets(topIndex)
        Plasmoid.clearMenu(topIndex)

        const preferencesHandle = Plasmoid.addSubmenu(
            topIndex,
            0,
            i18n("Preferences"),
            "preferences-system"
        )
        appendPreferenceNodes(topIndex, preferencesHandle, kcmEntries, 0)

        const administrationHandle = Plasmoid.addSubmenu(
            topIndex,
            0,
            i18n("Administration"),
            "preferences-system-administration"
        )
        const systemApplicationsModel = findApplicationsCategoryModel(i18n("System"))
        if (systemApplicationsModel) {
            appendKickerModel(topIndex, administrationHandle, systemApplicationsModel, 0)
        }

        Plasmoid.addSeparator(topIndex, 0)

        for (let row = 0; row < systemActionsModel.count; ++row) {
            const text = systemActionsModel.labelForRow(row)
            const token = registerTarget(topIndex, systemActionsModel, row)
            Plasmoid.addAction(topIndex, 0, text, modelIcon(systemActionsModel, row), token, true)
        }

        systemDirty = false
    }

    function prepareMenu(index) {
        // A currently visible source menu has had its actions moved into the
        // shared native QMenu, exactly as in Global Menu. Never rebuild it in
        // place; model changes will be picked up the next time it is opened.
        if (Plasmoid.currentIndex === index) {
            return
        }

        if (index === 0 && applicationsDirty) {
            rebuildApplications()
        } else if (index === 1 && placesDirty) {
            rebuildPlaces()
        } else if (index === 2 && systemDirty) {
            rebuildSystem()
        }
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

    Component.onCompleted: {
        Plasmoid.showIcons = Plasmoid.configuration.showIcons
        kcmEntries = Plasmoid.preferenceTree()
        systemDirty = true
    }

    Connections {
        target: Plasmoid

        function onRequestActivateIndex(index) {
            if (index < 0 || index >= buttonRepeater.count) {
                return
            }
            const button = buttonRepeater.itemAt(index)
            if (button) {
                button.activated()
            }
        }

        function onActionTriggered(actionId) {
            if (actionId.indexOf("kcm:") === 0) {
                KCMUtils.KCMLauncher.openSystemSettings(actionId.substring(4))
                return
            }

            const target = root.actionTargets[actionId]
            if (target && target.model) {
                target.model.trigger(target.row, "", null)
            }
        }
    }

    Connections {
        target: Plasmoid.configuration

        function onShowIconsChanged() {
            Plasmoid.showIcons = Plasmoid.configuration.showIcons
            root.applicationsDirty = true
            root.placesDirty = true
            root.systemDirty = true
        }
    }

    fullRepresentation: GridLayout {
        id: buttonGrid

        Layout.minimumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth

        rows: 1
        columns: 3
        rowSpacing: 0
        columnSpacing: 0

        Binding {
            target: Plasmoid
            property: "buttonGrid"
            value: buttonGrid
            restoreMode: Binding.RestoreNone
        }

        Repeater {
            id: buttonRepeater
            model: [i18n("Applications"), i18n("Places"), i18n("System")]

            MenuDelegate {
                required property int index
                required property string modelData

                readonly property int buttonIndex: index

                Layout.fillHeight: true
                text: modelData
                down: Plasmoid.currentIndex === index
                menuIsOpen: Plasmoid.currentIndex !== -1

                onActivated: {
                    root.prepareMenu(index)
                    Plasmoid.trigger(this, index)
                }
            }
        }
    }
}
