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

    property string scriptPath: PluginService.loadPluginData("melodyctl", "scriptPath", "/home/chirag/stuff/melodyctl/melodyctl.py")
    property int pollInterval: parseInt(PluginService.loadPluginData("melodyctl", "pollInterval", "120"), 10)

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
    readonly property string pillText: hasData ? leftCell + "·" + rightCell + "·" + caseCell : "--"

    function levelText(value) {
        return value < 0 ? "--" : value + "%";
    }

    function gestureSummary(ear) {
        const rows = root.gestureRows.filter(r => r.ear === ear && r.action >= 1 && r.action <= 4);
        return rows.map(r => r.action_name + ": " + r.function_name).join("   ");
    }

    Connections {
        target: PluginService
        ignoreUnknownSignals: true

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== "melodyctl")
                return;
            root.scriptPath = PluginService.loadPluginData("melodyctl", "scriptPath", root.scriptPath);
            root.pollInterval = parseInt(PluginService.loadPluginData("melodyctl", "pollInterval", "120"), 10);
        }
    }

    Timer {
        interval: Math.max(15, root.pollInterval) * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 400
        repeat: false
        running: true
        triggeredOnStart: true
        onTriggered: root.loadGestures()
    }

    Process {
        id: batteryProcess
        command: ["python3", root.scriptPath, "battery", "--json"]

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
        if (batteryProcess.running)
            return;
        batteryProcess.running = true;
    }

    function loadGestures() {
        if (gestureProcess.running)
            return;
        gestureProcess.command = ["python3", root.scriptPath, "gestures", "--json"];
        gestureProcess.running = true;
    }

    function runControl(args) {
        if (controlProcess.running)
            return;
        controlProcess.command = ["python3", root.scriptPath].concat(args);
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
            detailsText: root.connected ? (root.status !== "" ? root.status : "Live battery + controls") : (root.lastError !== "" ? root.lastError : "Earbuds not connected")
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingS
                topPadding: Theme.spacingS
                bottomPadding: Theme.spacingS

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
