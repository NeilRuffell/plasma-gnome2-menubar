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

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Kicker::GroupRole from plasma-workspace/applets/kicker/actionlist.h.
    // ComputerModel explicitly assigns its non-place rows to the translated
    // "Applications" group; KFilePlaces rows forward their real Places group.
    readonly property int kickerGroupRole: Qt.UserRole + 2

    preferredRepresentation: fullRepresentation
    Plasmoid.constraintHints: Plasmoid.CanFillArea

    property var kcmEntries: []
    property bool applicationsDirty: true
    property bool placesDirty: true
    property bool systemDirty: true

    // QAction callbacks stay in QML because the Kicker models are QML-facing
    // Plasma models. The native backend only owns QMenu presentation/switching.
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
                        node.name,
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
            const index = computerModel.index(row, 0)
            const groupName = String(computerModel.data(index, root.kickerGroupRole) || "")
            if (groupName === i18n("Applications")) {
                continue
            }

            const text = String(computerModel.data(index, Qt.DisplayRole) || "")
            if (!text) {
                continue
            }

            const token = registerTarget(topIndex, computerModel, row)
            Plasmoid.addAction(
                topIndex,
                0,
                text,
                computerModel.data(index, Qt.DecorationRole),
                token,
                true
            )
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
                // RecentUsageModel is a ForwardingModel whose source is not an
                // AbstractModel, so labelForRow() is empty. KDE exposes the
                // document filename through Qt.DisplayRole instead.
                const text = modelText(recentDocumentsModel, row)
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
        // While a top menu is visible, its QAction set lives temporarily in
        // the shared visible QMenu. Rebuild only inactive source menus; this is
        // the same ownership rule Plasma Global Menu follows.
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

        LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
        Layout.minimumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight

        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
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

                Layout.fillWidth: root.vertical
                Layout.fillHeight: !root.vertical
                text: modelData
                down: Plasmoid.currentIndex === index
                menuIsOpen: Plasmoid.currentIndex !== -1

                onActivated: {
                    root.prepareMenu(index)
                    Plasmoid.trigger(this, index)
                }
            }
        }

        // Same zero-size filler used by Plasma Global Menu so the menubar
        // occupies only its natural content while still satisfying GridLayout.
        Item {
            Layout.preferredWidth: 0
            Layout.preferredHeight: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
