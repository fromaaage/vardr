import QtQuick
import QtQuick.Controls

Button {
    id: pb
    property color tint: Theme.accent
    property bool filled: true
    implicitHeight: 38
    leftPadding: 18
    rightPadding: 18
    font.pixelSize: 15
    font.weight: Font.DemiBold
    scale: down ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
    contentItem: Text {
        text: pb.text
        font: pb.font
        color: pb.filled ? "white" : pb.tint
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: height / 2
        color: pb.filled ? pb.tint : Qt.rgba(pb.tint.r, pb.tint.g, pb.tint.b, Theme.dark ? 0.22 : 0.13)
        opacity: pb.enabled ? (pb.hovered && !pb.down ? 0.88 : 1) : 0.4
        Behavior on opacity { NumberAnimation { duration: Theme.animMs } }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
