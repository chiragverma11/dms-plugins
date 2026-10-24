import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "errfmt.js" as ErrFmt

PluginSettings {
    id: root
    pluginId: "melodyctl"

    readonly property string installHint: "uv tool install --python /usr/bin/python3 git+https://github.com/chiragverma11/melodyctl"

    property bool testRunning: false
    property bool testOk: false
    property string testResult: ""
    property string testDetail: ""
    property string testOut: ""
    property string testErr: ""

    function runTest() {
        if (testProcess.running)
            return;
        root.testRunning = true;
        root.testOk = false;
        root.testResult = "";
        root.testDetail = "";
        root.testOut = "";
        root.testErr = "";
        const override = root.loadValue("command", root.loadValue("scriptPath", ""));
        testProcess.command = ["sh", "-c",
            'if [ -n "$1" ]; then T="$1"; ' +
            'elif command -v melodyctl >/dev/null 2>&1; then T="melodyctl"; ' +
            'elif [ -x "$HOME/.local/bin/melodyctl" ]; then T="$HOME/.local/bin/melodyctl"; ' +
            'else T=""; fi; ' +
            'if [ -z "$T" ]; then echo "NOT_FOUND"; exit 1; fi; ' +
            'if command -v "$T" >/dev/null 2>&1; then "$T" --version; exit $?; fi; ' +
            'if [ -f "$T" ]; then python3 "$T" --version; exit $?; fi; ' +
            'echo "NOT_FOUND"; exit 1',
            "sh", override];
        testProcess.running = true;
    }

    Process {
        id: testProcess

        stdout: StdioCollector {
            onStreamFinished: root.testOut = text
        }
        stderr: StdioCollector {
            onStreamFinished: root.testErr = text
        }
        onExited: code => {
            root.testRunning = false;
            const o = root.testOut.trim();
            const e = root.testErr.trim();
            if (o === "NOT_FOUND") {
                root.testOk = false;
                root.testResult = "Failed — melodyctl not found on PATH or at the configured path";
                root.testDetail = "";
            } else if (code === 0 && o !== "") {
                root.testOk = true;
                root.testResult = "OK — " + o;
                root.testDetail = "";
            } else {
                const info = ErrFmt.humanize(e || o || ("exit " + code));
                root.testOk = false;
                root.testResult = "Failed — " + (info.title || "melodyctl failed");
                root.testDetail = info.hint !== "" ? info.hint + "\n\n" + info.detail : info.detail;
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Melodyctl Buds"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Reads Left / Right / Case battery and drives game mode + touch gestures via the melodyctl CLI over the OPOv1 RFCOMM channel."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        topPadding: Theme.spacingS
        text: "Installation"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.surfaceVariantText
    }

    StyledText {
        width: parent.width
        text: "This plugin needs the melodyctl CLI (uv or pipx). Install it, then use Test:"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: installText.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

        TextEdit {
            id: installText
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            text: root.installHint
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            font.family: "monospace"
        }
    }

    StyledText {
        width: parent.width
        topPadding: Theme.spacingS
        text: "pipx also works: pipx install git+https://github.com/chiragverma11/melodyctl"
        font.pixelSize: Theme.fontSizeSmall - 1
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Row {
        spacing: Theme.spacingM

        StyledRect {
            width: Math.max(80, testLabel.implicitWidth + Theme.spacingM * 2)
            height: 32
            radius: Theme.cornerRadius
            color: Theme.primary

            StyledText {
                id: testLabel
                anchors.centerIn: parent
                text: root.testRunning ? "Testing…" : "Test CLI"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.runTest()
            }
        }
    }

    StyledText {
        width: parent.width
        visible: root.testResult !== ""
        text: root.testResult
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: root.testOk ? Theme.primary : Theme.error
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        visible: root.testDetail !== ""
        height: visible ? testDetailText.height + Theme.spacingM * 2 : 0
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

        TextEdit {
            id: testDetailText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            height: Math.min(contentHeight, 120)
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            text: root.testDetail
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall - 1
            font.family: "monospace"
        }
    }

    StyledText {
        width: parent.width
        topPadding: Theme.spacingS
        text: "melodyctl command / path (optional override)"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Leave empty to auto-detect: uses `melodyctl` on PATH, or set a full path to a script or a command name."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    DTextField {
        width: parent.width
        text: root.loadValue("command", root.loadValue("scriptPath", ""))
        placeholderText: "melodyctl   (or /path/to/melodyctl.py)"
        leftIconName: "terminal"
        onEditingFinished: root.saveValue("command", text)
    }

    StyledText {
        width: parent.width
        topPadding: Theme.spacingS
        text: "Poll interval (seconds)"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    DTextField {
        width: parent.width
        text: root.loadValue("pollInterval", "120")
        placeholderText: "120"
        maximumLength: 4
        leftIconName: "timer"
        onEditingFinished: root.saveValue("pollInterval", text)
    }

    StyledText {
        width: parent.width
        text: "How often to ask the earbuds when no daemon is running. With `melodyctl daemon` the widget reads its state file instead - pushes show up straight away and this is only a safety net."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        topPadding: Theme.spacingS
        text: "Bar pill"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.surfaceVariantText
    }

    DToggle {
        width: parent.width
        text: "Show battery numbers"
        description: "Compact (default) keeps just the earbuds icon. On adds L·R·C next to it. Right-clicking the pill toggles this too."
        Component.onCompleted: checked = root.loadValue("pillStyle", "compact") === "full"
        onToggled: function (newChecked) {
            checked = newChecked;
            root.saveValue("pillStyle", newChecked ? "full" : "compact");
        }
    }
}
