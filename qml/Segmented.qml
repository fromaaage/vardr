import QtQuick
import QtQuick.Controls

TabBar {
    id: seg
    property var options: []
    spacing: 0
    background: Rectangle { radius: 9; color: Theme.fill }
    Repeater {
        model: seg.options
        TabButton {
            id: tb
            required property string modelData
            text: modelData
            width: implicitWidth + 20
            height: 30
            contentItem: Text {
                text: tb.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Theme.text
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 7
                color: tb.checked ? (Theme.dark ? "#6e6e73" : "#ffffff") : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animMs } }
            }
        }
    }
}
