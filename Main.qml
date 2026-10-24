import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qml"

ApplicationWindow {
    id: win
    width: 1040
    height: 720
    minimumWidth: 900
    minimumHeight: 520
    visible: !startHidden
    title: "Vardr – System Updates"
    color: Theme.bg

    readonly property var pages: [
        { title: "Maintenance", icon: "update", tint: Theme.accent },
        { title: "Repositories", icon: "database", tint: Theme.purple },
        { title: "Settings", icon: "gear", tint: "#8e8e93" }
    ]

    // Called from the tray menu
    function showPage(i) { Theme.page = i }
    function startUpdateAll() { if (!actions.step) Theme.begin(actions.updateAll) }

    // With a tray icon, closing only hides the window; checks keep running
    onClosing: (close) => {
        if (trayAvailable) {
            close.accepted = false
            hide()
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------- Sidebar ----------------
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
            color: Theme.sidebar

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                anchors.topMargin: 20
                spacing: 4

                RowLayout {
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 14
                    spacing: 10
                    Image {
                        source: "icons/vardr.svg"
                        sourceSize: Qt.size(34, 34)
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Vardr"
                            font.pixelSize: 22
                            font.weight: Font.Bold
                            color: Theme.text
                        }
                        Text {
                            text: "Update guardian"
                            font.pixelSize: 12
                            color: Theme.subtext
                        }
                    }
                }

                Repeater {
                    model: win.pages
                    delegate: Rectangle {
                        id: nav
                        required property int index
                        required property var modelData
                        readonly property bool current: Theme.page === index
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: 10
                        color: current ? Theme.accent
                             : hover.hovered ? Qt.rgba(0.5, 0.5, 0.5, 0.12) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animMs } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 10
                            spacing: 10
                            IconTile {
                                icon: nav.modelData.icon
                                color: nav.current ? Qt.rgba(1, 1, 1, 0.22) : nav.modelData.tint
                                size: 28
                            }
                            Text {
                                text: nav.modelData.title
                                font.pixelSize: 15
                                font.weight: nav.current ? Font.DemiBold : Font.Normal
                                color: nav.current ? "white" : Theme.text
                                Layout.fillWidth: true
                            }
                            // Update count badge
                            Rectangle {
                                readonly property int count: nav.index === 0 ? checker.count : 0
                                visible: count > 0
                                implicitWidth: Math.max(22, badgeText.implicitWidth + 12)
                                implicitHeight: 22
                                radius: 11
                                color: nav.current ? "white" : Theme.danger
                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: parent.count
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: nav.current ? Theme.accent : "white"
                                }
                            }
                        }
                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Theme.page = nav.index }
                    }
                }

                Item { Layout.fillHeight: true }

                // Small live status + light/dark toggle at the bottom of the sidebar
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    spacing: 8
                    Text {
                        text: actions.step ? actions.step
                            : checker.checking ? "Checking…"
                            : checker.count ? Theme.plural(checker.count, "update") + " available"
                            : "System up to date"
                        font.pixelSize: 12
                        color: Theme.subtext
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    IconTile {
                        icon: Theme.dark ? "sun" : "moon"
                        color: modeHover.hovered ? Theme.accent : (Theme.dark ? "#48484a" : "#8e8e93")
                        size: 32
                        radius: 16
                        Behavior on color { ColorAnimation { duration: Theme.animMs } }
                        HoverHandler { id: modeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Theme.toggleDark() }
                        ToolTip.visible: modeHover.hovered
                        ToolTip.delay: 600
                        ToolTip.text: Theme.dark ? "Light mode" : "Dark mode"
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.separator
                opacity: 0.6
            }
        }

        // ---------------- Content ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 24
            Layout.topMargin: 18
            spacing: 14

            Text {
                text: win.pages[Theme.page].title
                font.pixelSize: 30
                font.weight: Font.Bold
                color: Theme.text
            }

            StackLayout {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: Theme.page
                onCurrentIndexChanged: pageIn.restart()

                MaintenancePage {}
                ReposPage {}
                SettingsPage {}

                NumberAnimation {
                    id: pageIn
                    target: stack
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
