import QtQuick

Text {
    id: lt
    signal clicked()
    font.pixelSize: 13
    color: Theme.accent
    opacity: area.containsMouse ? 0.7 : 1
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: lt.clicked()
    }
}
