import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "melodyctl"

    StyledText {
        width: parent.width
        text: "Enco Buds Battery"
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
        text: "melodyctl script path"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    DankTextField {
        width: parent.width
        text: root.loadValue("scriptPath", "/home/chirag/stuff/melodyctl/melodyctl.py")
        placeholderText: "/path/to/melodyctl.py"
        leftIconName: "description"
        onEditingFinished: root.saveValue("scriptPath", text)
    }

    StyledText {
        width: parent.width
        text: "Poll interval (seconds)"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    DankTextField {
        width: parent.width
        text: root.loadValue("pollInterval", "120")
        placeholderText: "120"
        maximumLength: 4
        leftIconName: "timer"
        onEditingFinished: root.saveValue("pollInterval", text)
    }
}
