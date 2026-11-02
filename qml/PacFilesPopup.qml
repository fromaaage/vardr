import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// .pacnew/.pacsave list: each file sorted into safe / own changes / leftover
Popup {
    id: pp
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(820, parent.width - 80)
    height: Math.min(620, parent.height - 80)
    modal: true
    padding: 20
    background: Rectangle { radius: Theme.radius; color: Theme.card }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMs }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.animMs; easing.type: Easing.OutCubic }
    }
    onAboutToShow: pacfiles.scan()

    readonly property var badges: ({
        safe: { text: "Safe to take over", color: Theme.success },
        custom: { text: "Your own changes", color: Theme.orange },
        leftover: { text: "Leftover", color: Theme.subtext },
        unreadable: { text: "Root only", color: Theme.danger }
    })

    function run(action) {
        close()
        diffPopup.close()
        Theme.begin(action)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        Text {
            text: pacfiles.count ? Theme.plural(pacfiles.count, "config file") + " to review" : "No config files to review"
            font.pixelSize: 20
            font.weight: Font.Bold
            color: Theme.text
        }
        Text {
            text: "A .pacnew is the new version from the package, your current file stays in use until you replace it."
            font.pixelSize: 12
            color: Theme.subtext
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: pacfiles.items
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var badge: pp.badges[modelData.state]
                readonly property bool isNew: modelData.kind === "pacnew"
                width: ListView.view.width - 12
                implicitHeight: rowCol.implicitHeight + 24
                radius: 10
                color: Theme.fill
                ColumnLayout {
                    id: rowCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6
                    RowLayout {
                        spacing: 8
                        Text {
                            text: row.modelData.target
                            font.family: "monospace"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Theme.text
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            implicitWidth: badgeText.implicitWidth + 16
                            implicitHeight: 22
                            radius: 11
                            color: Qt.rgba(row.badge.color.r, row.badge.color.g, row.badge.color.b, 0.2)
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: row.badge.text
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: row.badge.color
                            }
                        }
                    }
                    Text {
                        text: "." + row.modelData.kind + " · " + row.modelData.reason
                        font.pixelSize: 12
                        color: Theme.subtext
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        PillButton {
                            text: "Delete ." + row.modelData.kind
                            filled: false
                            tint: Theme.danger
                            implicitHeight: 32
                            font.pixelSize: 13
                            enabled: !actions.step
                            onClicked: pp.run(() => actions.pacDelete([row.modelData.path]))
                        }
                        PillButton {
                            text: "Compare"
                            visible: row.modelData.state !== "unreadable"
                            filled: false
                            implicitHeight: 32
                            font.pixelSize: 13
                            onClicked: diffPopup.show(row.modelData)
                        }
                        PillButton {
                            text: "Use new"
                            visible: row.modelData.state === "safe"
                            implicitHeight: 32
                            font.pixelSize: 13
                            enabled: !actions.step
                            onClicked: pp.run(() => actions.pacAdopt([row.modelData.path]))
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: pacfiles.safeCount ? "“Use new” keeps the current file as <name>.vardr-<date>.bak" : ""
                font.pixelSize: 11
                color: Theme.subtext
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            PillButton { text: "Close"; filled: false; onClicked: pp.close() }
            PillButton {
                text: "Use all safe (" + pacfiles.safeCount + ")"
                visible: pacfiles.safeCount > 1
                enabled: !actions.step
                onClicked: pp.run(actions.pacAdoptSafe)
            }
        }
    }

    // Diff view: red = current file (in use), green = new/saved file
    Popup {
        id: diffPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(900, parent.width - 60)
        height: Math.min(660, parent.height - 60)
        modal: true
        padding: 20
        background: Rectangle { radius: Theme.radius; color: Theme.card }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        property var item: ({})
        property var rows: []
        function show(it) {
            item = it
            rows = pacfiles.diff(it.path)
            open()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            Text {
                text: diffPopup.item.target || ""
                font.family: "monospace"
                font.pixelSize: 17
                font.weight: Font.Bold
                color: Theme.text
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: Theme.fill
                ListView {
                    anchors.fill: parent
                    anchors.margins: 10
                    clip: true
                    model: diffPopup.rows
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool head: modelData.t === "head"
                        width: ListView.view.width - 12
                        implicitHeight: line.implicitHeight + (head ? legend.implicitHeight + (index ? 24 : 6) : 2)
                        color: modelData.t === "del" ? Qt.rgba(1, 0.27, 0.23, 0.16)
                             : modelData.t === "add" ? Qt.rgba(0.19, 0.82, 0.35, 0.16) : "transparent"
                        // Section legend: which side is which
                        Text {
                            id: legend
                            visible: parent.head && !!parent.modelData.a
                            height: visible ? implicitHeight + 4 : 0
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 6
                            textFormat: Text.StyledText
                            text: visible ? '<font color="' + Theme.danger + '">−  ' + parent.modelData.a + '</font>'
                                  + '&nbsp;&nbsp;&nbsp;&nbsp;<font color="' + Theme.success + '">+  ' + parent.modelData.b + '</font>' : ""
                            font.family: "monospace"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            id: line
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: legend.top
                            anchors.leftMargin: 6
                            text: parent.modelData.s
                            wrapMode: Text.WrapAnywhere
                            font.family: parent.head ? Qt.application.font.family : "monospace"
                            font.pixelSize: parent.head ? 14 : 12
                            font.weight: parent.head ? Font.Bold : Font.Normal
                            color: parent.modelData.t === "hunk" ? Theme.subtext : Theme.text
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                PillButton {
                    text: "Open in meld"
                    visible: pacfiles.hasMeld()
                    filled: false
                    onClicked: pacfiles.compare(diffPopup.item.path)
                }
                PillButton { text: "Close"; filled: false; onClicked: diffPopup.close() }
                PillButton {
                    text: "Use new"
                    visible: diffPopup.item.state === "safe"
                    enabled: !actions.step
                    onClicked: pp.run(() => actions.pacAdopt([diffPopup.item.path]))
                }
            }
        }
    }
}
