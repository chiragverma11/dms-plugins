# melodyctl-dms

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
(Quickshell) widget for **OPPO Enco Buds (ETI81)**: a bar pill showing
Left / Right / Case battery, with a popout for game mode and touch-gesture
controls.

It is a thin UI over the **`melodyctl`** CLI - all device I/O happens through
that CLI, so this plugin needs no Bluetooth code of its own.

## Requirements

- DankMaterialShell (Quickshell)
- The `melodyctl` CLI (sibling project) and its dependencies
- Buds paired and connected

## Install

```bash
# 1. put the plugin where DMS looks for it
ln -s /path/to/melodyctl-dms ~/.config/DankMaterialShell/plugins/melodyctl

# 2. tell DMS which CLI to run (Settings -> Plugins -> melodyctl), or edit
#    ~/.config/DankMaterialShell/plugin_settings.json:
#    { "melodyctl": { "enabled": true, "scriptPath": "/path/to/melodyctl/melodyctl.py" } }

# 3. reload
dms ipc call plugins reload melodyctl
```

Add the widget to a bar via your DMS layout settings (`rightWidgets`, etc.).

## Settings

| Key | Default | Meaning |
|---|---|---|
| `scriptPath` | `/home/chirag/stuff/melodyctl/melodyctl.py` | path to the melodyctl CLI |
| `pollInterval` | `120` | battery poll interval, seconds |

## Files

| File | Role |
|---|---|
| `plugin.json` | plugin manifest (id `melodyctl`) |
| `MelodyctlWidget.qml` | bar pill + popout (battery rows, game mode, gestures) |
| `MelodyctlSettings.qml` | settings UI (`scriptPath`, `pollInterval`) |

## License

[MIT](LICENSE). Not affiliated with or endorsed by OPPO / HeyTap.
