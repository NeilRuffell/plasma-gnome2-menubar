cmake_minimum_required(VERSION 3.22)

project(plasma-gnome2-menubar VERSION 0.9.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs6)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Widgets Quick)
find_package(KF6 6.0 REQUIRED COMPONENTS Config CoreAddons)
find_package(Plasma 6.0 REQUIRED)

plasma_add_applet(org.local.plasma.gnome2menubar
    QML_SOURCES
        qml/main.qml
        qml/MenuDelegate.qml
        qml/config.qml
        qml/configGeneral.qml
    CPP_SOURCES
        src/gnome2menubarapplet.cpp
        src/gnome2menubarapplet.h
    RESOURCES
        main.xml
    QML_ARGS DEPENDENCIES QtCore org.kde.plasma.core
)

target_link_libraries(org.local.plasma.gnome2menubar PRIVATE
    Qt6::Core
    Qt6::Widgets
    Qt6::Quick
    Plasma::Plasma
    KF6::ConfigCore
    KF6::CoreAddons
)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
