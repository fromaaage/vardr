import QtQuick
import QtQuick.Controls

TextField {
    implicitHeight: 36
    leftPadding: 12
    rightPadding: 12
    font.pixelSize: 14
    color: Theme.text
    placeholderTextColor: Theme.subtext
    selectByMouse: true
    background: Rectangle {
        radius: 8
        color: Theme.fill
        border.width: parent.activeFocus ? 2 : 0
        border.color: Theme.accent
    }
}
