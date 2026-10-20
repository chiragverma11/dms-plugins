# Melodyctl Buds

Battery, game mode and touch-gesture controls for **HeyMelody-family earbuds**
(OPPO Enco / OnePlus Buds / realme) in your DankBar. Driven by the
[`melodyctl`](https://github.com/chiragverma11/melodyctl) CLI over the device's
single OPOv1 RFCOMM link.

Verified on **OPPO Enco Buds (ETI81, product `062410`)**. The CLI refuses writes
for models it has not verified unless you pass `--force`, so the plugin can read
battery from other whitelist models but will not guess at their write commands.

## Install

DMS loads plugins from `~/.config/DankMaterialShell/plugins/`. This plugin is
not in the DMS registry, so link it in:

```bash
git clone https://github.com/chiragverma11/dms-plugins
ln -s "$PWD/dms-plugins/melodyctl" ~/.config/DankMaterialShell/plugins/melodyctl
dms ipc call plugins reload melodyctl
```

Then add **Melodyctl Buds** to a bar (DMS layout settings, e.g. `rightWidgets`).

### Requires the `melodyctl` CLI

```bash
uv tool install --python /usr/bin/python3 \
  "git+https://github.com/chiragverma11/melodyctl@v1.5.2"
```

A **system Python** is required: uv-managed Pythons lack Bluetooth socket
support. The plugin auto-detects `melodyctl` on `PATH`; you can also point it at
a script path in its settings (*Test CLI* checks it). `pipx install` works too.

## Recommended: run the daemon

The earbuds allow **one** connection at a time, and they only push their state
as it *changes*. `melodyctl daemon` holds that link and publishes what the buds
push, so the widget never opens a connection of its own:

- `$XDG_RUNTIME_DIR/melodyctl/state.json` — battery, charging, bud/lid state and
  game mode, rewritten as events arrive (with a 60 s heartbeat);
- `$XDG_RUNTIME_DIR/melodyctl/daemon.sock` — commands for the CLI.

The daemon re-reads the battery after `--poll` seconds of silence (default
120 s), so a quiet link cannot leave a stale percentage on screen. Full
contract, including the systemd **user** unit and the state schema, lives in the
[melodyctl daemon docs](https://github.com/chiragverma11/melodyctl/blob/main/docs/daemon.md).

It is opt-in. Without it the widget polls `melodyctl battery --json-full` on the
interval below and everything still works, just without push updates.

## Features

- **Bar pill** — earbuds icon plus battery; **compact** by default (icon only,
  dimmed while the buds are unreachable), or **full** (`L·R·C`). Right-click
  toggles the two; the choice is also in settings.
- **Popout** — Left / Right / Case gauges, charging bolts, and (with the daemon)
  each bud's in-case/in-ear state plus the case lid.
- **Game mode switch** — the buds report their real mode as a push (event 5),
  so a gesture-driven change shows up by itself. There is no query for it: a
  change made *here* is shown as "last set here" until the buds report again.
- **Touch gestures** — the gesture table is editable in place: tap a row, pick
  another function for that bud. Options come from the connected model's own
  whitelist slots (`melodyctl gesture-set --list --json --product <id>`, an
  offline call), so only accepted combinations are offered. The popout body
  scrolls when it is taller than the screen.
- **Refresh button** — performs a real read through whoever owns the link
  (the daemon if it is running), not just a re-read of cached values.
- **Errors as sentences** — e.g. *Earbuds busy*, *Earbuds unreachable*,
  *Earbuds disconnected*, with the raw CLI output in a selectable **Details**
  box. Never a traceback.

## Settings

| Setting | What it does |
|---|---|
| `melodyctl` command / path | Optional override; empty means "find it on `PATH`". |
| Poll interval (seconds) | How often to ask the buds **when no daemon is running** (default 120). With a daemon this is only a safety net. |
| Bar pill → Show battery numbers | Start in full (`icon + L·R·C`) instead of compact. |

## Compatibility

The plugin and the CLI version independently; this plugin is **1.5.2**.

| CLI version | What works |
|---|---|
| ≥ 1.5.2 | Everything below, plus the reconnect/stale-state fixes (no stale game mode after a lid cycle, real refresh with a daemon, calmer link-loss message). |
| ≥ 1.5.0 | Push display, live game-mode state, whitelist-driven gesture editor, daemon. |
| ≥ 1.3.0 | Minimum: device name in the tile (`device --json`). Older CLIs are not supported. |

See [`CHANGELOG.md`](CHANGELOG.md) for the plugin's own history.

## Troubleshooting

- **"Earbuds busy"** — something else holds the single RFCOMM link (another
  `melodyctl` command, HeyMelody on a phone, or a second widget). Only one
  connection is allowed at a time.
- **"Earbuds unreachable"** — the buds are off, out of range, or sitting in a
  closed case (they disconnect). Take them out and retry.
- **Numbers stop updating with a daemon** — check
  `journalctl --user -u melodyctl-daemon -f` and the `session` field in
  `state.json`; `waiting` means the link dropped and the daemon is retrying.
- **First run** — `melodyctl device --json` and `melodyctl battery --json`
  should work in a terminal before the widget can use them.

## License

MIT — see the repository [LICENSE](../LICENSE).
