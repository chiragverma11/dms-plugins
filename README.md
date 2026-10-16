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
  (`uv tool install --python /usr/bin/python3 git+https://github.com/chiragverma11/melodyctl`;
  a system Python is required because uv-managed Pythons lack Bluetooth sockets). The
  plugin auto-detects it, or you can point it at a script path in its settings.
- The bar pill defaults to **compact** — just the earbuds icon, dimmed while the
  buds are unreachable. Click it for the popout (Left / Right / Case battery +
  controls); **right-click** it to toggle compact ⇄ **full** (icon + `L·R·C`), or
  set *Show battery numbers* in the plugin settings.
- Failures surface as a short message (e.g. *Earbuds busy*, *Earbuds
  unreachable*) with the raw CLI output kept in a selectable **Details** box -
  never a raw traceback. The CLI reports structured errors under `--json`
  (`{"error":{"code","message","hint"}}`).
- Plugins here are personal and verified only against the hardware named in
  each plugin's README.

## License

[MIT](LICENSE).
