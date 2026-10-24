import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    spacing: 16

    // Hero: everything in one click
    Card {
        Layout.fillWidth: true
        implicitHeight: heroCol.implicitHeight + 36
        ColumnLayout {
            id: heroCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            RowLayout {
                spacing: 14
                IconTile {
                    icon: "update"
                    color: checker.count ? Theme.orange : Theme.success
                    size: 48
                    Behavior on color { ColorAnimation { duration: Theme.animMs } }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        text: actions.step || "Update everything"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: Theme.text
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 10
                        Text {
                            text: checker.checking ? "Checking for updates…"
                                : checker.error ? checker.error
                                : checker.count ? Theme.plural(checker.count, "update") + " available"
                                                  + (checker.aurCount ? " (" + checker.aurCount + " AUR)" : "")
                                : "Up to date" + (checker.lastCheck ? " · checked " + checker.lastCheck : "")
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: checker.error ? Theme.danger : checker.count ? Theme.accent : Theme.success
                            elide: Text.ElideRight
                            Layout.maximumWidth: 340
                        }
                        LinkText {
                            text: "Show"
                            visible: checker.count > 0 && !checker.checking
                            onClicked: updatesPopup.open()
                        }
                        LinkText {
                            text: "Check now"
                            visible: !checker.checking
                            onClicked: checker.check()
                        }
                    }
                }
                PillButton {
                    text: "Stop"
                    visible: runner.running
                    filled: false
                    tint: Theme.danger
                    onClicked: runner.stop()
                }
                PillButton {
                    text: "Update all"
                    implicitHeight: 46
                    font.pixelSize: 17
                    enabled: !actions.step
                    onClicked: Theme.begin(actions.updateAll)
                }
            }

            // Progress through the steps of "Update all"
            ColumnLayout {
                Layout.fillWidth: true
                visible: actions.stepTotal > 1
                spacing: 4
                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Theme.fill
                    Rectangle {
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                        width: parent.width * Math.max(0.04, (actions.stepIndex - 0.5) / Math.max(1, actions.stepTotal))
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    text: actions.plan.join("  →  ")
                    font.pixelSize: 11
                    color: Theme.subtext
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 16
        rowSpacing: 16
        ActionCard {
            title: "System update"
            detail: (Theme.rev, settings.get("update_command"))
            button: "Update"
            icon: "update"
            tint: Theme.tileBlue
            onTriggered: Theme.begin(actions.update)
        }
        ActionCard {
            title: "AUR"
            detail: (Theme.rev, actions.detectedAurHelper() || "no helper found") + " -Sua"
            button: "Update"
            icon: "package"
            tint: Theme.purple
            onTriggered: Theme.begin(actions.aur)
        }
        ActionCard {
            title: "Cache"
            detail: "keep " + (Theme.rev, settings.get("cache_keep")) + " versions"
            button: "Clean"
            icon: "trash"
            tint: Theme.orange
            // Full width when there is no fix card next to it
            Layout.columnSpan: fixCard.visible ? 1 : 2
            onTriggered: Theme.begin(actions.cleanCache)
        }
        ActionCard {
            id: fixCard
            readonly property string cmd: (Theme.rev, settings.get("fix_command"))
            visible: cmd.trim().length > 0
            title: "System fix"
            detail: cmd.indexOf("garuda-health --fix") === 0 && cmd.indexOf("limine-update") > 0
                    ? "garuda-health --fix → limine-update" : cmd
            button: "Run"
            icon: "shield"
            tint: Theme.teal
            onTriggered: Theme.begin(actions.fix)
        }
    }

    LogView {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    // Answer bar for questions from pacman/paru
    Card {
        Layout.fillWidth: true
        visible: runner.prompt.length > 0
        implicitHeight: 62
        border.color: Theme.accent
        border.width: 1.5
        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            Text {
                text: "Answer needed"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Theme.accent
            }
            PilotField {
                id: answer
                Layout.fillWidth: true
                placeholderText: "Custom answer"
                onAccepted: { runner.send(text); text = "" }
            }
            PillButton { text: "Send"; filled: false; onClicked: { runner.send(answer.text); answer.text = "" } }
            PillButton { text: "Default"; filled: false; onClicked: runner.send("") }
            PillButton { text: "No"; filled: false; tint: Theme.danger; onClicked: runner.send("n") }
            PillButton { text: "Yes"; onClicked: runner.send("y") }
        }
    }

    Popup {
        id: updatesPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 80)
        height: Math.min(500, parent.height - 80)
        modal: true
        padding: 20
        background: Rectangle { radius: Theme.radius; color: Theme.card }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMs }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.animMs; easing.type: Easing.OutCubic }
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            Text {
                text: Theme.plural(checker.count, "update")
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Theme.text
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: checker.packages
                ScrollBar.vertical: ScrollBar {}
                delegate: RowLayout {
                    required property var modelData
                    width: ListView.view.width - 12
                    height: 32
                    Text {
                        text: modelData.name
                        color: Theme.text
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "AUR"
                        visible: modelData.source === "aur"
                        color: Theme.purple
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: modelData.old + "  →  " + modelData.new
                        color: Theme.subtext
                        font.family: "monospace"
                        font.pixelSize: 12
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                PillButton { text: "Close"; filled: false; onClicked: updatesPopup.close() }
                PillButton {
                    text: "Update all"
                    enabled: !actions.step
                    onClicked: {
                        updatesPopup.close()
                        Theme.begin(actions.updateAll)
                    }
                }
            }
        }
    }
}
