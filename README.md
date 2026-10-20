# dms-plugins

My plugins for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

Each plugin lives in its own camelCase folder with a `plugin.json`, a
`README.md` (requirements, install, usage) and a `CHANGELOG.md`, so several
plugins can share this one repository.

## Plugins

| Plugin | Type | Description |
|---|---|---|
| [Melodyctl Buds](melodyctl/) | DankBar Widget / Popout | Battery, game mode and touch-gesture controls for **HeyMelody-family earbuds** (OPPO Enco / OnePlus Buds; verified on OPPO Enco Buds, ETI81). |

## Install

DMS loads plugins from `~/.config/DankMaterialShell/plugins/`. These are not in
the DMS registry, so link the folder(s) you want and reload:

```bash
git clone https://github.com/chiragverma11/dms-plugins
ln -s "$PWD/dms-plugins/<plugin>" ~/.config/DankMaterialShell/plugins/<plugin>
dms ipc call plugins reload <plugin>
```

Then add the widget to a bar via DMS layout settings (`rightWidgets`, etc.).
Each plugin's README lists its own requirements — for example
[Melodyctl Buds](melodyctl/) needs the [`melodyctl`](https://github.com/chiragverma11/melodyctl)
CLI installed.

## Notes

- Plugins here are personal and verified only against the hardware named in
  each plugin's README.

## License

[MIT](LICENSE).
