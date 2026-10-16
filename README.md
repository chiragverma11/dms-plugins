# dms-plugins

My plugins for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

Each plugin lives in its own camelCase folder with a `plugin.json`, so several
plugins can share this one repository.

## Plugins

| Plugin | Type | Description |
|---|---|---|
| [melodyctl](melodyctl) | DankBar Widget / Popout | Left / Right / Case battery plus game mode and touch-gesture controls for **OPPO Enco Buds (ETI81)**, driven by the [`melodyctl`](https://github.com/chiragverma11/melodyctl) CLI. |

## Install

```bash
git clone https://github.com/chiragverma11/dms-plugins
ln -s "$PWD/dms-plugins/melodyctl" ~/.config/DankMaterialShell/plugins/melodyctl
dms ipc call plugins reload melodyctl
```

Then add the widget to a bar via DMS layout settings (`rightWidgets`, etc.).

## Notes

- `melodyctl/` needs the **`melodyctl` CLI** on your `PATH`
  (`pipx install git+https://github.com/chiragverma11/melodyctl`). The plugin
  auto-detects it, or you can point it at a script path in its settings.
- Plugins here are personal and verified only against the hardware named in
  each plugin's README.

## License

[MIT](LICENSE).
