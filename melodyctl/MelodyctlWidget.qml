import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    popoutWidth: 320
    popoutHeight: 0

    ccWidgetIcon: "headset"
    ccWidgetPrimaryText: "Enco Buds"
    ccWidgetSecondaryText: root.pillText
    ccWidgetIsActive: root.connected

    // --- melodyctl CLI resolution -------------------------------------------
    // Order: explicit override (setting) -> `melodyctl` on PATH -> dev fallback.
    readonly property string devFallback: "/home/chirag/stuff/melodyctl/melodyctl.py"
    readonly property string installHint: "uv tool install --python /usr/bin/python3 git+https://github.com/chiragverma11/melodyctl"

    // `command` is the forward setting; `scriptPath` is read as a legacy fallback.
    property string commandOverride: PluginService.loadPluginData("melodyctl", "command",
            PluginService.loadPluginData("melodyctl", "scriptPath", ""))
    property int pollInterval: parseInt(PluginService.loadPluginData("melodyctl", "pollInterval", "120"), 10)

    property string cliPath: ""
    property bool cliIsScript: false
    property bool cliChecked: false
    property bool cliAvailable: false
    property string cliVersion: ""
    property string cliError: ""

    property int leftLevel: -1
    property int rightLevel: -1
    property int caseLevel: -1
    property bool connected: false
    property string lastError: ""
    property string status: ""

    property var gestureRows: []
    property string gameMode: "unknown"

    readonly property bool hasData: leftLevel >= 0 || rightLevel >= 0 || caseLevel >= 0
    readonly property string leftCell: leftLevel < 0 ? "–" : String(leftLevel)
    readonly property string rightCell: rightLevel < 0 ? "–" : String(rightLevel)
    readonly property string caseCell: caseLevel < 0 ? "–" : String(caseLevel)
    readonly property string pillText: !cliAvailable
        ? (cliChecked ? "setup" : "…")
        : (hasData ? leftCell + "·" + rightCell + "·" + caseCell : "--")

    // Resolve the CLI in one shell probe: honour an override, else PATH, else dev path.
    readonly property string resolveScript: [
        'if [ -n "$1" ]; then',
        '  if command -v "$1" >/dev/null 2>&1 || [ -f "$1" ]; then printf "%s" "$1"; exit 0; fi',
        '  printf "MISSING_OVERRIDE"; exit 0',
        'fi',
        'if command -v melodyctl >/dev/null 2>&1; then printf "%s" "$(command -v melodyctl)"; exit 0; fi',
        'if [ -x "$HOME/.local/bin/melodyctl" ]; then printf "%s" "$HOME/.local/bin/melodyctl"; exit 0; fi',
        'if [ -f "$2" ]; then printf "%s" "$2"; exit 0; fi',
        'printf "NONE"'
    ].join("\n")

    function cliArgs(rest) {
        const base = root.cliIsScript ? ["python3", root.cliPath] : [root.cliPath];
        return base.concat(rest);
    }

    function resolveCli() {
        if (resolveProcess.running)
            return;
        resolveProcess.command = ["sh", "-c", root.resolveScript, "sh", root.commandOverride, root.devFallback];
        resolveProcess.running = true;
    }

    function ensureCli() {
        if (!root.cliChecked && !resolveProcess.running)
            root.resolveCli();
    }

    function onResolved(result) {
        root.cliChecked = true;
        if (result === "" || result === "NONE" || result === "MISSING_OVERRIDE") {
            root.cliAvailable = false;
            root.cliPath = "";
            root.cliError = result === "MISSING_OVERRIDE"
                ? "melodyctl not found at the configured command/path"
                : "melodyctl CLI not found";
            return;
        }
        root.cliPath = result;
        root.cliIsScript = result.endsWith(".py");
        root.cliAvailable = true;
        root.cliError = "";
        root.checkVersion();
        root.refresh();
        root.loadGestures();
    }

    function checkVersion() {
        if (versionProcess.running)
            return;
        versionProcess.command = root.cliArgs(["--version"]);
        versionProcess.running = true;
    }

    function levelText(value) {
        return value < 0 ? "--" : value + "%";
    }

    function gestureSummary(ear) {
        const rows = root.gestureRows.filter(r => r.ear === ear && r.action >= 1 && r.action <= 4);
        return rows.map(r => r.action_name + ": " + r.function_name).join("   ");
    }

    Component.onCompleted: root.resolveCli()

    Connections {
        target: PluginService
        ignoreUnknownSignals: true

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== "melodyctl")
                return;
            root.commandOverride = PluginService.loadPluginData("melodyctl", "command",
                    PluginService.loadPluginData("melodyctl", "scriptPath", ""));
            root.pollInterval = parseInt(PluginService.loadPluginData("melodyctl", "pollInterval", "120"), 10);
            root.cliChecked = false;
            root.cliAvailable = false;
            root.resolveCli();
        }
    }

    Timer {
        interval: Math.max(15, root.pollInterval) * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: resolveProcess

        stdout: StdioCollector {
            onStreamFinished: root.onResolved(text.trim())
        }
    }

    Process {
        id: versionProcess

        stdout: StdioCollector {
            onStreamFinished: root.cliVersion = text.trim().replace("melodyctl ", "")
        }
        stderr: StdioCollector {}
    }

    Process {
        id: batteryProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim());
                    root.leftLevel = data.left ?? -1;
                    root.rightLevel = data.right ?? -1;
                    root.caseLevel = data.case ?? -1;
                    root.connected = true;
                    root.lastError = "";
                } catch (e) {
                    root.connected = false;
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.lastError = text.trim();
            }
        }
    }

    Process {
        id: gestureProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.gestureRows = JSON.parse(text.trim());
                } catch (e) {
                    root.gestureRows = [];
                }
            }
        }
    }

    Process {
        id: controlProcess

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.status = text.trim();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.status = text.trim();
            }
        }
    }

    function refresh() {
        if (!root.cliAvailable) {
            root.ensureCli();
            return;
        }
        if (batteryProcess.running)
            return;
        batteryProcess.command = root.cliArgs(["battery", "--json"]);
        batteryProcess.running = true;
    }

    function loadGestures() {
        if (!root.cliAvailable)
            return;
        if (gestureProcess.running)
            return;
        gestureProcess.command = root.cliArgs(["gestures", "--json"]);
        gestureProcess.running = true;
    }

    function runControl(args) {
        if (!root.cliAvailable)
            return;
        if (controlProcess.running)
            return;
        controlProcess.command = root.cliArgs(args);
        controlProcess.running = true;
    }

    component BatteryRow: StyledRect {
        id: row

        required property string label
        required property int value

        width: root.popoutWidth - Theme.spacingL * 2
        height: 44
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingM

            DankIcon {
                name: Theme.getBatteryIcon(row.value, false, row.value >= 0)
                size: 20
                color: Theme.primary
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: row.label
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: root.levelText(row.value)
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: row.value >= 0 && row.value <= 20 ? Theme.error : Theme.surfaceText
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    component ActionButton: StyledRect {
        id: btn

        required property string label
        property bool accent: false
        signal clicked()

        width: Math.max(64, labelText.implicitWidth + Theme.spacingM * 2)
        height: 30
        radius: Theme.cornerRadius
        color: accent ? Theme.primary : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

        StyledText {
            id: labelText
            anchors.centerIn: parent
            text: btn.label
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        MouseArea {
            anchors.fill: parent
            onClicked: btn.clicked()
        }
    }

    horizontalBarPill: Component {
        RowLayout {
            spacing: Theme.spacingXS

            DankIcon {
                name: "headset"
                size: root.iconSize
                color: Theme.widgetIconColor || Theme.primary
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: root.pillText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.Medium
                color: Theme.widgetTextColor || Theme.surfaceText
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "headset"
            size: root.iconSize
            color: Theme.widgetIconColor || Theme.primary
            anchors.centerIn: parent
        }
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "OPPO Enco Buds"
            detailsText: !root.cliAvailable
                ? (root.cliError !== "" ? root.cliError : "melodyctl CLI not found")
                : root.connected ? (root.status !== "" ? root.status : "Live battery + controls")
                                 : (root.lastError !== "" ? root.lastError : "Earbuds not connected")
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingS
                topPadding: Theme.spacingS
                bottomPadding: Theme.spacingS

                StyledText {
                    width: parent.width
                    visible: root.cliChecked && !root.cliAvailable
                    text: "The melodyctl CLI is required. Install it with:\n\n    " + root.installHint
                        + "\n\nOr set a custom command / script path in this plugin's settings."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                BatteryRow {
                    label: "Left"
                    value: root.leftLevel
                }

                BatteryRow {
                    label: "Right"
                    value: root.rightLevel
                }

                BatteryRow {
                    label: "Case"
                    value: root.caseLevel
                }

                StyledText {
                    width: parent.width
                    visible: root.cliAvailable && root.cliVersion !== ""
                    text: "melodyctl " + root.cliVersion
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    width: parent.width
                    topPadding: Theme.spacingS
                    text: "Game mode"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceVariantText
                }

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    ActionButton {
                        label: "Game mode ON"
                        accent: root.gameMode === "on"
                        onClicked: {
                            root.gameMode = "on";
                            root.runControl(["game", "on"]);
                        }
                    }

                    ActionButton {
                        label: "OFF"
                        accent: root.gameMode === "off"
                        onClicked: {
                            root.gameMode = "off";
                            root.runControl(["game", "off"]);
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    topPadding: Theme.spacingS
                    text: "Triple-tap action"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceVariantText
                }

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingS

                    ActionButton {
                        label: "Voice assistant"
                        onClicked: root.runControl(["gesture-set", "4", "1", "3", "3"])
                    }

                    ActionButton {
                        label: "Game mode"
                        onClicked: root.runControl(["gesture-set", "4", "1", "3", "17"])
                    }
                }

                StyledText {
                    width: parent.width
                    topPadding: Theme.spacingS
                    text: "Touch gestures"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    width: parent.width
                    visible: root.gestureRows.length > 0
                    text: "L:  " + root.gestureSummary("left")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    width: parent.width
                    visible: root.gestureRows.length > 0
                    text: "R:  " + root.gestureSummary("right")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                }

                ActionButton {
                    label: "Refresh gestures"
                    onClicked: root.loadGestures()
                }
            }
        }
    }
}
