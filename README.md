# dms-plugins

My plugins for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

Each plugin lives in its own camelCase folder with a `plugin.json`, so several
plugins can share this one repository.

## Plugins

| Plugin | Type | Description |
|---|---|---|
| [Melodyctl Buds](melodyctl) | DankBar Widget / Popout | Left / Right / Case battery plus game mode and touch-gesture controls for **HeyMelody-family earbuds** (OPPO Enco / OnePlus Buds; verified on OPPO Enco Buds, ETI81), driven by the [`melodyctl`](https://github.com/chiragverma11/melodyctl) CLI. |

## Install

```bash
git clone https://github.com/chiragverma11/dms-plugins
ln -s "$PWD/dms-plugins/melodyctl" ~/.config/DankMaterialShell/plugins/melodyctl
dms ipc call plugins reload melodyctl
```

Then add the widget to a bar via DMS layout settings (`rightWidgets`, etc.).

## Notes

- `melodyctl/` needs the **`melodyctl` CLI** on your `PATH`
  (`uv tool install --python /usr/bin/python3 "git+https://github.com/chiragverma11/melodyctl@v1.5.2"`;
  a system Python is required because uv-managed Pythons lack Bluetooth sockets). The
  plugin auto-detects it, or you can point it at a script path in its settings.
- **Preferred: run the daemon.** The earbuds allow one connection at a time and
  only ever push their state *as it changes*, so `melodyctl daemon` (a systemd
  **user** unit, opt-in - see the
  [melodyctl daemon docs](https://github.com/chiragverma11/melodyctl/blob/main/docs/daemon.md))
  holds the link and publishes it to `$XDG_RUNTIME_DIR/melodyctl/state.json`.
  The widget reads that file directly - no Bluetooth connection of its own, and
  battery, bud/lid state and game mode update the moment the buds push them.
  The daemon re-reads the battery when the link has been quiet for its `--poll`
  interval (default 120 s), so the reading cannot drift. Without a daemon the
  widget polls `melodyctl battery --json-full` on the interval below and behaves
  exactly as it always has.
- **Minimum CLI version: 1.3.0** (`melodyctl device --json` feeds the model name in
  the tile and popout; without it the plugin falls back to a generic label).
  Push display, live game-mode state and the whitelist-driven gesture editor use
  **1.5.0**; the reconnect/stale-state fixes use **1.5.2**; with anything older
  the widget just polls. The plugin's version is its own — see
  [`melodyctl/CHANGELOG.md`](melodyctl/CHANGELOG.md).
- The bar pill defaults to **compact** — just the earbuds icon, dimmed while the
  buds are unreachable. Click it for the popout (Left / Right / Case battery +
  controls); **right-click** it to toggle compact ⇄ **full** (icon + `L·R·C`), or
  set *Show battery numbers* in the plugin settings.
- The popout shows each bud's battery, a game-mode switch and the touch-gesture
  list. Gestures are **editable in place**: tap a row to see what that bud's
  button can do and pick a different function, which is written to the buds
  straight away (per ear). The options come from the connected model's
  whitelist slots (`melodyctl gesture-set --list --json --product <id>`, an
  offline call), so the editor offers exactly what that model accepts. The body
  **scrolls** when it is taller than the screen, e.g. with a gesture row
  expanded.
- With the daemon running the popout also shows what the buds push: charging
  bolts, each bud's in-case/in-ear state and the case lid, and the **real**
  game-mode state (the buds report it; before 1.5.0 the widget could only show
  the last value it sent).
- Buttons and the gesture toggle are muted while the buds are unreachable, and
  the battery gauges show `–` rather than a stale percentage once the link drops.
- Failures surface as a short message (e.g. *Earbuds busy*, *Earbuds
  unreachable*) with the raw CLI output kept in a selectable **Details** box -
  never a raw traceback. The CLI reports structured errors under `--json`
  (`{"error":{"code","message","hint"}}`).
- Plugins here are personal and verified only against the hardware named in
  each plugin's README.

## License

[MIT](LICENSE).
