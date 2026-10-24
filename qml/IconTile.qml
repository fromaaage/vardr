import QtQuick

// iOS-Settings style: white symbol (icons/<name>.svg) on a colored rounded square
Rectangle {
    property string icon
    property int size: 30
    width: size
    height: size
    radius: size * 0.24
    Image {
        anchors.centerIn: parent
        source: parent.icon ? Qt.resolvedUrl("../icons/" + parent.icon + ".svg") : ""
        sourceSize: Qt.size(parent.size * 0.62, parent.size * 0.62)
        smooth: true
    }
}
