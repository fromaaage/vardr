import QtQuick
import QtQuick.Controls

// iOS-style switch: green track, white knob
Switch {
    id: sw
    implicitWidth: 51
    implicitHeight: 31
    padding: 0
    indicator: Rectangle {
        implicitWidth: 51
        implicitHeight: 31
        radius: height / 2
        color: sw.checked ? Theme.success : (Theme.dark ? "#48484a" : "#e9e9eb")
        opacity: sw.enabled ? 1 : 0.5
        Behavior on color { ColorAnimation { duration: Theme.animMs } }
        Rectangle {
            width: 27
            height: 27
            radius: 13.5
            y: 2
            x: sw.checked ? parent.width - width - 2 : 2
            color: "white"
            border.color: Qt.rgba(0, 0, 0, 0.06)
            Behavior on x { NumberAnimation { duration: Theme.animMs; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Item {}
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
