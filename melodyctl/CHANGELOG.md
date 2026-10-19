# Changelog — Melodyctl Buds (DMS plugin)

Notable changes to this plugin. Versions are the **plugin's own** and are
independent of the `melodyctl` CLI's; the minimum CLI version is noted per
release. This repo is a monorepo, so tags are prefixed `melodyctl-v<version>`.

## [1.5.0] - 2026-10-19

Requires `melodyctl` >= 1.5.0 for the push features below; **1.3.0+ still
works** (the widget falls back to polling its own RFCOMM session).

### Added
- **Push display from the `melodyctl daemon`.** While the daemon holds the
  link, the widget watches `$XDG_RUNTIME_DIR/melodyctl/state.json` instead of
  connecting: battery updates appear the moment the buds push them, and the
  popout gains each bud's in-case/in-ear state, the case lid and charging
  bolts. No RFCOMM connection is opened by the widget at all in this mode.
- **Real game-mode state.** The buds report it (push event 5), so the switch
  shows what the device says rather than only the last value the widget sent
  - the "shows last sent" caveat is gone when a daemon is running.
- **Whitelist-driven gesture options.** The per-action function list now comes
  from `melodyctl gesture-set --list --json --product <id>` (offline), i.e.
  the connected model's own allowed slots, instead of a hardcoded ETI81 copy
  that could drift from the CLI.

### Changed
- `battery --json-full` is used in the polling fallback, so charging is shown
  even without a daemon.
- The poll interval is a safety net with a daemon running (the state file is
  watched); the settings text now says so.

## [1.4.0] - 2026-10-19

Requires `melodyctl` >= 1.3.0.

### Added
- **Edit touch gestures from the popout.** Tap a gesture row to see what that
  bud's button can do and pick a different function; the change is written to
  the buds straight away, per ear.
- **Device name in the tile and popout**, read once per session from
  `melodyctl device --json` (older CLIs keep the fallback label).
- Popout body **scrolls** when it is taller than the screen - e.g. with a
  gesture row expanded.

### Changed
- Popout redesigned: battery cards with gauges and animated interactions.
- Wording presents the plugin as HeyMelody-family (verified on OPPO Enco
  Buds/ETI81) rather than ETI81-only.

## Earlier releases

Release notes for these live in the annotated git tags; summary:

| tag | date | summary |
|---|---|---|
| `melodyctl-v1.3.0` | 2026-10-16 | Compact/full bar pill (right-click or settings), TWS `earbuds` icon, dim when disconnected; clear stale battery after a drop |
| `melodyctl-v1.2.0` | 2026-10-16 | Refresh on popout open; serialise CLI calls through one queue (no more RFCOMM busy races); freshness label |
| `melodyctl-v1.1.0` | 2026-10-16 | Graceful errors — short title + Details box; shared `errfmt.js` humanizer |
| `melodyctl-v1.0.2` | 2026-10-16 | Recommend `uv tool install` (system `--python`); note the pipx alternative |
| `melodyctl-v1.0.1` | 2026-10-16 | Detect pipx installs via `~/.local/bin` |
| `melodyctl-v1.0.0` | 2026-10-16 | Restructure into the `dms-plugins` monorepo; `melodyctl` CLI auto-detection |
