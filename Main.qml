import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 900
    height: 680
    minimumWidth: 780
    minimumHeight: 480
    visible: true
    title: "Garuda Pilot"

    readonly property bool dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    readonly property color bg: dark ? "#000000" : "#f2f2f7"
    readonly property color card: dark ? "#1c1c1e" : "#ffffff"
    readonly property color text: dark ? "#ffffff" : "#000000"
    readonly property color subtext: "#8e8e93"
    readonly property color accent: "#0a84ff"
    readonly property color danger: "#ff453a"
    readonly property color success: "#30d158"

    property string status: ""
    property bool statusOk: true
    property int rev: 0   // bumped on settings change to refresh bindings
    property alias currentTab: tabs.currentIndex

    function begin(action) {
        log.clear()
        status = ""
        action()
    }

    color: bg

    Connections {
        target: settings
        function onChanged() { win.rev++ }
    }

    Connections {
        target: runner
        function onLineAdded(line) { log.append(line) }
    }

    Connections {
        target: actions
        function onDone(code) {
            win.statusOk = code === 0
            win.status = code === 0 ? "Done" : "Finished with exit code " + code
        }
    }

    component PillButton: Button {
        id: pb
        property color tint: win.accent
        property bool filled: true
        implicitHeight: 40
        leftPadding: 20
        rightPadding: 20
        font.pixelSize: 15
        font.weight: Font.DemiBold
        contentItem: Text {
            text: pb.text
            font: pb.font
            color: pb.filled ? "white" : pb.tint
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: height / 2
            color: pb.filled ? pb.tint : Qt.rgba(pb.tint.r, pb.tint.g, pb.tint.b, 0.15)
            opacity: pb.enabled ? (pb.down ? 0.7 : 1) : 0.4
        }
    }

    component Card: Rectangle {
        color: win.card
        radius: 14
    }

    component Segmented: TabBar {
        id: seg
        property var options: []
        background: Rectangle { radius: 9; color: win.dark ? "#2c2c2e" : "#e3e3e8" }
        Repeater {
            model: seg.options
            TabButton {
                id: tb
                required property string modelData
                text: modelData
                width: implicitWidth + 16
                contentItem: Text {
                    text: tb.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: win.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 7
                    color: tb.checked ? (win.dark ? "#636366" : "#ffffff") : "transparent"
                }
            }
        }
    }

    component ActionCard: Card {
        id: ac
        property string title
        property string detail
        property string button
        signal triggered()
        Layout.fillWidth: true
        implicitHeight: 72
        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: ac.title
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: win.text
                }
                Label {
                    text: ac.detail
                    font.family: "monospace"
                    font.pixelSize: 12
                    color: win.subtext
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            PillButton {
                text: ac.button
                filled: false
                enabled: !actions.step
                onClicked: ac.triggered()
            }
        }
    }

    header: Item {
        implicitHeight: 64
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            Label {
                text: ["Maintenance", "Repositories", "Settings"][tabs.currentIndex]
                font.pixelSize: 28
                font.weight: Font.Bold
                color: win.text
                Layout.fillWidth: true
            }
            Segmented {
                id: tabs
                options: ["Maintenance", "Repositories", "Settings"]
            }
        }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: 24
        anchors.topMargin: 4
        currentIndex: tabs.currentIndex

        // ---------------- Maintenance ----------------
        ColumnLayout {
            spacing: 16

            // Hero: everything in one click
            Card {
                Layout.fillWidth: true
                implicitHeight: 92
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            text: actions.step || "Update everything"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            color: win.text
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "System update → AUR → Clean cache"
                            font.pixelSize: 13
                            color: win.subtext
                        }
                    }
                    PillButton {
                        text: "Stop"
                        visible: runner.running
                        filled: false
                        tint: win.danger
                        onClicked: runner.stop()
                    }
                    PillButton {
                        text: "Update all"
                        implicitHeight: 48
                        font.pixelSize: 17
                        enabled: !actions.step
                        onClicked: win.begin(actions.updateAll)
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 16
                ActionCard {
                    title: "System update"
                    detail: (win.rev, settings.get("update_command"))
                    button: "Update"
                    onTriggered: win.begin(actions.update)
                }
                ActionCard {
                    title: "AUR"
                    detail: (win.rev, actions.detectedAurHelper() || "no helper found") + " -Sua"
                    button: "Update"
                    onTriggered: win.begin(actions.aur)
                }
                ActionCard {
                    title: "Cache"
                    detail: "keep " + (win.rev, settings.get("cache_keep")) + " versions"
                    button: "Clean"
                    onTriggered: win.begin(actions.cleanCache)
                }
                ActionCard {
                    title: "Garuda fix"
                    detail: (win.rev, settings.isDefault("fix_command")) ? "garuda-health --fix → limine-update" : settings.get("fix_command")
                    button: "Run"
                    onTriggered: win.begin(actions.fix)
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6
                    ScrollView {
                        id: scroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        TextArea {
                            id: log
                            readOnly: true
                            textFormat: TextEdit.RichText
                            wrapMode: TextEdit.Wrap
                            font.family: "monospace"
                            font.pixelSize: 12
                            color: win.text
                            selectByMouse: true
                            background: null
                            placeholderText: "Output appears here."
                            placeholderTextColor: win.subtext
                            onTextChanged: cursorPosition = length
                        }
                    }
                    Label {
                        text: runner.currentLine
                        textFormat: Text.RichText
                        visible: text.length > 0
                        font.family: "monospace"
                        font.pixelSize: 12
                        color: win.text
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Label {
                        text: win.status
                        visible: text.length > 0 && !runner.running
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: win.statusOk ? win.success : win.danger
                    }
                }
            }

            // Answer bar for questions from pacman/paru
            Card {
                Layout.fillWidth: true
                visible: runner.prompt.length > 0
                implicitHeight: 64
                border.color: win.accent
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    Label {
                        text: "Answer needed"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: win.accent
                    }
                    TextField {
                        id: answer
                        Layout.fillWidth: true
                        placeholderText: "Custom answer"
                        color: win.text
                        placeholderTextColor: win.subtext
                        background: Rectangle { radius: 8; color: win.dark ? "#2c2c2e" : "#e9e9ee" }
                        onAccepted: { runner.send(text); text = "" }
                    }
                    PillButton { text: "Send"; filled: false; onClicked: { runner.send(answer.text); answer.text = "" } }
                    PillButton { text: "Default"; filled: false; onClicked: runner.send("") }
                    PillButton { text: "No"; filled: false; tint: win.danger; onClicked: runner.send("n") }
                    PillButton { text: "Yes"; onClicked: runner.send("y") }
                }
            }
        }

        // ---------------- Repositories ----------------
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
                    onClicked: {
                        tabs.currentIndex = 0
                        win.begin(actions.mirrors)
                    }
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
                    tint: win.danger
                    enabled: repoPage.dirty
                    onClicked: repoPage.reload()
                }
                PillButton {
                    text: "Save & update"
                    enabled: repoPage.dirty && !actions.step
                    onClicked: {
                        const script = repoPage.textMode ? repoEditor.prepareRaw(rawEdit.text)
                                                         : repoEditor.prepare(repoPage.items())
                        if (!script)
                            return
                        tabs.currentIndex = 0
                        win.begin(() => actions.saveRepos(script))
                    }
                }
            }

            Label {
                text: repoPage.dirty ? "Unsaved changes"
                    : repoPage.textMode ? "Edit /etc/pacman.conf directly. Checked with pacman-conf before saving."
                    : "Top repositories take precedence. Drag ≡ to reorder."
                color: repoPage.dirty ? win.accent : win.subtext
                font.pixelSize: 13
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Label {
                text: repoEditor.error
                visible: text.length > 0
                color: win.danger
                wrapMode: Text.Wrap
                font.pixelSize: 13
                Layout.fillWidth: true
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: repoPage.textMode ? 1 : 0

                ListView {
                    id: repoList
                    clip: true
                    spacing: 8
                    model: repoModel
                    moveDisplaced: Transition { NumberAnimation { properties: "y"; duration: 150 } }

                    delegate: Card {
                        id: row
                        required property int index
                        required property string name
                        required property bool active
                        required property string siglevel
                        required property string source
                        required property string key
                        width: repoList.width
                        height: 60
                        opacity: active ? 1 : 0.55

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 14
                            spacing: 10

                            Label {
                                text: "≡"
                                font.pixelSize: 22
                                color: win.subtext
                                Layout.preferredWidth: 28
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
                                Label {
                                    text: row.name + (row.key ? "  · key " + row.key : "")
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    color: win.text
                                }
                                Label {
                                    text: row.source
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    color: win.subtext
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            ComboBox {
                                id: sig
                                readonly property var levels: {
                                    const l = repoEditor.sigLevels()
                                    return l.indexOf(row.siglevel) < 0 ? l.concat([row.siglevel]) : l
                                }
                                model: levels.map(v => v || "Default SigLevel")
                                currentIndex: levels.indexOf(row.siglevel)
                                Layout.preferredWidth: 210
                                onActivated: (i) => {
                                    repoModel.setProperty(row.index, "siglevel", levels[i])
                                    repoPage.dirty = true
                                }
                            }
                            Switch {
                                checked: row.active
                                onToggled: {
                                    repoModel.setProperty(row.index, "active", checked)
                                    repoPage.dirty = true
                                }
                            }
                            PillButton {
                                text: "✕"
                                filled: false
                                tint: win.danger
                                leftPadding: 14
                                rightPadding: 14
                                onClicked: {
                                    repoModel.remove(row.index)
                                    repoPage.dirty = true
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
                            color: win.text
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
                width: 460
                modal: true
                padding: 20
                background: Rectangle { radius: 14; color: win.card }
                onOpened: { newName.text = ""; newValue.text = ""; newKey.text = ""; addError.text = "" }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10
                    Label {
                        text: "Add repository"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: win.text
                    }
                    TextField {
                        id: newName
                        Layout.fillWidth: true
                        placeholderText: "Name, e.g. chaotic-aur"
                        color: win.text
                        placeholderTextColor: win.subtext
                        background: Rectangle { radius: 8; color: win.dark ? "#2c2c2e" : "#e9e9ee" }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        ComboBox {
                            id: newKind
                            model: ["Server", "Include"]
                        }
                        TextField {
                            id: newValue
                            Layout.fillWidth: true
                            placeholderText: newKind.currentIndex === 0
                                ? "https://example.org/$repo/$arch" : "/etc/pacman.d/example-mirrorlist"
                            font.family: "monospace"
                            color: win.text
                            placeholderTextColor: win.subtext
                            background: Rectangle { radius: 8; color: win.dark ? "#2c2c2e" : "#e9e9ee" }
                        }
                    }
                    ComboBox {
                        id: newSig
                        Layout.fillWidth: true
                        readonly property var levels: repoEditor.sigLevels()
                        model: levels.map(v => v || "Default SigLevel")
                    }
                    TextField {
                        id: newKey
                        Layout.fillWidth: true
                        placeholderText: "Signing key ID (optional, imported on save)"
                        font.family: "monospace"
                        color: win.text
                        placeholderTextColor: win.subtext
                        background: Rectangle { radius: 8; color: win.dark ? "#2c2c2e" : "#e9e9ee" }
                    }
                    Label {
                        id: addError
                        visible: text.length > 0
                        color: win.danger
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
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

        // ---------------- Settings ----------------
        ScrollView {
            id: settingsScroll
            contentWidth: availableWidth
            ColumnLayout {
                width: settingsScroll.availableWidth
                spacing: 8
                Label {
                    text: "UPDATE COMMAND"
                    font.pixelSize: 12
                    color: win.subtext
                    leftPadding: 16
                }
                Card {
                    Layout.fillWidth: true
                    implicitHeight: col.implicitHeight + 28
                    ColumnLayout {
                        id: col
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                        TextField {
                            id: cmd
                            Layout.fillWidth: true
                            text: settings.get("update_command")
                            font.family: "monospace"
                            color: win.text
                            background: Rectangle { radius: 8; color: win.dark ? "#2c2c2e" : "#e9e9ee" }
                            onEditingFinished: settings.set("update_command", text)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Run as root (password dialog)"
                                color: win.text
                                font.pixelSize: 15
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: settings.get("update_as_root")
                                onToggled: settings.set("update_as_root", checked)
                            }
                        }
                        PillButton {
                            text: "Reset to garuda-update"
                            filled: false
                            onClicked: { settings.reset("update_command"); cmd.text = settings.get("update_command") }
                        }
                    }
                }
                Label {
                    text: "Runs through bash, so pipes and && work. With the root switch on, leave out sudo (e.g. pacman -Syu)."
                    wrapMode: Text.Wrap
                    font.pixelSize: 12
                    color: win.subtext
                    leftPadding: 16
                    Layout.fillWidth: true
                }

                Label {
                    text: "FIX COMMAND"
                    font.pixelSize: 12
                    color: win.subtext
                    leftPadding: 16
                    Layout.topMargin: 16
                }
                Card {
                    Layout.fillWidth: true
                    implicitHeight: fixCol.implicitHeight + 28
                    ColumnLayout {
                        id: fixCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                        TextField {
                            id: fixCmd
                            Layout.fillWidth: true
                            text: settings.get("fix_command")
                            font.family: "monospace"
                            color: win.text
                            background: Rectangle { radius: 8; color: win.dark ? "#2c2c2e" : "#e9e9ee" }
                            onEditingFinished: settings.set("fix_command", text)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Run as root (password dialog)"
                                color: win.text
                                font.pixelSize: 15
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: settings.get("fix_as_root")
                                onToggled: settings.set("fix_as_root", checked)
                            }
                        }
                        PillButton {
                            text: "Reset to default"
                            filled: false
                            onClicked: { settings.reset("fix_command"); fixCmd.text = settings.get("fix_command") }
                        }
                    }
                }

                Label {
                    text: "AUR HELPER"
                    font.pixelSize: 12
                    color: win.subtext
                    leftPadding: 16
                    Layout.topMargin: 16
                }
                Card {
                    Layout.fillWidth: true
                    implicitHeight: 56
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        Label {
                            text: "Helper"
                            color: win.text
                            font.pixelSize: 15
                            Layout.fillWidth: true
                        }
                        Label {
                            text: (win.rev, actions.detectedAurHelper()) ? "" : "not installed"
                            color: win.danger
                            font.pixelSize: 13
                        }
                        ComboBox {
                            readonly property var keys: ["auto", "paru", "yay"]
                            model: ["Automatic", "paru", "yay"]
                            currentIndex: Math.max(0, keys.indexOf(settings.get("aur_helper")))
                            onActivated: (i) => settings.set("aur_helper", keys[i])
                        }
                    }
                }

                Label {
                    text: "CACHE"
                    font.pixelSize: 12
                    color: win.subtext
                    leftPadding: 16
                    Layout.topMargin: 16
                }
                Card {
                    Layout.fillWidth: true
                    implicitHeight: 56
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        Label {
                            text: "Versions to keep per package"
                            color: win.text
                            font.pixelSize: 15
                            Layout.fillWidth: true
                        }
                        ComboBox {
                            model: [1, 2, 3]
                            currentIndex: settings.get("cache_keep") - 1
                            onActivated: (i) => settings.set("cache_keep", i + 1)
                        }
                    }
                }
                Label {
                    text: "Uninstalled packages are always removed. Applies to pacman and AUR build caches."
                    wrapMode: Text.Wrap
                    font.pixelSize: 12
                    color: win.subtext
                    leftPadding: 16
                    Layout.fillWidth: true
                }
                Item { implicitHeight: 8 }
            }
        }
    }
}
