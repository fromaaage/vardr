import QtQuick
import QtQuick.Controls

// Rounded pop-up button with chevron, menu styled like an iOS context menu
ComboBox {
    id: cb
    implicitHeight: 34
    leftPadding: 12
    rightPadding: 30
    font.pixelSize: 14
    contentItem: Text {
        text: cb.displayText
        font: cb.font
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: cb.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        text: "⌄"
        font.pixelSize: 16
        color: Theme.subtext
    }
    background: Rectangle {
        radius: 8
        color: Theme.fill
        opacity: cb.enabled ? (cb.hovered ? 0.85 : 1) : 0.5
    }
    delegate: ItemDelegate {
        id: d
        required property int index
        required property var modelData
        width: ListView.view.width
        height: 34
        contentItem: Text {
            text: (cb.currentIndex === d.index ? "✓  " : "    ") + d.modelData
            font: cb.font
            color: Theme.text
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 6
            color: d.highlighted || d.hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : "transparent"
        }
        highlighted: cb.highlightedIndex === index
    }
    popup: Popup {
        y: cb.height + 4
        width: Math.max(cb.width, 180)
        padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 320)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: cb.popup.visible ? cb.delegateModel : null
            currentIndex: cb.highlightedIndex
        }
        background: Rectangle {
            radius: 10
            color: Theme.dark ? "#2c2c2e" : "#ffffff"
            border.color: Theme.separator
        }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
