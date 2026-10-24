pragma Singleton
import QtQuick

// Colors (iOS system palette) and app-wide UI state shared by all pages.
QtObject {
    // Appearance: the in-app choice is kept only while the desktop stays in the
    // mode it had when the choice was made; a desktop change always wins.
    readonly property bool desktopDark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    property bool dark: desktopDark

    Component.onCompleted: {
        const desk = desktopDark ? "dark" : "light"
        const choice = settings.get("appearance")
        dark = choice && settings.get("appearance_desktop") === desk ? choice === "dark" : desktopDark
        if (settings.get("appearance_desktop") !== desk)
            settings.set("appearance", "")
        settings.set("appearance_desktop", desk)
    }
    onDesktopDarkChanged: {
        dark = desktopDark
        settings.set("appearance", "")
        settings.set("appearance_desktop", desktopDark ? "dark" : "light")
    }

    function toggleDark() {
        dark = !dark
        settings.set("appearance", dark ? "dark" : "light")
    }

    readonly property color bg: dark ? "#000000" : "#f2f2f7"
    readonly property color sidebar: dark ? "#1c1c1e" : "#e9e9ee"
    readonly property color card: dark ? "#1c1c1e" : "#ffffff"
    readonly property color fill: dark ? "#2c2c2e" : "#e9e9ee"      // inputs, segmented
    readonly property color separator: dark ? "#38383a" : "#d1d1d6"
    readonly property color text: dark ? "#ffffff" : "#000000"
    readonly property color subtext: "#8e8e93"
    readonly property color accent: dark ? "#ff2bd6" : "#d4149f"  // brand magenta, darker in light mode for contrast
    readonly property color danger: "#ff453a"
    readonly property color success: dark ? "#30d158" : "#34c759"
    readonly property color orange: "#ff9f0a"
    readonly property color purple: "#bf5af2"
    readonly property color teal: "#40c8e0"
    readonly property int radius: 14
    readonly property int animMs: 180

    property int page: 0
    property string status: ""
    property bool statusOk: true
    property int rev: 0  // bumped on settings change so bindings re-read values

    readonly property Connections _settings: Connections {
        target: settings
        function onChanged() { rev++ }
    }
    readonly property Connections _done: Connections {
        target: actions
        function onDone(code) {
            statusOk = code === 0
            status = code === 0 ? "Done" : "Finished with exit code " + code
        }
    }

    // Start an action on the Maintenance page with a fresh log
    function begin(action) {
        page = 0
        runner.clear()
        status = ""
        action()
    }

    function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s") }
}
