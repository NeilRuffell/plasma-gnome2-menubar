/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQml

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
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

    // QMenu interprets '&' as a mnemonic marker. All strings supplied by the
    // KDE models here are display labels, so literal ampersands must be escaped
    // before they are handed to QAction/QMenu. This preserves labels such as
    // "Input & Output" and "Mouse & Touchpad" exactly.
    function qMenuText(text) {
        return String(text || "").replace(/&/g, "&&")
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
                const submenuHandle = Plasmoid.addSubmenu(topIndex, parentHandle, qMenuText(text), iconValue)
                if (submenuHandle >= 0) {
                    appendKickerModel(topIndex, submenuHandle, childModel, depth + 1)
                }
            } else if (!text || String(text).trim().length === 0) {
                Plasmoid.addSeparator(topIndex, parentHandle)
            } else {
                const token = registerTarget(topIndex, sourceModel, row)
                Plasmoid.addAction(topIndex, parentHandle, qMenuText(text), iconValue, token, true)
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
                    qMenuText(node.name || node.id || i18n("Other")),
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
                        qMenuText(node.name),
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
                qMenuText(text),
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
            qMenuText(i18n("Recent Documents")),
            "document-open-recent"
        )

        if (recentDocumentsModel.count === 0) {
            Plasmoid.addAction(topIndex, recentHandle, qMenuText(i18n("No Recent Documents")), "", "", false)
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
                    qMenuText(text),
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
            qMenuText(i18n("Preferences")),
            "preferences-system"
        )
        appendPreferenceNodes(topIndex, preferencesHandle, kcmEntries, 0)

        const administrationHandle = Plasmoid.addSubmenu(
            topIndex,
            0,
            qMenuText(i18n("Administration")),
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
            Plasmoid.addAction(topIndex, 0, qMenuText(text), modelIcon(systemActionsModel, row), token, true)
        }

        systemDirty = false
    }

    // Keep all inactive source QMenus populated. Plasma Global Menu switches
    // between already-existing source menus; it does not construct menu trees
    // inside the hover activation path. If an active menu changes underneath
    // us, leave it dirty and rebuild it immediately after it becomes inactive.
    function refreshDirtyMenus() {
        if (applicationsDirty && Plasmoid.currentIndex !== 0) {
            rebuildApplications()
        }
        if (placesDirty && Plasmoid.currentIndex !== 1) {
            rebuildPlaces()
        }
        if (systemDirty && Plasmoid.currentIndex !== 2) {
            rebuildSystem()
        }
    }

    function markApplicationsDirty() {
        applicationsDirty = true
        systemDirty = true
        Qt.callLater(root.refreshDirtyMenus)
    }

    function markPlacesDirty() {
        placesDirty = true
        Qt.callLater(root.refreshDirtyMenus)
    }

    function markSystemDirty() {
        systemDirty = true
        Qt.callLater(root.refreshDirtyMenus)
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

        onRefreshed: root.markApplicationsDirty()
    }

    Kicker.ComputerModel {
        id: computerModel
        appletInterface: root
        systemApplications: []
        onCountChanged: root.markPlacesDirty()
    }

    Kicker.RecentUsageModel {
        id: recentDocumentsModel
        shownItems: Kicker.RecentUsageModel.OnlyDocs
        ordering: Kicker.RecentUsageModel.Recent
        onCountChanged: root.markPlacesDirty()
    }

    Kicker.SystemModel {
        id: systemActionsModel
        onCountChanged: root.markSystemDirty()
    }

    Component.onCompleted: {
        Plasmoid.showIcons = Plasmoid.configuration.showIcons
        kcmEntries = Plasmoid.preferenceTree()
        applicationsDirty = true
        placesDirty = true
        systemDirty = true
        refreshDirtyMenus()
    }

    Connections {
        target: Plasmoid

        function onCurrentIndexChanged() {
            // Do not put rebuild work on the native menu-switching event itself.
            // Reconcile any source menu that became inactive on the next turn.
            Qt.callLater(root.refreshDirtyMenus)
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
            Qt.callLater(root.refreshDirtyMenus)
        }
    }

    fullRepresentation: GridLayout {
        id: buttonGrid

        // Keep the same status transitions as Global Menu FullView.
        Plasmoid.status: {
            if (Plasmoid.currentIndex > -1 && buttonRepeater.count > 0) {
                return PlasmaCore.Types.NeedsAttentionStatus
            }
            return buttonRepeater.count > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
        }

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

        Connections {
            target: Plasmoid

            // Deliberately mirrors Plasma Global Menu: while QMenu owns the
            // mouse grab, the C++ event filter resolves the hovered panel item
            // and asks QML to activate that already-populated menu.
            function onRequestActivateIndex(index: int) {
                const button = buttonRepeater.itemAt(index)
                if (button) {
                    button.activated()
                }
            }
        }

        // Global Menu also forwards generic applet activation to its first
        // menubar item. Keep the same host-level activation behavior.
        Connections {
            target: Plasmoid
            function onActivated() {
                const button = buttonRepeater.itemAt(0)
                if (button) {
                    button.activated()
                }
            }
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
                Kirigami.MnemonicData.active: altState.pressed

                down: Plasmoid.currentIndex === index
                menuIsOpen: Plasmoid.currentIndex !== -1

                // No menu construction here. This is now only the same native
                // active-index trigger used by Plasma Global Menu.
                onActivated: Plasmoid.trigger(this, index)

                // Same mnemonic-state source used by Plasma Global Menu.
                KeyboardIndicator.KeyState {
                    id: altState
                    key: Qt.Key_Alt
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
