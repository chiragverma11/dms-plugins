# dms-plugins

My plugins for [Dux Shell (DMS 2.0)](https://github.com/duxlabs-dev/dux-shell),
formerly DankMaterialShell.

Each plugin lives in its own camelCase folder with a `plugin.json`, a
`README.md` (requirements, install, usage) and a `CHANGELOG.md`, so several
plugins can share this one repository.

## Plugins

| Plugin | Type | Description |
|---|---|---|
| [Melodyctl Buds](melodyctl/) | Bar Widget / Popout | Battery, game mode and touch-gesture controls for **HeyMelody-family earbuds** (OPPO Enco / OnePlus Buds; verified on OPPO Enco Buds, ETI81). |

## Install

DMS 2.0 loads plugins from `~/.config/dms/plugins/` (`~/.config/DankMaterialShell/plugins/`
on 1.x). These are not in the registry, so link the folder(s) you want and
reload:

```bash
git clone https://github.com/chiragverma11/dms-plugins
ln -s "$PWD/dms-plugins/<plugin>" ~/.config/dms/plugins/<plugin>
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
