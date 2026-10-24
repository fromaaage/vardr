import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Terminal output; rows are updated in place (progress bars, pacman downloads)
Card {
    id: lv
    ListModel { id: rows }

    Connections {
        target: runner
        function onCleared() { rows.clear() }
        function onRowChanged(i, html) {
            while (rows.count < i)
                rows.append({ line: "" })
            if (i < rows.count)
                rows.setProperty(i, "line", html)
            else
                rows.append({ line: html })
            if (list.atEnd)
                Qt.callLater(list.positionViewAtEnd)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        TextMetrics {
            id: charSize
            font.family: "monospace"
            font.pixelSize: 12
            text: "M"
        }

        ListView {
            id: list
            onWidthChanged: if (width > 0) runner.setColumns(Math.floor((width - 16) / charSize.advanceWidth))
            // Follow the output unless the user scrolled up
            property bool atEnd: true
            onMovementEnded: atEnd = atYEnd
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: rows
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Text {
                required property string line
                width: ListView.view.width - 12
                text: '<div style="white-space:pre-wrap;">' + line + '</div>'
                textFormat: Text.RichText
                wrapMode: Text.WrapAnywhere
                font.family: "monospace"
                font.pixelSize: 12
                color: Theme.text
            }
            Text {
                anchors.centerIn: parent
                visible: rows.count === 0
                text: "Output appears here."
                color: Theme.subtext
                font.pixelSize: 13
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: rows.count > 0
            Text {
                text: runner.running ? "Running…" : Theme.status
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: runner.running ? Theme.subtext : Theme.statusOk ? Theme.success : Theme.danger
                Layout.fillWidth: true
            }
            PillButton {
                text: copied.running ? "Copied" : "Copy log"
                filled: false
                implicitHeight: 30
                font.pixelSize: 13
                onClicked: {
                    clip.text = runner.plainText()
                    clip.selectAll()
                    clip.copy()
                    copied.restart()
                }
                Timer { id: copied; interval: 1500 }
            }
        }
    }
    TextEdit { id: clip; visible: false }
}
