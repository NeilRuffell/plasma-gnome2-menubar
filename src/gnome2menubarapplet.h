/*
 * SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>
 * SPDX-FileCopyrightText: 2026 Neil Ruffell
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Native menu backend for plasma-gnome2-menubar.
 *
 * The popup/switching code intentionally follows Plasma's Global Menu applet
 * (plasma-workspace/applets/appmenu) so top-level menu interaction is handled
 * with the same QWidget/QMenu foundation rather than Qt Quick popup menus.
 */

#pragma once

#include <Plasma/Applet>

#include <QHash>
#include <QPointer>
#include <QVariant>
#include <array>

class QAction;
class QIcon;
class QMenu;
class QQuickItem;

class Gnome2MenuBarApplet : public Plasma::Applet
{
    Q_OBJECT

    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(QQuickItem *buttonGrid READ buttonGrid WRITE setButtonGrid NOTIFY buttonGridChanged)
    Q_PROPERTY(bool showIcons READ showIcons WRITE setShowIcons NOTIFY showIconsChanged)

public:
    explicit Gnome2MenuBarApplet(QObject *parent, const KPluginMetaData &data, const QVariantList &args);
    ~Gnome2MenuBarApplet() override;

    int currentIndex() const;

    QQuickItem *buttonGrid() const;
    void setButtonGrid(QQuickItem *buttonGrid);

    bool showIcons() const;
    void setShowIcons(bool showIcons);

    Q_INVOKABLE void clearMenu(int topIndex);
    Q_INVOKABLE int addSubmenu(int topIndex, int parentHandle, const QString &text, const QVariant &icon = {});
    Q_INVOKABLE void addAction(int topIndex,
                               int parentHandle,
                               const QString &text,
                               const QVariant &icon,
                               const QString &actionId,
                               bool enabled = true);
    Q_INVOKABLE void addSeparator(int topIndex, int parentHandle);

    // Returns the installed System Settings hierarchy using KDE's own category
    // desktop files plus KPluginMetaData plugin discovery. No helper process is
    // used and no distro-specific Qt plugin path is hard-coded.
    Q_INVOKABLE QVariantList preferenceTree() const;

Q_SIGNALS:
    void currentIndexChanged();
    void buttonGridChanged();
    void showIconsChanged();
    void requestActivateIndex(int index);
    void actionTriggered(const QString &actionId);

public Q_SLOTS:
    void trigger(QQuickItem *ctx, int idx);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    struct MenuState {
        QPointer<QMenu> root;
        QHash<int, QPointer<QMenu>> handles;
        int nextHandle = 1;
    };

    static bool validTopIndex(int index);
    QMenu *sourceMenu(int index) const;
    QMenu *menuForHandle(int topIndex, int handle) const;
    QIcon iconFromVariant(const QVariant &value) const;

    void setCurrentIndex(int index);
    void onMenuAboutToHide();
    void restoreCurrentMenuActions();

    // Global Menu's top-level source menus are submenus of one root QMenu.
    // Mirroring that hierarchy gives the persistent visible menu the same
    // QWidget parent/ownership relationship as Plasma's implementation.
    QPointer<QMenu> m_menuRoot;
    std::array<MenuState, 3> m_menus;
    int m_currentIndex = -1;
    bool m_showIcons = true;

    QPointer<QMenu> m_currentMenu;
    QPointer<QMenu> m_sourceMenu;
    QPointer<QQuickItem> m_buttonGrid;
};
