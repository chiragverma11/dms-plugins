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

    popoutWidth: 340
    popoutHeight: 0

    ccWidgetIcon: "earbuds"
    ccWidgetPrimaryText: "Enco Buds"
    ccWidgetSecondaryText: root.pillText
    ccWidgetIsActive: root.connected

    // Left click opens the popout; right click flips the pill between compact
    // (icon only) and full (icon + L·R·C).
    pillRightClickAction: () => root.togglePillStyle()

    // --- melodyctl CLI resolution -------------------------------------------
    // Order: explicit override (setting) -> `melodyctl` on PATH -> dev fallback.
    readonly property string devFallback: "/home/chirag/stuff/melodyctl/melodyctl.py"
    readonly property string installHint: "uv tool install --python /usr/bin/python3 git+https://github.com/chiragverma11/melodyctl"

    // `command` is the forward setting; `scriptPath` is read as a legacy fallback.
    property string commandOverride: PluginService.loadPluginData("melodyctl", "command",
            PluginService.loadPluginData("melodyctl", "scriptPath", ""))
    property int pollInterval: parseInt(PluginService.loadPluginData("melodyctl", "pollInterval", "120"), 10)
    // "compact" (icon only, default) or "full" (icon + L·R·C).
    property string pillStyle: PluginService.loadPluginData("melodyctl", "pillStyle", "compact")

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

    // Drop any stale readings so a disconnected popout never shows old numbers.
    function clearLevels() {
        root.leftLevel = -1;
        root.rightLevel = -1;
        root.caseLevel = -1;
        root.batteryUpdatedAt = 0;
    }

    function togglePillStyle() {
        root.pillStyle = root.pillStyle === "full" ? "compact" : "full";
        PluginService.savePluginData("melodyctl", "pillStyle", root.pillStyle);
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
    // Game mode is write-only (no read command), so we can only remember the last
    // command we sent rather than showing a real device state.
    property string gameModeLastSent: ""
    property bool gesturesExpanded: false

    readonly property bool hasData: leftLevel >= 0 || rightLevel >= 0 || caseLevel >= 0
    readonly property string leftCell: leftLevel < 0 ? "–" : String(leftLevel)
    readonly property string rightCell: rightLevel < 0 ? "–" : String(rightLevel)
    readonly property string caseCell: caseLevel < 0 ? "–" : String(caseLevel)
    readonly property string pillText: !cliAvailable
        ? (cliChecked ? "setup" : "…")
        : (hasData ? leftCell + "·" + rightCell + "·" + caseCell : "--")

    // Dim the pill while the earbuds are unreachable so the state is obvious.
    readonly property color pillIconColor: root.connected
        ? (Theme.widgetIconColor || Theme.primary)
        : Theme.withAlpha(Theme.widgetIconColor || Theme.primary, 0.45)
    readonly property color pillTextColor: root.connected
        ? (Theme.widgetTextColor || Theme.surfaceText)
        : Theme.withAlpha(Theme.widgetTextColor || Theme.surfaceText, 0.6)

    readonly property string statusLine: {
        if (!root.cliAvailable)
            return root.cliError !== "" ? root.cliError : "melodyctl CLI not found";
        if (root.errorTitle !== "")
            return root.errorTitle;
        if (root.connected)
            return root.status !== "" ? root.status : "Live battery + controls";
        return "Earbuds not connected";
    }

    // After a control action the header line shows the CLI's acknowledgement
    // for a few seconds, then falls back to the default status line.
    property int ackTimeout: 7000

    Timer {
        id: statusResetTimer

        interval: root.ackTimeout
        repeat: false
        onTriggered: root.status = ""
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

    // --- gesture decoding for the popout ------------------------------------
    readonly property var leftGestures: root.gestureRows.filter(r => r.ear === "left" && r.action >= 1 && r.action <= 4)
    readonly property var rightGestures: root.gestureRows.filter(r => r.ear === "right" && r.action >= 1 && r.action <= 4)

    // Triple-tap is the one gesture surfaced as a quick control (it maps to the
    // "both earbuds" gesture id 4 when written).
    readonly property var tripleRow: root.gestureRows.find(r => r.ear === "left" && r.button === 1 && r.action === 3)
    readonly property int tripleActionIndex: {
        if (!root.tripleRow)
            return -1;
        if (root.tripleRow.function === 3)
            return 0;   // voice assistant
        if (root.tripleRow.function === 17)
            return 1;   // game mode
        return -1;
    }

    readonly property int gameModeIndex: root.gameModeLastSent === "on" ? 0
        : (root.gameModeLastSent === "off" ? 1 : -1)

    // Map a gesture function name to a Material Symbols glyph.
    function functionIcon(name) {
        switch (name) {
        case "play/pause":
            return "play_arrow";
        case "previous song":
        case "previous (OnePlus only)":
            return "skip_previous";
        case "next song":
            return "skip_next";
        case "voice assistant":
            return "mic";
        case "game mode":
            return "sports_esports";
        case "volume up":
            return "volume_up";
        case "volume down":
            return "volume_down";
        case "none":
            return "block";
        default:
            return "graph_2";
        }
    }

    // "previous song" -> "Previous song"
    function functionLabel(name) {
        if (!name || name.length === 0)
            return "—";
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    Component.onCompleted: root.resolveCli()

    Connections {
        target: PluginService
        ignoreUnknownSignals: true

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== "melodyctl")
                return;
            root.pillStyle = PluginService.loadPluginData("melodyctl", "pillStyle", "compact");
            root.pollInterval = parseInt(PluginService.loadPluginData("melodyctl", "pollInterval", "120"), 10);
            // Only re-resolve the CLI when the command/path actually changed, so a
            // pill-style flip doesn't spawn extra probes.
            const newCommand = PluginService.loadPluginData("melodyctl", "command",
                    PluginService.loadPluginData("melodyctl", "scriptPath", ""));
            if (newCommand !== root.commandOverride) {
                root.commandOverride = newCommand;
                root.cliChecked = false;
                root.cliAvailable = false;
                root.resolveCli();
            }
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

    // A gesture read can lose the race with the battery read for the buds'
    // single RFCOMM connection, so retry once while the popout is open.
    Timer {
        id: gestureRetryTimer

        interval: 700
        repeat: false
        onTriggered: root.loadGestures(false)
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
                    root.clearLevels();
                }
            } else {
                root.connected = false;
                root.clearLevels();
                if (res.err !== "")
                    root.setError(res.err);
            }
        });
    }

    function loadGestures(allowRetry) {
        root.runCli(["gestures", "--json"], res => {
            let parsed = null;
            if (res.code === 0 && res.out !== "") {
                try {
                    parsed = JSON.parse(res.out);
                } catch (e) {
                    parsed = null;
                }
            }
            if (parsed !== null) {
                root.gestureRows = parsed;
                return;
            }
            if (allowRetry !== false && root.popoutVisible)
                gestureRetryTimer.restart();
        });
    }

    function runControl(args) {
        root.runCli(args, res => {
            const out = (res.out || "").trim();
            if (out !== "") {
                root.status = out;
                statusResetTimer.restart();
            }
            if (res.code === 0) {
                root.clearError();
                if (args[0] === "gesture-set")
                    root.loadGestures();   // the gesture table changed
            } else if (res.err !== "") {
                root.setError(res.err);
            }
        });
    }

    component SectionLabel: StyledText {
        font.pixelSize: Theme.fontSizeSmall - 1
        font.weight: Font.Bold
        font.letterSpacing: 1.3
        font.capitalization: Font.AllUppercase
        color: Theme.surfaceVariantText
    }

    component BatteryGauge: Item {
        id: gauge

        required property string label
        required property string iconName
        required property int value
        property bool known: false

        readonly property int pct: gauge.value < 0 ? 0 : Math.min(100, gauge.value)
        readonly property color accent: !gauge.known
            ? Theme.surfaceVariantText
            : (gauge.value <= 15 ? Theme.error : (gauge.value <= 30 ? Theme.warning : Theme.primary))

        implicitHeight: gaugeCol.implicitHeight

        Column {
            id: gaugeCol

            width: parent.width
            spacing: Theme.spacingXS

            Item {
                width: parent.width
                height: Theme.iconSize + 8

                DankIcon {
                    anchors.centerIn: parent
                    name: gauge.iconName
                    size: Theme.iconSize + 2
                    color: gauge.accent
                    opacity: gauge.known ? 1 : 0.45

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: gauge.known ? gauge.value + "%" : "–"
                font.pixelSize: Theme.fontSizeLarge + 1
                font.weight: Font.Bold
                color: gauge.known ? Theme.surfaceText : Theme.surfaceVariantText
                opacity: gauge.known ? 1 : 0.55

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }
            }

            StyledRect {
                width: parent.width
                height: 4
                radius: 2
                color: Theme.withAlpha(Theme.surfaceVariantText, 0.16)

                StyledRect {
                    height: parent.height
                    radius: parent.radius
                    width: gauge.known ? parent.width * gauge.pct / 100 : 0
                    color: gauge.accent

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: gauge.label
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.surfaceVariantText
            }
        }
    }

    component GestureRow: Item {
        id: gRow

        required property string gesture
        required property string fn

        width: parent ? parent.width : 0
        height: 26

        StyledText {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: gRow.gesture
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        RowLayout {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            DankIcon {
                name: root.functionIcon(gRow.fn)
                size: 14
                color: Theme.surfaceText
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: root.functionLabel(gRow.fn)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    horizontalBarPill: Component {
        RowLayout {
            spacing: Theme.spacingXS

            DankIcon {
                name: "earbuds"
                size: root.iconSize
                color: root.pillIconColor
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                visible: root.pillStyle === "full"
                text: root.pillText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.Medium
                color: root.pillTextColor
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "earbuds"
            size: root.iconSize
            color: root.pillIconColor
            anchors.centerIn: parent
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot

            headerText: "OPPO Enco Buds"
            // The status line is rendered below (monospace + smaller) so it can be
            // styled, so the built-in details line stays empty.
            detailsText: ""
            showCloseButton: true

            headerActions: Component {
                DankActionButton {
                    iconName: "refresh"
                    iconColor: root.batteryRefreshing ? Theme.primary : Theme.surfaceText
                    tooltipText: "Refresh"
                    onClicked: {
                        root.refresh();
                        root.loadGestures();
                    }
                }
            }

            // Refresh whenever the popout opens, so it never shows stale data.
            readonly property bool popoutNow: parentPopout ? parentPopout.shouldBeVisible : false

            onPopoutNowChanged: {
                root.popoutVisible = popoutNow;
                if (popoutNow) {
                    root.nowTick = Date.now();
                    root.refresh();
                    root.loadGestures();
                    contentCol.shown = false;
                    entranceTimer.restart();
                }
            }

            Component.onCompleted: {
                root.popoutVisible = popoutNow;
                contentCol.shown = true;
            }

            Timer {
                id: entranceTimer

                interval: 16
                repeat: false
                onTriggered: contentCol.shown = true
            }

            Column {
                id: contentCol

                width: parent.width
                spacing: Theme.spacingM

                property bool shown: true

                opacity: contentCol.shown ? 1 : 0
                transform: Translate {
                    y: contentCol.shown ? 0 : 12

                    Behavior on y {
                        NumberAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }

                // Status / acknowledgement line (under the title).
                StyledText {
                    width: parent.width
                    leftPadding: Theme.spacingS
                    text: root.statusLine
                    isMonospace: true
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                // --- resolving CLI -------------------------------------------------
                RowLayout {
                    width: parent.width
                    visible: !root.cliChecked
                    spacing: Theme.spacingS

                    DankSpinner {
                        size: 16
                        running: true
                        color: Theme.surfaceVariantText
                        Layout.alignment: Qt.AlignVCenter
                    }

                    StyledText {
                        text: "Looking for melodyctl…"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                    }
                }

                // --- CLI missing ---------------------------------------------------
                StyledRect {
                    width: parent.width
                    visible: root.cliChecked && !root.cliAvailable
                    implicitHeight: installCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.warning, 0.3)

                    Column {
                        id: installCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "info"
                                size: Theme.iconSizeSmall
                                color: Theme.warning
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                text: "melodyctl CLI required"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: "Install it, or set a custom command / script path in this plugin's settings."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }

                        TextEdit {
                            width: parent.width
                            height: contentHeight + topPadding + bottomPadding
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            text: root.installHint
                            color: Theme.surfaceText
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSmall - 1
                            leftPadding: Theme.spacingS
                            rightPadding: Theme.spacingS
                            topPadding: Theme.spacingXS
                            bottomPadding: Theme.spacingXS

                            Rectangle {
                                anchors.fill: parent
                                z: -1
                                radius: 6
                                color: Theme.withAlpha(Theme.surfaceVariantText, 0.12)
                            }
                        }
                    }
                }

                // --- error ---------------------------------------------------------
                StyledRect {
                    id: errorCard

                    width: parent.width
                    visible: root.errorDetail !== "" && root.cliAvailable
                    implicitHeight: visible ? Math.min(errorCol.implicitHeight + Theme.spacingM * 2, 190) : 0
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(root.errorTransient ? Theme.surfaceVariantText : Theme.error,
                                           root.errorTransient ? 0.1 : 0.14)
                    border.width: 1
                    border.color: Theme.withAlpha(root.errorTransient ? Theme.surfaceVariantText : Theme.error, 0.25)

                    Column {
                        id: errorCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankIcon {
                                name: root.errorTransient ? "info" : "warning"
                                size: Theme.iconSizeSmall
                                color: root.errorTransient ? Theme.surfaceVariantText : Theme.error
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                width: parent.width
                                visible: root.errorHint !== ""
                                text: root.errorHint
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: root.errorTransient ? Theme.surfaceText : Theme.error
                                wrapMode: Text.WordWrap
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                            }
                        }

                        TextEdit {
                            width: parent.width
                            height: Math.min(contentHeight + topPadding + bottomPadding, 110)
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

                // --- battery -------------------------------------------------------
                StyledRect {
                    width: parent.width
                    visible: root.cliAvailable
                    implicitHeight: batteryCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.08)

                    Column {
                        id: batteryCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingXS

                            SectionLabel {
                                text: "Battery"
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                            }

                            DankSpinner {
                                size: 12
                                running: root.batteryRefreshing
                                visible: root.batteryRefreshing
                                color: Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                text: root.freshnessText
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            BatteryGauge {
                                Layout.fillWidth: true
                                label: "Left"
                                iconName: "earbud_left"
                                value: root.leftLevel
                                known: root.connected && root.leftLevel >= 0
                            }

                            BatteryGauge {
                                Layout.fillWidth: true
                                label: "Right"
                                iconName: "earbud_right"
                                value: root.rightLevel
                                known: root.connected && root.rightLevel >= 0
                            }

                            BatteryGauge {
                                Layout.fillWidth: true
                                label: "Case"
                                iconName: "earbud_case"
                                value: root.caseLevel
                                known: root.connected && root.caseLevel >= 0
                            }
                        }
                    }
                }

                // --- controls ------------------------------------------------------
                StyledRect {
                    width: parent.width
                    visible: root.cliAvailable
                    implicitHeight: controlsCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.08)

                    Column {
                        id: controlsCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        // Everything here needs the earbuds, so mute it when they
                        // are unreachable instead of letting taps fail silently.
                        opacity: root.connected ? 1 : 0.45

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.mediumDuration
                                easing.type: Theme.standardEasing
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS

                            RowLayout {
                                width: parent.width
                                spacing: Theme.spacingS

                                Column {
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter

                                    StyledText {
                                        text: "Game mode"
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        text: "Low-latency audio"
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                DankButtonGroup {
                                    Layout.alignment: Qt.AlignVCenter
                                    size: "small"
                                    selectionMode: "single"
                                    enabled: root.connected
                                    model: ["On", "Off"]
                                    currentIndex: root.gameModeIndex
                                    onSelectionChanged: (index, selected) => {
                                        if (!selected)
                                            return;
                                        root.gameModeLastSent = index === 0 ? "on" : "off";
                                        root.runControl(["game", root.gameModeLastSent]);
                                    }
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: "Not reported by the buds — shows last sent."
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.withAlpha(Theme.surfaceVariantText, 0.85)
                                wrapMode: Text.WordWrap
                            }
                        }

                        StyledRect {
                            width: parent.width
                            height: 1
                            color: Theme.withAlpha(Theme.surfaceVariantText, 0.1)
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "Triple-tap action"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: "Left & right earbud"
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                            }

                            Item {
                                width: parent.width
                                height: tripleGroup.implicitHeight * tripleGroup.scale

                                DankButtonGroup {
                                    id: tripleGroup

                                    anchors.horizontalCenter: parent.horizontalCenter
                                    scale: Math.min(1, parent.width / implicitWidth)
                                    transformOrigin: Item.Center
                                    size: "small"
                                    selectionMode: "single"
                                    enabled: root.connected
                                    model: ["Voice assistant", "Game mode"]
                                    currentIndex: root.tripleActionIndex
                                    onSelectionChanged: (index, selected) => {
                                        if (!selected)
                                            return;
                                        root.runControl(["gesture-set", "4", "1", "3", index === 0 ? "3" : "17"]);
                                    }
                                }
                            }
                        }
                    }
                }

                // --- touch gestures (collapsible) ----------------------------------
                Column {
                    width: parent.width
                    visible: root.cliAvailable
                    spacing: Theme.spacingS

                    Item {
                        width: parent.width
                        height: 26

                        // Not reachable -> the gesture table can't be read, so
                        // keep the section collapsed and non-interactive.
                        opacity: root.connected ? 1 : 0.5

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.mediumDuration
                                easing.type: Theme.standardEasing
                            }
                        }

                        SectionLabel {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Touch gestures"
                        }

                        DankIcon {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            name: "expand_more"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                            rotation: (root.gesturesExpanded && root.connected) ? 180 : 0

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: Theme.shortDuration
                                    easing.type: Theme.standardEasing
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.connected
                            cursorShape: root.connected ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.gesturesExpanded = !root.gesturesExpanded
                        }
                    }

                    Item {
                        width: parent.width
                        height: (root.gesturesExpanded && root.connected) ? gestureCard.implicitHeight : 0
                        clip: true

                        Behavior on height {
                            NumberAnimation {
                                duration: Theme.mediumDuration
                                easing.type: Theme.standardEasing
                            }
                        }

                        StyledRect {
                            id: gestureCard

                            width: parent.width
                            implicitHeight: gestureBody.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.nestedSurface
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.08)

                            Column {
                                id: gestureBody

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                Repeater {
                                    model: {
                                        const out = [];
                                        if (root.leftGestures.length > 0)
                                            out.push({ "ear": "left", "icon": "earbud_left", "rows": root.leftGestures });
                                        if (root.rightGestures.length > 0)
                                            out.push({ "ear": "right", "icon": "earbud_right", "rows": root.rightGestures });
                                        return out;
                                    }

                                    delegate: Column {
                                        required property var modelData

                                        width: gestureBody.width
                                        spacing: Theme.spacingXS

                                        RowLayout {
                                            width: parent.width
                                            spacing: Theme.spacingXS

                                            DankIcon {
                                                name: modelData.icon
                                                size: 14
                                                color: Theme.surfaceVariantText
                                                Layout.alignment: Qt.AlignVCenter
                                            }

                                            StyledText {
                                                text: modelData.ear === "left" ? "Left earbud" : "Right earbud"
                                                font.pixelSize: Theme.fontSizeSmall - 1
                                                font.weight: Font.Medium
                                                color: Theme.surfaceVariantText
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.fillWidth: true
                                            }
                                        }

                                        Repeater {
                                            model: modelData.rows

                                            delegate: GestureRow {
                                                required property var modelData

                                                gesture: modelData.action_name
                                                fn: modelData.function_name
                                            }
                                        }
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    visible: root.gestureRows.length === 0
                                    text: "No gesture data yet."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }
                    }
                }

                // --- footer --------------------------------------------------------
                StyledText {
                    width: parent.width
                    visible: root.cliAvailable && root.cliVersion !== ""
                    text: "melodyctl " + root.cliVersion
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.withAlpha(Theme.surfaceVariantText, 0.8)
                    topPadding: Theme.spacingXS
                }
            }
        }
    }
}
