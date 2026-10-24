import QtQuick
import QtQuick.Layouts

Card {
    id: ac
    property string title
    property string detail
    property string button
    property string icon
    property color tint: Theme.accent
    signal triggered()
    Layout.fillWidth: true
    implicitHeight: 72
    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        IconTile { icon: ac.icon; color: ac.tint; size: 36 }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: ac.title
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: Theme.text
            }
            Text {
                text: ac.detail
                font.family: "monospace"
                font.pixelSize: 12
                color: Theme.subtext
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
        PillButton {
            text: ac.button
            filled: false
            enabled: !actions.step
            onClicked: ac.triggered()
        }
    }
}
