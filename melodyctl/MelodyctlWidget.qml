import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services
import "errfmt.js" as ErrFmt

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
    property string status: ""

    // Friendly error state derived from CLI stderr (see errfmt.js). The raw text
    // is kept in errorDetail for the (bounded) details box; the header only ever
    // shows the short errorTitle.
    property string errorTitle: ""
    property string errorHint: ""
    property string errorDetail: ""
    property string errorCode: ""
    property bool errorTransient: false

    function setError(raw) {
        const info = ErrFmt.humanize(raw);
        root.errorTitle = info.title;
        root.errorHint = info.hint;
        root.errorDetail = info.detail;
        root.errorCode = info.code;
        root.errorTransient = info.transient;
    }

    function clearError() {
        root.errorTitle = "";
        root.errorHint = "";
        root.errorDetail = "";
        root.errorCode = "";
        root.errorTransient = false;
    }

    // --- serialized CLI runner (one RFCOMM connection at a time) -------------
    // The buds accept a single RFCOMM connection, so every melodyctl call goes
    // through one queue rather than racing separate Process objects (which is
    // what produced spurious "Device or resource busy").
    property var cliQueue: []
    property bool cliBusy: false
    property var cliCurrent: null
    property string cliOut: ""
    property string cliErr: ""

    function runCli(args, onDone) {
        if (!root.cliAvailable) {
            root.ensureCli();
            return;
        }
        const key = args.join(" ");
        if (root.cliCurrent && root.cliCurrent.key === key)
            return;                                   // same request already running
        for (let i = 0; i < root.cliQueue.length; ++i)
            if (root.cliQueue[i].key === key)
                return;                               // same request already queued
        root.cliQueue = root.cliQueue.concat([{ args: args, key: key, onDone: onDone }]);
        root.pumpCli();
    }

    function pumpCli() {
        if (root.cliBusy || root.cliQueue.length === 0)
            return;
        const req = root.cliQueue[0];
        root.cliQueue = root.cliQueue.slice(1);
        root.cliBusy = true;
        root.cliCurrent = req;
        root.cliOut = "";
        root.cliErr = "";
        cliProcess.command = root.cliArgs(req.args);
        cliProcess.running = true;
    }

    // --- freshness ------------------------------------------------------------
    property bool batteryRefreshing: false
    property real batteryUpdatedAt: 0
    property bool popoutVisible: false
    property real nowTick: Date.now()

    readonly property string freshnessText: {
        if (!root.cliAvailable)
            return "";
        if (root.batteryRefreshing)
            return "Refreshing…";
        if (root.batteryUpdatedAt <= 0)
            return "";
        const secs = Math.round((root.nowTick - root.batteryUpdatedAt) / 1000);
        if (secs < 5)
            return "Updated just now";
        if (secs < 60)
            return "Updated " + secs + "s ago";
        return "Updated " + Math.floor(secs / 60) + "m ago";
    }

    property var gestureRows: []
    property string gameMode: "unknown"

    readonly property bool hasData: leftLevel >= 0 || rightLevel >= 0 || caseLevel >= 0
    readonly property string leftCell: leftLevel < 0 ? "–" : String(leftLevel)
    readonly property string rightCell: rightLevel < 0 ? "–" : String(rightLevel)
    readonly property string caseCell: caseLevel < 0 ? "–" : String(caseLevel)
    readonly property string pillText: !cliAvailable
        ? (cliChecked ? "setup" : "…")
        : (hasData ? leftCell + "·" + rightCell + "·" + caseCell : "--")

    readonly property string statusLine: {
        if (!root.cliAvailable)
            return root.cliError !== "" ? root.cliError : "melodyctl CLI not found";
        if (root.errorTitle !== "")
            return root.errorTitle;
        if (root.connected)
            return root.status !== "" ? root.status : "Live battery + controls";
        return "Earbuds not connected";
    }

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
        root.runCli(["--version"], res => {
            if (res.code === 0 && res.out !== "")
                root.cliVersion = res.out.replace("melodyctl ", "");
        });
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

    // Tick the "updated Xs ago" label, but only while the popout is open.
    Timer {
        interval: 1000
        repeat: true
        running: root.popoutVisible
        onTriggered: root.nowTick = Date.now()
    }

    Process {
        id: resolveProcess

        stdout: StdioCollector {
            onStreamFinished: root.onResolved(text.trim())
        }
    }

    // Single worker for all CLI calls; requests run one at a time (see runCli).
    Process {
        id: cliProcess

        stdout: StdioCollector {
            onStreamFinished: root.cliOut = text
        }
        stderr: StdioCollector {
            onStreamFinished: root.cliErr = text
        }
        onExited: code => {
            const req = root.cliCurrent;
            root.cliBusy = false;
            root.cliCurrent = null;
            if (req && req.onDone)
                req.onDone({ code: code, out: root.cliOut.trim(), err: root.cliErr.trim() });
            root.pumpCli();
        }
    }

    function refresh() {
        if (!root.cliAvailable) {
            root.ensureCli();
            return;
        }
        root.batteryRefreshing = true;
        root.runCli(["battery", "--json"], res => {
            root.batteryRefreshing = false;
            if (res.code === 0 && res.out !== "") {
                try {
                    const data = JSON.parse(res.out);
                    root.leftLevel = data.left ?? -1;
                    root.rightLevel = data.right ?? -1;
                    root.caseLevel = data.case ?? -1;
                    root.connected = true;
                    root.batteryUpdatedAt = Date.now();
                    root.clearError();
                } catch (e) {
                    root.connected = false;
                }
            } else {
                root.connected = false;
                if (res.err !== "")
                    root.setError(res.err);
            }
        });
    }

    function loadGestures() {
        root.runCli(["gestures", "--json"], res => {
            if (res.code === 0 && res.out !== "") {
                try {
                    root.gestureRows = JSON.parse(res.out);
                } catch (e) {
                    root.gestureRows = [];
                }
            }
        });
    }

    function runControl(args) {
        root.runCli(args, res => {
            const out = (res.out || "").trim();
            if (out !== "")
                root.status = out;
            if (res.code === 0) {
                root.clearError();
                if (args[0] === "gesture-set")
                    root.loadGestures();   // the gesture table changed
            } else if (res.err !== "") {
                root.setError(res.err);
            }
        });
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
            detailsText: root.statusLine
            showCloseButton: true

            // Refresh whenever the popout opens, so it never shows stale data.
            readonly property bool popoutNow: parentPopout ? parentPopout.shouldBeVisible : false

            onPopoutNowChanged: {
                root.popoutVisible = popoutNow;
                if (popoutNow) {
                    root.nowTick = Date.now();
                    root.refresh();
                    root.loadGestures();
                }
            }

            Component.onCompleted: root.popoutVisible = popoutNow

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

                StyledRect {
                    id: errorCard

                    width: parent.width
                    visible: root.errorDetail !== ""
                    height: visible ? Math.min(errorCol.implicitHeight + Theme.spacingM * 2, 170) : 0
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(root.errorTransient ? Theme.surfaceContainerHigh : Theme.error,
                                           root.errorTransient ? Theme.popupTransparency : 0.12)

                    Column {
                        id: errorCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            width: parent.width
                            visible: root.errorHint !== ""
                            text: root.errorHint
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.errorTransient ? Theme.surfaceText : Theme.error
                            wrapMode: Text.WordWrap
                        }

                        TextEdit {
                            width: parent.width
                            height: Math.min(contentHeight, 96)
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            text: root.errorDetail
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.family: "monospace"
                        }
                    }
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
                    visible: root.cliAvailable && root.freshnessText !== ""
                    text: root.freshnessText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
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
