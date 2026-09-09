/*
 * SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>
 * SPDX-FileCopyrightText: 2026 Neil Ruffell
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Popup switching/event handling is adapted from Plasma Global Menu.
 */

#include "gnome2menubarapplet.h"

#include <KAuthorized>
#include <KConfigGroup>
#include <KDesktopFile>
#include <KPluginMetaData>
#include <KRuntimePlatform>
#include <Plasma/Plasma>

#include <QAction>
#include <QDir>
#include <QEvent>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QKeyEvent>
#include <QMenu>
#include <QMouseEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScreen>
#include <QStandardPaths>
#include <QTimer>
#include <QWidget>
#include <QWindow>

#include <algorithm>
#include <functional>
#include <utility>

namespace
{
struct PreferenceCategory {
    QString id;
    QString name;
    QString icon;
    QString parent;
    int weight = 100;
};

struct PreferenceModule {
    QString id;
    QString name;
    QString icon;
    QString parent;
    int weight = 100;
};

Qt::Edges edgeFromLocation(Plasma::Types::Location location)
{
    switch (location) {
    case Plasma::Types::TopEdge:
        return Qt::TopEdge;
    case Plasma::Types::BottomEdge:
        return Qt::BottomEdge;
    case Plasma::Types::LeftEdge:
        return Qt::LeftEdge;
    case Plasma::Types::RightEdge:
        return Qt::RightEdge;
    case Plasma::Types::Floating:
    case Plasma::Types::Desktop:
    case Plasma::Types::FullScreen:
        break;
    }
    return {};
}

QVariantMap moduleMap(const PreferenceModule &module)
{
    return {
        {QStringLiteral("type"), QStringLiteral("item")},
        {QStringLiteral("kind"), QStringLiteral("kcm")},
        {QStringLiteral("id"), module.id},
        {QStringLiteral("name"), module.name},
        {QStringLiteral("icon"), module.icon},
        {QStringLiteral("weight"), module.weight},
    };
}

bool preferenceLess(const QVariant &left, const QVariant &right)
{
    const QVariantMap a = left.toMap();
    const QVariantMap b = right.toMap();
    const int aw = a.value(QStringLiteral("weight"), 100).toInt();
    const int bw = b.value(QStringLiteral("weight"), 100).toInt();
    if (aw != bw) {
        return aw < bw;
    }
    return a.value(QStringLiteral("name")).toString().localeAwareCompare(b.value(QStringLiteral("name")).toString()) < 0;
}
} // namespace

