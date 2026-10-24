import QtQuick
import QtQuick.Layouts

// One row of a grouped settings card: label left, control right
RowLayout {
    property alias label: lbl.text
    Layout.fillWidth: true
    Layout.minimumHeight: 44
    spacing: 10
    Text {
        id: lbl
        color: Theme.text
        font.pixelSize: 15
        Layout.fillWidth: true
        elide: Text.ElideRight
    }
}
