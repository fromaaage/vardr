import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: page
    contentWidth: availableWidth

    ColumnLayout {
        width: page.availableWidth
        spacing: 6

        SectionLabel { text: "UPDATE CHECK"; Layout.topMargin: 0 }
        Card {
            Layout.fillWidth: true
            implicitHeight: checkCol.implicitHeight + 12
            ColumnLayout {
                id: checkCol
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 0
                SettingRow {
                    label: "Check for updates"
                    PilotCombo {
                        readonly property var hours: checker.intervals()
                        model: hours.map(h => h === 0 ? "Off" : h === 1 ? "Every hour"
                                            : h === 24 ? "Daily" : "Every " + h + " hours")
                        currentIndex: Math.max(0, hours.indexOf(settings.get("check_interval")))
                        Layout.preferredWidth: 170
                        onActivated: (i) => settings.set("check_interval", hours[i])
                    }
                }
                Separator {}
                SettingRow {
                    label: "Include AUR packages"
                    PilotSwitch {
                        checked: settings.get("check_aur")
                        onToggled: settings.set("check_aur", checked)
                    }
                }
                Separator {}
                SettingRow {
                    label: "Start at login (in tray)"
                    PilotSwitch {
                        checked: settings.get("autostart")
                        onToggled: settings.set("autostart", checked)
                    }
                }
            }
        }
        Footnote { text: "You get a notification only when new updates appear. Closing the window keeps Vardr in the tray." }

        SectionLabel { text: "UPDATE COMMAND" }
        CommandCard {
            key: "update_command"
            rootKey: "update_as_root"
            resetLabel: "Reset to garuda-update"
        }
        Footnote { text: "Runs through bash, so pipes and && work. With the root switch on, leave out sudo (e.g. pacman -Syu)." }

        SectionLabel { text: "FIX COMMAND" }
        CommandCard {
            key: "fix_command"
            rootKey: "fix_as_root"
            resetLabel: "Reset to default"
        }

        SectionLabel { text: "AUR HELPER" }
        Card {
            Layout.fillWidth: true
            implicitHeight: 56
            SettingRow {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                label: "Helper"
                Text {
                    text: (Theme.rev, actions.detectedAurHelper()) ? "" : "not installed"
                    color: Theme.danger
                    font.pixelSize: 13
                }
                PilotCombo {
                    readonly property var keys: ["auto", "paru", "yay"]
                    model: ["Automatic", "paru", "yay"]
                    currentIndex: Math.max(0, keys.indexOf(settings.get("aur_helper")))
                    Layout.preferredWidth: 140
                    onActivated: (i) => settings.set("aur_helper", keys[i])
                }
            }
        }

        SectionLabel { text: "CACHE" }
        Card {
            Layout.fillWidth: true
            implicitHeight: 56
            SettingRow {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                label: "Versions to keep per package"
                PilotCombo {
                    model: [1, 2, 3]
                    currentIndex: settings.get("cache_keep") - 1
                    Layout.preferredWidth: 80
                    onActivated: (i) => settings.set("cache_keep", i + 1)
                }
            }
        }
        Footnote { text: "Uninstalled packages are always removed. Applies to pacman and AUR build caches." }
        Text {
            text: "Vardr " + Qt.application.version
            font.pixelSize: 12
            color: Theme.subtext
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 24
            Layout.bottomMargin: 12
        }
    }

    component Footnote: Text {
        wrapMode: Text.Wrap
        font.pixelSize: 12
        color: Theme.subtext
        leftPadding: 16
        rightPadding: 16
        Layout.fillWidth: true
    }

    // Command text field + root switch + reset, for update and fix
    component CommandCard: Card {
        id: cc
        property string key
        property string rootKey
        property string resetLabel
        Layout.fillWidth: true
        implicitHeight: ccCol.implicitHeight + 24
        ColumnLayout {
            id: ccCol
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            spacing: 8
            PilotField {
                id: field
                Layout.fillWidth: true
                text: settings.get(cc.key)
                font.family: "monospace"
                onEditingFinished: settings.set(cc.key, text)
            }
            SettingRow {
                label: "Run as root (password dialog)"
                PilotSwitch {
                    checked: settings.get(cc.rootKey)
                    onToggled: settings.set(cc.rootKey, checked)
                }
            }
            Separator {}
            LinkText {
                text: cc.resetLabel
                font.pixelSize: 15
                Layout.topMargin: 4
                onClicked: {
                    settings.reset(cc.key)
                    field.text = settings.get(cc.key)
                }
            }
        }
    }
}
