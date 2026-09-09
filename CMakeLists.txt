cmake_minimum_required(VERSION 3.20)

project(plasma-gnome2-menubar VERSION 0.8.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

find_package(Qt6 REQUIRED COMPONENTS Core Widgets Quick)
find_package(KF6 REQUIRED COMPONENTS Config CoreAddons)
find_package(Plasma REQUIRED)

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