Gnome2MenuBarApplet::Gnome2MenuBarApplet(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
    : Plasma::Applet(parent, data, args)
{
    // Plasma Global Menu's File/Edit/View source menus are submenus of one
    // imported root QMenu. Reproduce that QWidget ownership hierarchy here so
    // the persistent visible popup can use the same source-menu parent.
    m_menuRoot = new QMenu;
    for (MenuState &state : m_menus) {
        state.root = new QMenu(m_menuRoot);
        m_menuRoot->addMenu(state.root);
        state.handles.insert(0, state.root);
    }
}

Gnome2MenuBarApplet::~Gnome2MenuBarApplet()
{
    // Match Global Menu's hide lifecycle: reconnect the visible menuAction to
    // its source without mutating the action list during popup teardown.
    if (m_currentMenu && m_sourceMenu) {
        QAction *menuAction = m_currentMenu->menuAction();
        menuAction->setMenu(m_sourceMenu);
    }

    delete m_menuRoot;
    m_menuRoot = nullptr;
    m_currentMenu = nullptr;
    m_sourceMenu = nullptr;

    for (MenuState &state : m_menus) {
        state.root = nullptr;
        state.handles.clear();
    }
}

bool Gnome2MenuBarApplet::validTopIndex(int index)
{
    return index >= 0 && index < 3;
}

int Gnome2MenuBarApplet::currentIndex() const
{
    return m_currentIndex;
}

void Gnome2MenuBarApplet::setCurrentIndex(int index)
{
    if (m_currentIndex == index) {
        return;
    }
    m_currentIndex = index;
    Q_EMIT currentIndexChanged();
}

QQuickItem *Gnome2MenuBarApplet::buttonGrid() const
{
    return m_buttonGrid;
}

void Gnome2MenuBarApplet::setButtonGrid(QQuickItem *buttonGrid)
{
    if (m_buttonGrid == buttonGrid) {
        return;
    }
    m_buttonGrid = buttonGrid;
    Q_EMIT buttonGridChanged();
}

bool Gnome2MenuBarApplet::showIcons() const
{
    return m_showIcons;
}

void Gnome2MenuBarApplet::setShowIcons(bool showIcons)
{
    if (m_showIcons == showIcons) {
        return;
    }
    m_showIcons = showIcons;
    Q_EMIT showIconsChanged();
}

QMenu *Gnome2MenuBarApplet::sourceMenu(int index) const
{
    if (!validTopIndex(index)) {
        return nullptr;
    }
    return m_menus.at(static_cast<std::size_t>(index)).root;
}

QMenu *Gnome2MenuBarApplet::menuForHandle(int topIndex, int handle) const
{
    if (!validTopIndex(topIndex)) {
        return nullptr;
    }
    return m_menus.at(static_cast<std::size_t>(topIndex)).handles.value(handle);
}

QIcon Gnome2MenuBarApplet::iconFromVariant(const QVariant &value) const
{
    if (!m_showIcons || !value.isValid() || value.isNull()) {
        return {};
    }

    if (value.canConvert<QIcon>()) {
        const QIcon icon = qvariant_cast<QIcon>(value);
        if (!icon.isNull()) {
            return icon;
        }
    }

    const QString iconName = value.toString();
    if (!iconName.isEmpty()) {
        return QIcon::fromTheme(iconName);
    }

    return {};
}

void Gnome2MenuBarApplet::clearMenu(int topIndex)
{
    if (!validTopIndex(topIndex)) {
        return;
    }

    // Source actions are temporarily moved into m_currentMenu while that top
    // menu is visible, exactly like Plasma's Global Menu applet. Do not mutate
    // the currently displayed source menu underneath the popup.
    if (m_currentIndex == topIndex && m_currentMenu && m_currentMenu->isVisible()) {
        return;
    }

    MenuState &state = m_menus.at(static_cast<std::size_t>(topIndex));
    if (!state.root) {
        return;
    }

    // Global Menu deliberately leaves the last source's actions in the shared
    // visible QMenu after aboutToHide. If our dynamic source became dirty while
    // it was active, restore those actions only now, after the popup event has
    // fully completed, before rebuilding that inactive source menu.
    if (m_sourceMenu == state.root && m_currentMenu && !m_currentMenu->isVisible()) {
        restoreCurrentMenuActions();
    }

    state.root->clear();
    state.handles.clear();
    state.handles.insert(0, state.root);
    state.nextHandle = 1;
}

int Gnome2MenuBarApplet::addSubmenu(int topIndex, int parentHandle, const QString &text, const QVariant &icon)
{
    QMenu *parentMenu = menuForHandle(topIndex, parentHandle);
    if (!parentMenu) {
        return -1;
    }

    MenuState &state = m_menus.at(static_cast<std::size_t>(topIndex));
    const int handle = state.nextHandle++;

    auto *submenu = new QMenu(text, parentMenu);
    const QIcon menuIcon = iconFromVariant(icon);
    if (!menuIcon.isNull()) {
        submenu->setIcon(menuIcon);
    }
    parentMenu->addMenu(submenu);
    state.handles.insert(handle, submenu);
    return handle;
}

void Gnome2MenuBarApplet::addAction(int topIndex,
                                    int parentHandle,
                                    const QString &text,
                                    const QVariant &icon,
                                    const QString &actionId,
                                    bool enabled)
{
    QMenu *parentMenu = menuForHandle(topIndex, parentHandle);
    if (!parentMenu) {
        return;
    }

    QAction *action = nullptr;
    const QIcon actionIcon = iconFromVariant(icon);
    if (actionIcon.isNull()) {
        action = parentMenu->addAction(text);
    } else {
        action = parentMenu->addAction(actionIcon, text);
    }

    action->setEnabled(enabled);
    action->setData(actionId);

    if (!actionId.isEmpty()) {
        connect(action, &QAction::triggered, this, [this, actionId]() {
            Q_EMIT actionTriggered(actionId);
        });
    }
}

void Gnome2MenuBarApplet::addSeparator(int topIndex, int parentHandle)
{
    QMenu *parentMenu = menuForHandle(topIndex, parentHandle);
    if (parentMenu && !parentMenu->isEmpty()) {
        parentMenu->addSeparator();
    }
}

void Gnome2MenuBarApplet::restoreCurrentMenuActions()
{
    if (!m_currentMenu || !m_sourceMenu) {
        return;
    }

    // This is the exact action hand-off Global Menu performs when switching
    // from one top-level source menu to another. It is intentionally *not*
    // called synchronously from aboutToHide.
    QAction *menuAction = m_currentMenu->menuAction();
    const QList<QAction *> actions = m_currentMenu->actions();
    for (QAction *action : actions) {
        m_currentMenu->removeAction(action);
        m_sourceMenu->addAction(action);
    }
    menuAction->setMenu(m_sourceMenu);
}

void Gnome2MenuBarApplet::onMenuAboutToHide()
{
    // Match Plasma 6.6.5 Global Menu literally: do not remove/reinsert actions
    // from the QMenu while Qt is processing the outside click that hides it.
    // Only restore the menuAction relationship and clear the active index.
    if (m_currentMenu && m_sourceMenu) {
        QAction *menuAction = m_currentMenu->menuAction();
        menuAction->setMenu(m_sourceMenu);
    }
    setCurrentIndex(-1);
}

void Gnome2MenuBarApplet::trigger(QQuickItem *ctx, int idx)
{
    if (m_currentIndex == idx) {
        return;
    }

    if (!ctx || !ctx->window() || !ctx->window()->screen()) {
        return;
    }

    QMenu *actionMenu = sourceMenu(idx);
    if (!actionMenu) {
        return;
    }

    // Same mouse-ungrab workaround used by Plasma Global Menu.
    auto ungrabMouseHack = [ctx]() {
        if (ctx && ctx->window() && ctx->window()->mouseGrabberItem()) {
            ctx->window()->mouseGrabberItem()->ungrabMouse();
        }
    };

    // Keep this block structurally aligned with AppMenuApplet::trigger() in
    // plasma-workspace 6.6.5 FullView.
    if (!m_currentMenu) {
        m_currentMenu = new QMenu(qobject_cast<QWidget *>(actionMenu->parent()));
        connect(m_currentMenu, &QMenu::aboutToHide, this, &Gnome2MenuBarApplet::onMenuAboutToHide, Qt::UniqueConnection);
    } else if (m_sourceMenu != actionMenu) {
        restoreCurrentMenuActions();
    }

    m_sourceMenu = actionMenu;
    QAction *menuAction = m_sourceMenu->menuAction();
    const QList<QAction *> sourceActions = m_sourceMenu->actions();
    for (QAction *action : sourceActions) {
        m_sourceMenu->removeAction(action);
        m_currentMenu->addAction(action);
    }
    menuAction->setMenu(m_currentMenu);

    QTimer::singleShot(0, ctx, ungrabMouseHack);

    const auto &geo = ctx->window()->screen()->availableVirtualGeometry();
    QPoint pos = ctx->window()->mapToGlobal(ctx->mapToScene(QPointF()).toPoint());

    const Qt::Edges edges = edgeFromLocation(location());
    m_currentMenu->setProperty("_breeze_menu_seamless_edges", QVariant::fromValue(edges));

    // Plasma Global Menu 6.6.5 only applies the explicit panel-edge offset for
    // TopEdge. Keep this exact rather than maintaining a second positioning
    // policy in this applet.
    if (location() == Plasma::Types::TopEdge) {
        pos.setY(pos.y() + ctx->height());
    }

    m_currentMenu->adjustSize();
    pos = QPoint(qBound(geo.x(), pos.x(), geo.x() + geo.width() - m_currentMenu->width()),
                 qBound(geo.y(), pos.y(), geo.y() + geo.height() - m_currentMenu->height()));

    if (m_currentMenu->isVisible()) {
        m_currentMenu->move(pos);
    } else {
        m_currentMenu->installEventFilter(this);
        m_currentMenu->winId(); // create window handle, as Global Menu does
        m_currentMenu->windowHandle()->setTransientParent(ctx->window());
        m_currentMenu->popup(pos);
    }

    setCurrentIndex(idx);
}

bool Gnome2MenuBarApplet::eventFilter(QObject *watched, QEvent *event)
{
    auto *menu = qobject_cast<QMenu *>(watched);
    if (!menu) {
        return false;
    }

    // Same navigation bridge used by Plasma's Global Menu applet: QMenu owns
    // the mouse grab, so panel-button hover is detected from QMenu mouse moves.
    if (event->type() == QEvent::KeyPress) {
        auto *e = static_cast<QKeyEvent *>(event);
        if (e->key() == Qt::Key_Left) {
            Q_EMIT requestActivateIndex(m_currentIndex - 1);
            return true;
        }
        if (e->key() == Qt::Key_Right) {
            if (menu->activeAction() && menu->activeAction()->menu()) {
                return false;
            }
            Q_EMIT requestActivateIndex(m_currentIndex + 1);
            return true;
        }
    } else if (event->type() == QEvent::MouseMove) {
        auto *e = static_cast<QMouseEvent *>(event);

        if (!m_buttonGrid || !m_buttonGrid->window()) {
            return false;
        }

        const QPointF windowLocalPos = m_buttonGrid->window()->mapFromGlobal(e->globalPosition());
        const QPointF buttonGridLocalPos = m_buttonGrid->mapFromScene(windowLocalPos);
        QQuickItem *item = m_buttonGrid->childAt(buttonGridLocalPos.x(), buttonGridLocalPos.y());
        if (!item) {
            return false;
        }

        bool ok = false;
        const int buttonIndex = item->property("buttonIndex").toInt(&ok);
        if (!ok) {
            return false;
        }

        Q_EMIT requestActivateIndex(buttonIndex);
    }

    return false;
}

QVariantList Gnome2MenuBarApplet::preferenceTree() const
{
    QHash<QString, PreferenceCategory> categories;

    const QStringList categoryDirs = QStandardPaths::locateAll(QStandardPaths::GenericDataLocation,
                                                                QStringLiteral("systemsettings/categories"),
                                                                QStandardPaths::LocateDirectory);
    for (const QString &directoryPath : categoryDirs) {
        const QDir directory(directoryPath);
        const QFileInfoList files = directory.entryInfoList({QStringLiteral("*.desktop")}, QDir::Files, QDir::Name);
        for (const QFileInfo &fileInfo : files) {
            KDesktopFile desktopFile(fileInfo.absoluteFilePath());
            const KConfigGroup group = desktopFile.desktopGroup();

            const QString id = group.readEntry(QStringLiteral("X-KDE-System-Settings-Category"));
            if (id.isEmpty() || categories.contains(id)) {
                continue;
            }

            QString parent = group.readEntry(QStringLiteral("X-KDE-System-Settings-Parent-Category-V2"));
            if (parent.isEmpty()) {
                parent = group.readEntry(QStringLiteral("X-KDE-System-Settings-Parent-Category"));
            }

            PreferenceCategory category;
            category.id = id;
            category.name = desktopFile.readName();
            if (category.name.isEmpty()) {
                category.name = id;
            }
            category.icon = desktopFile.readIcon();
            category.parent = parent;
            category.weight = group.readEntry(QStringLiteral("X-KDE-Weight"), 100);
            categories.insert(id, category);
        }
    }

    QHash<QString, PreferenceModule> modules;

    // Match System Settings' findKCMsMetaData(SystemSettings) discovery rules:
    // use KPluginMetaData namespaces, respect Qt platform/form-factor metadata,
    // and honor KAuthorized control-module policy. KPluginMetaData resolves Qt
    // library paths itself, so this is distro-independent.
    const auto systemSettingsFilter = [](const KPluginMetaData &metaData) {
        const QStringList supportedPlatforms = metaData.value(
            QStringLiteral("X-KDE-OnlyShowOnQtPlatforms"), QStringList());
        if (!supportedPlatforms.isEmpty()) {
            const QString platformName = qGuiApp->platformName();
            const bool platformMatches = std::any_of(
                supportedPlatforms.cbegin(),
                supportedPlatforms.cend(),
                [&platformName](const QString &platform) {
                    return platformName.startsWith(platform);
                });
            if (!platformMatches) {
                return false;
            }
        }

        QStringList runtimePlatforms = KRuntimePlatform::runtimePlatform();
        if (runtimePlatforms.isEmpty()) {
            runtimePlatforms.append(QStringLiteral("desktop"));
        }

        const QStringList formFactors = metaData.formFactors();
        if (formFactors.isEmpty() || formFactors.contains(QStringLiteral("all"))) {
            return true;
        }

        return std::any_of(
            formFactors.cbegin(),
            formFactors.cend(),
            [&runtimePlatforms](const QString &formFactor) {
                return runtimePlatforms.contains(formFactor);
            });
    };

    QList<KPluginMetaData> pluginList = KPluginMetaData::findPlugins(
        QStringLiteral("plasma/kcms"), systemSettingsFilter);
    pluginList += KPluginMetaData::findPlugins(
        QStringLiteral("plasma/kcms/systemsettings"), systemSettingsFilter);
    pluginList += KPluginMetaData::findPlugins(
        QStringLiteral("plasma/kcms/systemsettings_qwidgets"), systemSettingsFilter);

    for (const KPluginMetaData &metaData : std::as_const(pluginList)) {
        if (!metaData.isValid()
            || metaData.isHidden()
            || !KAuthorized::authorizeControlModule(metaData.pluginId())) {
            continue;
        }

        QString parent = metaData.value(
            QStringLiteral("X-KDE-System-Settings-Parent-Category-V2"), QString());
        if (parent.isEmpty()) {
            parent = metaData.value(
                QStringLiteral("X-KDE-System-Settings-Parent-Category"), QString());
        }
        if (parent.isEmpty() || parent == QLatin1String("rootcategory") || parent == QLatin1String("lost-and-found")) {
            continue;
        }

        const QString id = metaData.pluginId();
        const QString displayName = metaData.name();
        // System Settings uses KPluginMetaData::name() as the visible module
        // label. A raw plugin ID is an implementation detail, not a user-facing
        // fallback; if a metadata candidate has no display name, ignore it so a
        // named candidate from another System Settings namespace can win.
        if (id.isEmpty() || displayName.isEmpty() || modules.contains(id)) {
            continue;
        }

        PreferenceModule module;
        module.id = id;
        module.name = displayName;
        module.icon = metaData.iconName().isEmpty() ? QStringLiteral("preferences-system") : metaData.iconName();
        module.parent = parent;
        module.weight = metaData.value(QStringLiteral("X-KDE-Weight"), 100);
        modules.insert(id, module);
    }

    QMultiHash<QString, QString> childCategories;
    for (auto it = categories.cbegin(); it != categories.cend(); ++it) {
        const PreferenceCategory &category = it.value();
        if (!category.parent.isEmpty() && categories.contains(category.parent)) {
            childCategories.insert(category.parent, category.id);
        }
    }

    QMultiHash<QString, QString> childModules;
    QStringList looseModules;
    for (auto it = modules.cbegin(); it != modules.cend(); ++it) {
        if (categories.contains(it.value().parent)) {
            childModules.insert(it.value().parent, it.key());
        } else {
            looseModules.append(it.key());
        }
    }

    std::function<QVariantMap(const QString &)> serializeCategory;
    serializeCategory = [&](const QString &categoryId) -> QVariantMap {
        const PreferenceCategory category = categories.value(categoryId);
        QVariantList children;

        const QList<QString> categoryChildren = childCategories.values(categoryId);
        for (const QString &childId : categoryChildren) {
            const QVariantMap child = serializeCategory(childId);
            if (!child.value(QStringLiteral("children")).toList().isEmpty()) {
                children.append(child);
            }
        }

        const QList<QString> moduleChildren = childModules.values(categoryId);
        for (const QString &moduleId : moduleChildren) {
            children.append(moduleMap(modules.value(moduleId)));
        }

        std::sort(children.begin(), children.end(), preferenceLess);

        return {
            {QStringLiteral("type"), QStringLiteral("category")},
            {QStringLiteral("id"), category.id},
            {QStringLiteral("name"), category.name},
            {QStringLiteral("icon"), category.icon},
            {QStringLiteral("weight"), category.weight},
            {QStringLiteral("children"), children},
        };
    };

    QVariantList result;
    for (auto it = categories.cbegin(); it != categories.cend(); ++it) {
        const PreferenceCategory &category = it.value();
        const bool isRoot = category.parent.isEmpty() || category.parent == QLatin1String("rootcategory") || !categories.contains(category.parent);
        if (!isRoot || category.id == QLatin1String("rootcategory") || category.id == QLatin1String("lost-and-found")) {
            continue;
        }

        const QVariantMap serialized = serializeCategory(category.id);
        if (!serialized.value(QStringLiteral("children")).toList().isEmpty()) {
            result.append(serialized);
        }
    }

    if (!looseModules.isEmpty()) {
        QVariantList otherChildren;
        for (const QString &moduleId : std::as_const(looseModules)) {
            otherChildren.append(moduleMap(modules.value(moduleId)));
        }
        std::sort(otherChildren.begin(), otherChildren.end(), preferenceLess);
        result.append(QVariantMap{
            {QStringLiteral("type"), QStringLiteral("category")},
            {QStringLiteral("id"), QStringLiteral("other")},
            {QStringLiteral("name"), QStringLiteral("Other")},
            {QStringLiteral("icon"), QStringLiteral("preferences-other")},
            {QStringLiteral("weight"), 10000},
            {QStringLiteral("children"), otherChildren},
        });
    }

    std::sort(result.begin(), result.end(), preferenceLess);
    return result;
}

K_PLUGIN_CLASS_WITH_JSON(Gnome2MenuBarApplet, "../metadata.json")

#include "gnome2menubarapplet.moc"
#include "moc_gnome2menubarapplet.cpp"
