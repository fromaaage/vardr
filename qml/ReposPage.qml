import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: repoPage
    objectName: "repoPage"
    spacing: 12
    property bool dirty: false
    property bool loading: false
    readonly property bool textMode: modeSwitch.currentIndex === 1

    function reload() {
        loading = true
        repoModel.clear()
        for (const r of repoEditor.load())
            repoModel.append(r)
        rawEdit.text = repoEditor.rawText()
        loading = false
        dirty = false
    }
    function items() {
        const out = []
        // Plain objects: ListModel items do not cross over to Python
        for (let i = 0; i < repoModel.count; i++) {
            const e = repoModel.get(i)
            out.push({ name: e.name, active: e.active, siglevel: e.siglevel, key: e.key,
                       source: e.source, directives: e.directives, leading: e.leading })
        }
        return out
    }
    function save() {
        const script = textMode ? repoEditor.prepareRaw(rawEdit.text) : repoEditor.prepare(items())
        if (script)
            Theme.begin(() => actions.saveRepos(script))
    }

    ListModel { id: repoModel }
    Component.onCompleted: reload()

    Connections {
        target: actions
        function onDone(code) { repoPage.reload() }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Segmented {
            id: modeSwitch
            options: ["List", "Text"]
            enabled: !repoPage.dirty
        }
        Item { Layout.fillWidth: true }
        PillButton {
            text: "Rank mirrors"
            filled: false
            enabled: !actions.step
            onClicked: Theme.begin(actions.mirrors)
        }
        PillButton {
            text: "Add"
            filled: false
            visible: !repoPage.textMode
            onClicked: addPopup.open()
        }
        PillButton {
            text: "Revert"
            filled: false
            tint: Theme.danger
            enabled: repoPage.dirty
            onClicked: repoPage.reload()
        }
        PillButton {
            text: "Save & update"
            enabled: repoPage.dirty && !actions.step
            onClicked: repoPage.save()
        }
    }

    Text {
        text: repoPage.dirty ? "Unsaved changes"
            : repoPage.textMode ? "Edit /etc/pacman.conf directly. Checked with pacman-conf before saving."
            : "Top repositories take precedence. Drag ≡ to reorder."
        color: repoPage.dirty ? Theme.accent : Theme.subtext
        font.pixelSize: 13
        font.weight: repoPage.dirty ? Font.DemiBold : Font.Normal
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    Text {
        text: repoEditor.error
        visible: text.length > 0
        color: Theme.danger
        wrapMode: Text.Wrap
        font.pixelSize: 13
        Layout.fillWidth: true
    }

    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: repoPage.textMode ? 1 : 0

        // One grouped card, rows separated by hairlines (iOS list)
        Card {
            clip: true
            ListView {
                id: repoList
                anchors.fill: parent
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                clip: true
                model: repoModel
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                moveDisplaced: Transition { NumberAnimation { properties: "y"; duration: 150 } }
                remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }
                removeDisplaced: Transition { NumberAnimation { properties: "y"; duration: 150 } }

                delegate: Item {
                    id: row
                    required property int index
                    required property string name
                    required property bool active
                    required property string siglevel
                    required property string source
                    required property string key
                    width: repoList.width
                    height: 60

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 52
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.separator
                        visible: row.index < repoModel.count - 1
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: "≡"
                            font.pixelSize: 22
                            color: Theme.subtext
                            Layout.preferredWidth: 32
                            horizontalAlignment: Text.AlignHCenter
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                cursorShape: Qt.SizeVerCursor
                                preventStealing: true
                                onPositionChanged: (mouse) => {
                                    const p = mapToItem(repoList.contentItem, mouse.x, mouse.y)
                                    const to = repoList.indexAt(10, p.y)
                                    if (to >= 0 && to !== row.index) {
                                        repoModel.move(row.index, to, 1)
                                        repoPage.dirty = true
                                    }
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            opacity: row.active ? 1 : 0.45
                            Behavior on opacity { NumberAnimation { duration: Theme.animMs } }
                            Text {
                                text: row.name + (row.key ? "  · key " + row.key : "")
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                color: Theme.text
                            }
                            Text {
                                text: row.source
                                font.family: "monospace"
                                font.pixelSize: 11
                                color: Theme.subtext
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        PilotCombo {
                            readonly property var levels: {
                                const l = repoEditor.sigLevels()
                                return l.indexOf(row.siglevel) < 0 ? l.concat([row.siglevel]) : l
                            }
                            model: levels.map(v => v || "Default SigLevel")
                            currentIndex: levels.indexOf(row.siglevel)
                            Layout.preferredWidth: 220
                            onActivated: (i) => {
                                repoModel.setProperty(row.index, "siglevel", levels[i])
                                repoPage.dirty = true
                            }
                        }
                        PilotSwitch {
                            checked: row.active
                            onToggled: {
                                repoModel.setProperty(row.index, "active", checked)
                                repoPage.dirty = true
                            }
                        }
                        PillButton {
                            text: "✕"
                            filled: false
                            tint: Theme.danger
                            implicitWidth: 34
                            implicitHeight: 34
                            leftPadding: 0
                            rightPadding: 0
                            onClicked: {
                                repoModel.remove(row.index)
                                repoPage.dirty = true
                            }
                        }
                    }
                }
            }
        }

        Card {
            ScrollView {
                anchors.fill: parent
                anchors.margins: 12
                TextArea {
                    id: rawEdit
                    textFormat: TextEdit.PlainText
                    font.family: "monospace"
                    font.pixelSize: 12
                    color: Theme.text
                    selectByMouse: true
                    background: null
                    onTextChanged: if (!repoPage.loading) repoPage.dirty = true
                }
            }
        }
    }

    Popup {
        id: addPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 480
        modal: true
        padding: 22
        background: Rectangle { radius: Theme.radius; color: Theme.card }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMs }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.animMs; easing.type: Easing.OutCubic }
        }
        onOpened: { newName.text = ""; newValue.text = ""; newKey.text = ""; addError.text = ""; newName.forceActiveFocus() }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            Text {
                text: "Add repository"
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Theme.text
                Layout.bottomMargin: 4
            }
            PilotField {
                id: newName
                Layout.fillWidth: true
                placeholderText: "Name, e.g. chaotic-aur"
            }
            RowLayout {
                Layout.fillWidth: true
                PilotCombo {
                    id: newKind
                    model: ["Server", "Include"]
                    Layout.preferredWidth: 110
                }
                PilotField {
                    id: newValue
                    Layout.fillWidth: true
                    placeholderText: newKind.currentIndex === 0
                        ? "https://example.org/$repo/$arch" : "/etc/pacman.d/example-mirrorlist"
                    font.family: "monospace"
                }
            }
            PilotCombo {
                id: newSig
                Layout.fillWidth: true
                readonly property var levels: repoEditor.sigLevels()
                model: levels.map(v => v || "Default SigLevel")
            }
            PilotField {
                id: newKey
                Layout.fillWidth: true
                placeholderText: "Signing key ID (optional, imported on save)"
                font.family: "monospace"
            }
            Text {
                id: addError
                visible: text.length > 0
                color: Theme.danger
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                Item { Layout.fillWidth: true }
                PillButton { text: "Cancel"; filled: false; onClicked: addPopup.close() }
                PillButton {
                    text: "Add"
                    onClicked: {
                        const r = repoEditor.newRepo(newName.text, newKind.currentText,
                                                     newValue.text, newSig.levels[newSig.currentIndex])
                        if (typeof r === "string") {
                            addError.text = r
                            return
                        }
                        r.key = newKey.text.replace(/\s/g, "")
                        repoModel.append(r)
                        repoPage.dirty = true
                        addPopup.close()
                        repoList.positionViewAtEnd()
                    }
                }
            }
        }
    }
}
