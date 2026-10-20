import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services
import "errfmt.js" as ErrFmt

PluginComponent {
    id: root

    popoutWidth: 340
    popoutHeight: 0

    // Device name / product id shown in the control-center tile and popout
    // header; filled in from the daemon's state.json or `melodyctl device --json`.
    property string deviceName: ""
    property string deviceId: ""
    readonly property string deviceLabel: root.deviceName !== "" ? root.deviceName : "Melodyctl Buds"

    ccWidgetIcon: "earbuds"
    ccWidgetPrimaryText: root.deviceLabel
    ccWidgetSecondaryText: root.pillText
    ccWidgetIsActive: root.connected

    // Left click opens the popout; right click flips the pill between compact
    // (icon only) and full (icon + L·R·C).
    pillRightClickAction: () => root.togglePillStyle()

    // --- melodyctl CLI resolution -------------------------------------------
    // Order: explicit override (setting) -> `melodyctl` on PATH -> dev fallback.
    readonly property string devFallback: "/home/chirag/stuff/melodyctl/melodyctl.py"
    readonly property string installHint: "uv tool install --python /usr/bin/python3 git+https://github.com/chiragverma11/melodyctl"

    // `command` is the forward setting; `scriptPath` is read as a legacy fallback.
    property string commandOverride: PluginService.loadPluginData("melodyctl", "command",
            PluginService.loadPluginData("melodyctl", "scriptPath", ""))
    property int pollInterval: parseInt(PluginService.loadPluginData("melodyctl", "pollInterval", "120"), 10)
    // "compact" (icon only, default) or "full" (icon + L·R·C).
    property string pillStyle: PluginService.loadPluginData("melodyctl", "pillStyle", "compact")

    property string cliPath: ""
    property bool cliIsScript: false
    property bool cliChecked: false
    property bool cliAvailable: false
    property string cliVersion: ""
    property string cliError: ""

    property int leftLevel: -1
    property int rightLevel: -1
    property int caseLevel: -1
    property bool leftCharging: false
    property bool rightCharging: false
    property bool caseCharging: false
    property bool connected: false
    property string status: ""

    // --- daemon push source ---------------------------------------------------
    // A running `melodyctl daemon` owns the single RFCOMM link and publishes what
    // the device pushes to $XDG_RUNTIME_DIR/melodyctl/state.json. Reading that
    // file needs no Bluetooth connection, so the widget prefers it and only
    // polls the CLI when the daemon is absent or its file has gone stale. The
    // contract lives in docs/daemon.md in the melodyctl repo.
    readonly property string daemonStatePath: {
        const dir = Quickshell.env("XDG_RUNTIME_DIR");
        return (dir && dir.length > 0) ? dir + "/melodyctl/state.json" : "";
    }
    // Last parsed state.json; null when there is no daemon / no readable file.
    property var daemonState: null
    // Its `ts` in ms. The daemon rewrites the file at least every 60 s, so an
    // older file is a crashed daemon's leftover, not live truth.
    property real daemonTs: 0
    readonly property bool daemonPresent: root.daemonState !== null
    readonly property bool daemonFresh: root.daemonPresent && root.daemonTs > 0
        && (root.nowTick - root.daemonTs) < 150000
    readonly property bool daemonLive: root.daemonFresh && root.daemonState.session === "connected"
    readonly property bool daemonWaiting: root.daemonFresh && root.daemonState.session === "waiting"
    property string daemonProduct: ""
    // The `session` field last applied; a waiting -> connected change is a
    // reconnect worth acknowledging in the popout.
    property string daemonSession: ""
    property bool daemonWasConnected: false
    // Bud/lid state (event 2) and the last game-mode push (event 5); both only
    // exist while a daemon is holding the link.
    property var budStatus: null
    property bool gameKnown: false
    property bool gameOn: false

    // Friendly error state derived from CLI stderr (see errfmt.js). The raw text
    // is kept in errorDetail for the (bounded) details box; the header only ever
    // shows the short errorTitle.
    property string errorTitle: ""
    property string errorHint: ""
    property string errorDetail: ""
    property string errorCode: ""
    property bool errorTransient: false

    function setError(raw) {
        const info = ErrFmt.humanize(raw);
        root.errorTitle = info.title;
        root.errorHint = info.hint;
        root.errorDetail = info.detail;
        root.errorCode = info.code;
        root.errorTransient = info.transient;
    }

    function clearError() {
        root.errorTitle = "";
        root.errorHint = "";
        root.errorDetail = "";
        root.errorCode = "";
        root.errorTransient = false;
    }

    // Drop any stale readings so a disconnected popout never shows old numbers.
    function clearLevels() {
        root.leftLevel = -1;
        root.rightLevel = -1;
        root.caseLevel = -1;
        root.leftCharging = false;
        root.rightCharging = false;
        root.caseCharging = false;
        root.batteryUpdatedAt = 0;
    }

    // The daemon is gone (or its file is unreadable): nothing it told us is
    // current any more, so drop the push-only state too.
    function clearDaemonState() {
        root.daemonState = null;
        root.daemonTs = 0;
        root.daemonProduct = "";
        root.daemonSession = "";
        root.budStatus = null;
        root.gameKnown = false;
        root.gameOn = false;
        root.gameModeSent = "";
    }

    // Apply one state.json read. Everything in it is what the device pushed to
    // the daemon, so while this file is fresh the widget never opens its own
    // RFCOMM link to read battery.
    function applyDaemonState(text) {
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            d = null;
        }
        if (!d || typeof d !== "object" || d.session === undefined) {
            root.clearDaemonState();
            return;
        }
        root.daemonState = d;
        root.daemonTs = typeof d.ts === "number" ? d.ts * 1000 : 0;
        root.daemonProduct = typeof d.product === "string" ? d.product : "";
        const previousSession = root.daemonSession;
        root.daemonSession = typeof d.session === "string" ? d.session : "";
        if (typeof d.device === "string" && d.device !== "")
            root.deviceName = d.device;      // no `device --json` needed
        if (d.session !== "connected") {
            // Waiting: the daemon owns the link and is retrying. Its last
            // numbers are not current, so never show them - and the same goes
            // for a game mode we set in the session that just ended: after a
            // reconnect only the device can say what it holds.
            root.connected = false;
            root.clearLevels();
            root.budStatus = null;
            root.gameKnown = false;
            root.gameOn = false;
            root.gameModeSent = "";
            if (d.error)
                root.setError(JSON.stringify({ error: d.error }));
            return;
        }
        root.connected = true;
        const battery = d.battery || {};
        const level = key => (battery[key] && typeof battery[key].level === "number")
            ? battery[key].level : -1;
        const charging = key => !!(battery[key] && battery[key].charging);
        root.leftLevel = level("left");
        root.rightLevel = level("right");
        root.caseLevel = level("case");
        root.leftCharging = charging("left");
        root.rightCharging = charging("right");
        root.caseCharging = charging("case");
        root.budStatus = d.status || null;
        root.batteryUpdatedAt = (typeof d.updated === "number" && d.updated > 0)
            ? d.updated * 1000 : root.daemonTs;
        if (d.game) {
            // The device pushed it (event 5), so real state beats what we sent.
            root.gameKnown = true;
            root.gameOn = !!d.game.on;
            root.gameModeSent = "";
        }
        if (previousSession === "waiting" && root.daemonWasConnected) {
            // The daemon rebuilt the link after a drop: say so, so a recovery
            // is visible without reading the journal.
            root.status = "Reconnected";
            statusResetTimer.restart();
        }
        root.daemonWasConnected = true;
        root.clearError();
        root.loadGestureSlots();
    }

    function togglePillStyle() {
        root.pillStyle = root.pillStyle === "full" ? "compact" : "full";
        PluginService.savePluginData("melodyctl", "pillStyle", root.pillStyle);
    }

    // --- serialized CLI runner (one RFCOMM connection at a time) -------------
    // The buds accept a single RFCOMM connection, so every melodyctl call goes
    // through one queue rather than racing separate Process objects (which is
    // what produced spurious "Device or resource busy").
    property var cliQueue: []
    property bool cliBusy: false
    property var cliCurrent: null
    property string cliOut: ""
    property string cliErr: ""

    function runCli(args, onDone) {
        if (!root.cliAvailable) {
            root.ensureCli();
            return;
        }
        const key = args.join(" ");
        if (root.cliCurrent && root.cliCurrent.key === key)
            return;                                   // same request already running
        for (let i = 0; i < root.cliQueue.length; ++i)
            if (root.cliQueue[i].key === key)
                return;                               // same request already queued
        root.cliQueue = root.cliQueue.concat([{ args: args, key: key, onDone: onDone }]);
        root.pumpCli();
    }

    function pumpCli() {
        if (root.cliBusy || root.cliQueue.length === 0)
            return;
        const req = root.cliQueue[0];
        root.cliQueue = root.cliQueue.slice(1);
        root.cliBusy = true;
        root.cliCurrent = req;
        root.cliOut = "";
        root.cliErr = "";
        cliProcess.command = root.cliArgs(req.args);
        cliProcess.running = true;
    }

    // --- freshness ------------------------------------------------------------
    property bool batteryRefreshing: false
    property real batteryUpdatedAt: 0
    property bool popoutVisible: false
    property real nowTick: Date.now()

    readonly property string freshnessText: {
        if (!root.cliAvailable)
            return "";
        if (root.batteryRefreshing)
            return "Refreshing…";
        if (root.batteryUpdatedAt <= 0)
            return "";
        const secs = Math.round((root.nowTick - root.batteryUpdatedAt) / 1000);
        if (secs < 5)
            return "Updated just now";
        if (secs < 60)
            return "Updated " + secs + "s ago";
        return "Updated " + Math.floor(secs / 60) + "m ago";
    }

    property var gestureRows: []
    // Optimistic game-mode value: only used when the buds have not told us
    // anything (with a daemon they push event 5, which wins over this).
    property string gameModeSent: ""
    property bool gesturesExpanded: false

    // Live state (event 2) - bud in case / in ear and the case lid.
    readonly property string budStatusText: {
        const st = root.budStatus;
        if (!st)
            return "";
        const parts = [];
        const side = (key, label) => {
            const s = st[key];
            if (!s)
                return;
            parts.push(label + (s.in_ear ? " in ear" : (s.in_case ? " in case" : " out")));
        };
        side("left", "Left");
        side("right", "Right");
        // The case entry only carries the lid flag (its in-case/in-ear bits are
        // not meaningful) - see docs/protocol/commands/notifications.md.
        if (st.case)
            parts.push("Lid " + (st.case.cover_open ? "open" : "closed"));
        return parts.join(" · ");
    }
    readonly property string gameModeNote: {
        if (root.gameKnown)
            return "Reported by the buds.";
        if (root.gameModeSent !== "")
            return "Last set here; the buds have not reported it back yet.";
        return "Not reported by the buds yet.";
    }
    readonly property int gameModeIndex: root.gameKnown
        ? (root.gameOn ? 0 : 1)
        : (root.gameModeSent === "on" ? 0 : (root.gameModeSent === "off" ? 1 : -1))

    readonly property bool hasData: leftLevel >= 0 || rightLevel >= 0 || caseLevel >= 0
    readonly property string leftCell: leftLevel < 0 ? "–" : String(leftLevel)
    readonly property string rightCell: rightLevel < 0 ? "–" : String(rightLevel)
    readonly property string caseCell: caseLevel < 0 ? "–" : String(caseLevel)
    readonly property string pillText: !cliAvailable
        ? (cliChecked ? "setup" : "…")
        : (hasData ? leftCell + "·" + rightCell + "·" + caseCell : "--")

    // Dim the pill while the earbuds are unreachable so the state is obvious.
    readonly property color pillIconColor: root.connected
        ? (Theme.widgetIconColor || Theme.primary)
        : Theme.withAlpha(Theme.widgetIconColor || Theme.primary, 0.45)
    readonly property color pillTextColor: root.connected
        ? (Theme.widgetTextColor || Theme.surfaceText)
        : Theme.withAlpha(Theme.widgetTextColor || Theme.surfaceText, 0.6)

    readonly property string statusLine: {
        if (!root.cliAvailable)
            return root.cliError !== "" ? root.cliError : "melodyctl CLI not found";
        if (root.errorTitle !== "")
            return root.errorTitle;
        if (root.connected)
            return root.status !== "" ? root.status
                : (root.daemonLive ? "Push updates via melodyctl daemon" : "Live battery + controls");
        if (root.daemonWaiting)
            return "Waiting for the earbuds (daemon)";
        return "Earbuds not connected";
    }

    // After a control action the header line shows the CLI's acknowledgement
    // for a few seconds, then falls back to the default status line.
    property int ackTimeout: 7000

    Timer {
        id: statusResetTimer

        interval: root.ackTimeout
        repeat: false
        onTriggered: root.status = ""
    }

    // Resolve the CLI in one shell probe: honour an override, else PATH, else dev path.
    readonly property string resolveScript: [
        'if [ -n "$1" ]; then',
        '  if command -v "$1" >/dev/null 2>&1 || [ -f "$1" ]; then printf "%s" "$1"; exit 0; fi',
        '  printf "MISSING_OVERRIDE"; exit 0',
        'fi',
        'if command -v melodyctl >/dev/null 2>&1; then printf "%s" "$(command -v melodyctl)"; exit 0; fi',
        'if [ -x "$HOME/.local/bin/melodyctl" ]; then printf "%s" "$HOME/.local/bin/melodyctl"; exit 0; fi',
        'if [ -f "$2" ]; then printf "%s" "$2"; exit 0; fi',
        'printf "NONE"'
    ].join("\n")

    function cliArgs(rest) {
        const base = root.cliIsScript ? ["python3", root.cliPath] : [root.cliPath];
        return base.concat(rest);
    }

    function resolveCli() {
        if (resolveProcess.running)
            return;
        resolveProcess.command = ["sh", "-c", root.resolveScript, "sh", root.commandOverride, root.devFallback];
        resolveProcess.running = true;
    }

    function ensureCli() {
        if (!root.cliChecked && !resolveProcess.running)
            root.resolveCli();
    }

    function onResolved(result) {
        root.cliChecked = true;
        if (result === "" || result === "NONE" || result === "MISSING_OVERRIDE") {
            root.cliAvailable = false;
            root.cliPath = "";
            root.cliError = result === "MISSING_OVERRIDE"
                ? "melodyctl not found at the configured command/path"
                : "melodyctl CLI not found";
            return;
        }
        root.cliPath = result;
        root.cliIsScript = result.endsWith(".py");
        root.cliAvailable = true;
        root.cliError = "";
        root.checkVersion();
        root.refresh();
        root.loadGestures();
        // state.json may have been read before we knew where the CLI is; try
        // the slot table again now (it no-ops unless a product id is known).
        root.loadGestureSlots();
    }

    function checkVersion() {
        root.runCli(["--version"], res => {
            if (res.code === 0 && res.out !== "")
                root.cliVersion = res.out.replace("melodyctl ", "");
        });
    }

    // --- gesture decoding for the popout ------------------------------------
    readonly property var leftGestures: root.gestureRows.filter(r => r.ear === "left" && r.action >= 1 && r.action <= 4)
    readonly property var rightGestures: root.gestureRows.filter(r => r.ear === "right" && r.action >= 1 && r.action <= 4)

    // Map a gesture function id to a Material Symbols glyph / label. Ids come
    // from the device tables (0 none, 1 play/pause, 3 assistant, 5 prev,
    // 6 next, 11 vol+, 12 vol-, 17 game mode).
    function functionIcon(id) {
        switch (id) {
        case 0:
            return "block";
        case 1:
            return "play_arrow";
        case 3:
            return "mic";
        case 5:
            return "skip_previous";
        case 6:
            return "skip_next";
        case 11:
            return "volume_up";
        case 12:
            return "volume_down";
        case 17:
            return "sports_esports";
        default:
            return "graph_2";
        }
    }

    function functionLabel(id) {
        switch (id) {
        case 0:
            return "None";
        case 1:
            return "Play/pause";
        case 3:
            return "Voice assistant";
        case 5:
            return "Previous song";
        case 6:
            return "Next song";
        case 11:
            return "Volume up";
        case 12:
            return "Volume down";
        case 17:
            return "Game mode";
        default:
            return root.functionNameFromVocabulary(id);
        }
    }

    // Names come from `gesture-set --list --json`'s vocabulary, so an id this
    // widget has no glyph for still reads as something.
    function functionNameFromVocabulary(id) {
        const name = root.gestureFunctionNames[String(id)];
        return (name && name.length > 0) ? name : ("Function " + id);
    }

    // --- gesture options (whitelist-driven, no RFCOMM) -----------------------
    // `gesture-set --list --json --product <id>` is offline: it resolves the
    // product's allowed (action -> function) pairs from the decrypted whitelist,
    // so the editor shows exactly what that model can be written with. Writing
    // anything else is refused by the CLI's own pre-flight check.
    property var gestureSlots: []
    property var gestureFunctionNames: ({})
    property string gestureSlotsFor: ""

    function loadGestureSlots() {
        const pid = root.daemonProduct !== "" ? root.daemonProduct : root.deviceId;
        if (pid === "" || pid === root.gestureSlotsFor)
            return;
        root.runCli(["gesture-set", "--list", "--json", "--product", pid], res => {
            if (res.code !== 0 || res.out === "")
                return;                     // older CLI: editor stays read-only
            let d = null;
            try {
                d = JSON.parse(res.out);
            } catch (e) {
                d = null;
            }
            if (!d || !Array.isArray(d.slots))
                return;
            const names = {};
            const vocab = (d.vocabulary && d.vocabulary.functions) || [];
            for (let i = 0; i < vocab.length; ++i)
                names[String(vocab[i].id)] = vocab[i].name;
            root.gestureSlots = d.slots;
            root.gestureFunctionNames = names;
            root.gestureSlotsFor = pid;
        });
    }

    // Function ids the whitelist allows for this (button, action). Presets the
    // app offers but has no wire code for (function: null) are dropped: the CLI
    // cannot write them either.
    function gestureOptions(button, action) {
        for (let i = 0; i < root.gestureSlots.length; ++i) {
            const slot = root.gestureSlots[i];
            if (slot.action !== action || (slot.button || 1) !== (button || 1))
                continue;
            const out = [];
            const fns = slot.functions || [];
            for (let k = 0; k < fns.length; ++k) {
                const code = fns[k].function;
                if (code === null || code === undefined || out.indexOf(code) !== -1)
                    continue;
                out.push(code);
            }
            return out;
        }
        return [];
    }

    // Only one gesture row may be expanded at a time ("ear:action").
    property string expandedGesture: ""

    function toggleGestureEditor(key) {
        root.expandedGesture = root.expandedGesture === key ? "" : key;
    }

    function setGestureFor(row, fn) {
        if (!row)
            return;
        root.runControl(["gesture-set", String(row.ear), String(row.button), String(row.action), String(fn)],
                        row.action_name + " → " + root.functionLabel(fn));
        root.expandedGesture = "";
    }

    onConnectedChanged: {
        if (!root.connected)
            root.expandedGesture = "";
    }

    Component.onCompleted: root.resolveCli()

    Connections {
        target: PluginService
        ignoreUnknownSignals: true

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== "melodyctl")
                return;
            root.pillStyle = PluginService.loadPluginData("melodyctl", "pillStyle", "compact");
            root.pollInterval = parseInt(PluginService.loadPluginData("melodyctl", "pollInterval", "120"), 10);
            // Only re-resolve the CLI when the command/path actually changed, so a
            // pill-style flip doesn't spawn extra probes.
            const newCommand = PluginService.loadPluginData("melodyctl", "command",
                    PluginService.loadPluginData("melodyctl", "scriptPath", ""));
            if (newCommand !== root.commandOverride) {
                root.commandOverride = newCommand;
                root.cliChecked = false;
                root.cliAvailable = false;
                root.deviceName = "";
                root.deviceId = "";
                root.gestureSlots = [];
                root.gestureSlotsFor = "";
                root.resolveCli();
            }
        }
    }

    // With no daemon this polls the CLI; with one it just re-reads the state
    // file (the file watch normally beats it to it), so the interval is a
    // safety net rather than an RFCOMM poll.
    Timer {
        interval: Math.max(15, root.pollInterval) * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Tick the "updated Xs ago" label, but only while the popout is open.
    Timer {
        interval: 1000
        repeat: true
        running: root.popoutVisible
        onTriggered: root.nowTick = Date.now()
    }

    // A gesture read can lose the race with the battery read for the buds'
    // single RFCOMM connection, so retry once while the popout is open.
    Timer {
        id: gestureRetryTimer

        interval: 700
        repeat: false
        onTriggered: root.loadGestures(false)
    }

    Process {
        id: resolveProcess

        stdout: StdioCollector {
            onStreamFinished: root.onResolved(text.trim())
        }
    }

    // Single worker for all CLI calls; requests run one at a time (see runCli).
    Process {
        id: cliProcess

        stdout: StdioCollector {
            onStreamFinished: root.cliOut = text
        }
        stderr: StdioCollector {
            onStreamFinished: root.cliErr = text
        }
        onExited: code => {
            const req = root.cliCurrent;
            root.cliBusy = false;
            root.cliCurrent = null;
            if (req && req.onDone)
                req.onDone({ code: code, out: root.cliOut.trim(), err: root.cliErr.trim() });
            root.pumpCli();
        }
    }

    // The daemon's state file. Watch it so a push shows up as soon as it is
    // written; atomic writes (tmp + rename) can defeat a file watch, so
    // refresh() also reloads it on the poll interval.
    FileView {
        id: stateView

        path: root.daemonStatePath
        watchChanges: root.daemonStatePath !== ""
        printErrors: false
        onLoaded: root.applyDaemonState(text())
        onFileChanged: stateView.reload()
        onLoadFailed: root.clearDaemonState()
    }

    // The model label / product id are fetched once per session (and again if
    // the CLI is re-resolved) so every poll doesn't need its own round-trip.
    // With a daemon these come from state.json instead.
    function loadDeviceName(force) {
        if (!force && root.deviceName !== "" && root.deviceId !== "")
            return;
        root.runCli(["device", "--json"], res => {
            if (res.code !== 0 || res.out === "")
                return;
            try {
                const d = JSON.parse(res.out);
                if (d && typeof d.name === "string" && d.name !== "")
                    root.deviceName = d.name;
                if (d && typeof d.id === "string" && d.id !== "")
                    root.deviceId = d.id;
                root.loadGestureSlots();
            } catch (e) {
                // keep the fallback label
            }
        });
    }

    function refresh() {
        root.nowTick = Date.now();
        if (!root.cliAvailable) {
            root.ensureCli();
            return;
        }
        if (root.daemonFresh) {
            // The daemon owns the link and this file is current: re-read it
            // rather than opening a second RFCOMM connection of our own.
            stateView.reload();
            return;
        }
        root.pollBattery();
    }

    // The manual read: ask for the battery now, through whoever owns the link.
    // With a daemon running the CLI request goes over its socket (one device
    // read, no second connection), and while the daemon is waiting the same
    // request makes it try again immediately instead of waiting out its backoff.
    function pollBattery() {
        if (!root.cliAvailable) {
            root.ensureCli();
            return;
        }
        root.batteryRefreshing = true;
        root.runCli(["battery", "--json-full"], res => {
            root.batteryRefreshing = false;
            if (res.code === 0 && res.out !== "") {
                try {
                    const data = JSON.parse(res.out);
                    const level = key => (data[key] && typeof data[key].level === "number")
                        ? data[key].level : -1;
                    const charging = key => !!(data[key] && data[key].charging);
                    root.leftLevel = level("left");
                    root.rightLevel = level("right");
                    root.caseLevel = level("case");
                    root.leftCharging = charging("left");
                    root.rightCharging = charging("right");
                    root.caseCharging = charging("case");
                    root.connected = true;
                    root.batteryUpdatedAt = Date.now();
                    root.clearError();
                    root.loadDeviceName(false);
                } catch (e) {
                    root.connected = false;
                    root.clearLevels();
                }
            } else {
                root.connected = false;
                root.clearLevels();
                if (res.err !== "")
                    root.setError(res.err);
            }
        });
    }

    function loadGestures(allowRetry) {
        root.runCli(["gestures", "--json"], res => {
            let parsed = null;
            if (res.code === 0 && res.out !== "") {
                try {
                    parsed = JSON.parse(res.out);
                } catch (e) {
                    parsed = null;
                }
            }
            if (parsed !== null) {
                root.gestureRows = parsed;
                return;
            }
            if (allowRetry !== false && root.popoutVisible)
                gestureRetryTimer.restart();
        });
    }

    // `ack` optionally overrides the acknowledgement shown in the header line.
    function runControl(args, ack) {
        root.runCli(args, res => {
            const out = (res.out || "").trim();
            const message = ack !== undefined ? ack : out;
            if (message !== "") {
                root.status = message;
                statusResetTimer.restart();
            }
            if (res.code === 0) {
                root.clearError();
                if (args[0] === "gesture-set")
                    root.loadGestures();   // the gesture table changed
            } else if (res.err !== "") {
                root.setError(res.err);
            }
        });
    }

    component SectionLabel: StyledText {
        font.pixelSize: Theme.fontSizeSmall - 1
        font.weight: Font.Bold
        font.letterSpacing: 1.3
        font.capitalization: Font.AllUppercase
        color: Theme.surfaceVariantText
    }

    component BatteryGauge: Item {
        id: gauge

        required property string label
        required property string iconName
        required property int value
        property bool known: false
        property bool charging: false

        readonly property int pct: gauge.value < 0 ? 0 : Math.min(100, gauge.value)
        readonly property color accent: !gauge.known
            ? Theme.surfaceVariantText
            : (gauge.value <= 15 ? Theme.error : (gauge.value <= 30 ? Theme.warning : Theme.primary))

        implicitHeight: gaugeCol.implicitHeight

        Column {
            id: gaugeCol

            width: parent.width
            spacing: Theme.spacingXS

            Item {
                width: parent.width
                height: Theme.iconSize + 8

                DankIcon {
                    anchors.centerIn: parent
                    name: gauge.iconName
                    size: Theme.iconSize + 2
                    color: gauge.accent
                    opacity: gauge.known ? 1 : 0.45

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }

                // Charging comes either way: from the daemon's push data, or
                // from the CLI poll (battery --json-full).
                DankIcon {
                    name: "bolt"
                    size: 12
                    visible: gauge.known && gauge.charging
                    color: Theme.primary
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: gauge.known ? gauge.value + "%" : "–"
                font.pixelSize: Theme.fontSizeLarge + 1
                font.weight: Font.Bold
                color: gauge.known ? Theme.surfaceText : Theme.surfaceVariantText
                opacity: gauge.known ? 1 : 0.55

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }
            }

            StyledRect {
                width: parent.width
                height: 4
                radius: 2
                color: Theme.withAlpha(Theme.surfaceVariantText, 0.16)

                StyledRect {
                    height: parent.height
                    radius: parent.radius
                    width: gauge.known ? parent.width * gauge.pct / 100 : 0
                    color: gauge.accent

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: gauge.label
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.surfaceVariantText
            }
        }
    }

    component GestureRow: Item {
        id: gRow

        required property var row          // decoded CLI gesture row

        readonly property string rowKey: gRow.row ? (gRow.row.ear + ":" + gRow.row.action) : ""
        readonly property bool expanded: root.expandedGesture === gRow.rowKey
        // Options come from the connected model's whitelist slots (offline).
        readonly property var options: root.gestureOptions(gRow.row ? gRow.row.button : 1,
                                                           gRow.row ? gRow.row.action : 0)
        readonly property bool editable: gRow.options.length > 0

        width: parent ? parent.width : 0
        height: headerItem.height + (gRow.expanded ? optionsCol.implicitHeight + Theme.spacingXS : 0)
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: Theme.mediumDuration
                easing.type: Theme.standardEasing
            }
        }

        Item {
            id: headerItem

            width: parent.width
            height: 26

            StyledText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: gRow.row ? gRow.row.action_name : ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            RowLayout {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                DankIcon {
                    name: root.functionIcon(gRow.row ? gRow.row.function : -1)
                    size: 14
                    color: Theme.surfaceText
                    Layout.alignment: Qt.AlignVCenter
                }

                StyledText {
                    text: root.functionLabel(gRow.row ? gRow.row.function : -1)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    Layout.alignment: Qt.AlignVCenter
                }

                DankIcon {
                    visible: gRow.editable
                    name: "expand_more"
                    size: 14
                    color: Theme.surfaceVariantText
                    rotation: gRow.expanded ? 180 : 0
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on rotation {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.connected && gRow.editable
                hoverEnabled: true
                cursorShape: (root.connected && gRow.editable) ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.toggleGestureEditor(gRow.rowKey)
            }
        }

        Column {
            id: optionsCol

            width: parent.width
            y: headerItem.height
            spacing: 2

            Repeater {
                model: gRow.options

                delegate: Item {
                    id: optionRow

                    required property int modelData

                    readonly property bool current: gRow.row !== null && gRow.row.function === optionRow.modelData

                    width: optionsCol.width
                    height: 26

                    StyledRect {
                        anchors.fill: parent
                        radius: 6
                        color: optionMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.14) : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.shorterDuration
                            }
                        }
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.functionIcon(optionRow.modelData)
                            size: 14
                            color: optionRow.current ? Theme.primary : Theme.surfaceText
                            Layout.alignment: Qt.AlignVCenter
                        }

                        StyledText {
                            text: root.functionLabel(optionRow.modelData)
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: optionRow.current ? Font.Medium : Font.Normal
                            color: optionRow.current ? Theme.primary : Theme.surfaceText
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                        }

                        DankIcon {
                            visible: optionRow.current
                            name: "check"
                            size: 14
                            color: Theme.primary
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    MouseArea {
                        id: optionMouse

                        anchors.fill: parent
                        enabled: root.connected
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setGestureFor(gRow.row, optionRow.modelData)
                    }
                }
            }
        }
    }

    horizontalBarPill: Component {
        RowLayout {
            spacing: Theme.spacingXS

            DankIcon {
                name: "earbuds"
                size: root.iconSize
                color: root.pillIconColor
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                visible: root.pillStyle === "full"
                text: root.pillText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.Medium
                color: root.pillTextColor
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "earbuds"
            size: root.iconSize
            color: root.pillIconColor
            anchors.centerIn: parent
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot

            headerText: root.deviceLabel
            // The status line is rendered below (monospace + smaller) so it can be
            // styled, so the built-in details line stays empty.
            detailsText: ""
            showCloseButton: true

            headerActions: Component {
                DankActionButton {
                    iconName: "refresh"
                    iconColor: root.batteryRefreshing ? Theme.primary : Theme.surfaceText
                    tooltipText: "Refresh"
                    onClicked: {
                        // A real read, not just a file reload: with a daemon the
                        // CLI asks it for one, so the button means the same
                        // thing whether or not one is running.
                        root.pollBattery();
                        root.loadGestures();
                    }
                }
            }

            // Refresh whenever the popout opens, so it never shows stale data.
            readonly property bool popoutNow: parentPopout ? parentPopout.shouldBeVisible : false

            // The popout is anchored under the bar and DMS never clamps it, so
            // bound the scrolling area to what actually fits on screen.
            readonly property var popupScreen: parentPopout ? parentPopout.screen : null
            readonly property real maxScrollHeight: {
                if (!popupScreen || !popupScreen.height)
                    return 0;
                return Math.max(240, popupScreen.height - 188);
            }

            onPopoutNowChanged: {
                root.popoutVisible = popoutNow;
                if (popoutNow) {
                    scroller.contentY = 0;
                    root.nowTick = Date.now();
                    root.refresh();
                    root.loadGestures();
                    contentCol.shown = false;
                    entranceTimer.restart();
                }
            }

            Component.onCompleted: {
                root.popoutVisible = popoutNow;
                contentCol.shown = true;
            }

            Timer {
                id: entranceTimer

                interval: 16
                repeat: false
                onTriggered: contentCol.shown = true
            }

            Column {
                id: contentCol

                width: parent.width
                spacing: Theme.spacingM

                property bool shown: true

                opacity: contentCol.shown ? 1 : 0
                transform: Translate {
                    y: contentCol.shown ? 0 : 12

                    Behavior on y {
                        NumberAnimation {
                            duration: Theme.mediumDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }

                // Status / acknowledgement line (under the title).
                StyledText {
                    width: parent.width
                    leftPadding: Theme.spacingS
                    text: root.statusLine
                    isMonospace: true
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                DankFlickable {
                    id: scroller

                    width: parent.width
                    height: popoutRoot.maxScrollHeight > 0 ? Math.min(scrollCol.implicitHeight, popoutRoot.maxScrollHeight) : scrollCol.implicitHeight
                    contentWidth: width
                    contentHeight: scrollCol.implicitHeight
                    clip: true
                    interactive: contentHeight > height

                    Column {
                        id: scrollCol

                        width: scroller.width
                        spacing: Theme.spacingM

                        // --- resolving CLI -------------------------------------------------
                        RowLayout {
                            width: parent.width
                            visible: !root.cliChecked
                            spacing: Theme.spacingS

                            DankSpinner {
                                size: 16
                                running: true
                                color: Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                text: "Looking for melodyctl…"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                            }
                        }

                        // --- CLI missing ---------------------------------------------------
                        StyledRect {
                            width: parent.width
                            visible: root.cliChecked && !root.cliAvailable
                            implicitHeight: installCol.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.nestedSurface
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.warning, 0.3)

                            Column {
                                id: installCol

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    DankIcon {
                                        name: "info"
                                        size: Theme.iconSizeSmall
                                        color: Theme.warning
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: "melodyctl CLI required"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.fillWidth: true
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    text: "Install it, or set a custom command / script path in this plugin's settings."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                }

                                TextEdit {
                                    width: parent.width
                                    height: contentHeight + topPadding + bottomPadding
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.WrapAnywhere
                                    text: root.installHint
                                    color: Theme.surfaceText
                                    font.family: "monospace"
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    leftPadding: Theme.spacingS
                                    rightPadding: Theme.spacingS
                                    topPadding: Theme.spacingXS
                                    bottomPadding: Theme.spacingXS

                                    Rectangle {
                                        anchors.fill: parent
                                        z: -1
                                        radius: 6
                                        color: Theme.withAlpha(Theme.surfaceVariantText, 0.12)
                                    }
                                }
                            }
                        }

                        // --- error ---------------------------------------------------------
                        StyledRect {
                            id: errorCard

                            width: parent.width
                            visible: root.errorDetail !== "" && root.cliAvailable
                            implicitHeight: visible ? Math.min(errorCol.implicitHeight + Theme.spacingM * 2, 190) : 0
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(root.errorTransient ? Theme.surfaceVariantText : Theme.error,
                                                   root.errorTransient ? 0.1 : 0.14)
                            border.width: 1
                            border.color: Theme.withAlpha(root.errorTransient ? Theme.surfaceVariantText : Theme.error, 0.25)

                            Column {
                                id: errorCol

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    DankIcon {
                                        name: root.errorTransient ? "info" : "warning"
                                        size: Theme.iconSizeSmall
                                        color: root.errorTransient ? Theme.surfaceVariantText : Theme.error
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        width: parent.width
                                        visible: root.errorHint !== ""
                                        text: root.errorHint
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: root.errorTransient ? Theme.surfaceText : Theme.error
                                        wrapMode: Text.WordWrap
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.fillWidth: true
                                    }
                                }

                                TextEdit {
                                    width: parent.width
                                    height: Math.min(contentHeight + topPadding + bottomPadding, 110)
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.Wrap
                                    text: root.errorDetail
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    font.family: "monospace"
                                }
                            }
                        }

                        // --- battery -------------------------------------------------------
                        StyledRect {
                            width: parent.width
                            visible: root.cliAvailable
                            implicitHeight: batteryCol.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.nestedSurface
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.08)

                            Column {
                                id: batteryCol

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingXS

                                    SectionLabel {
                                        text: "Battery"
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.fillWidth: true
                                    }

                                    DankSpinner {
                                        size: 12
                                        running: root.batteryRefreshing
                                        visible: root.batteryRefreshing
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: root.freshnessText
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    BatteryGauge {
                                        Layout.fillWidth: true
                                        label: "Left"
                                        iconName: "earbud_left"
                                        value: root.leftLevel
                                        known: root.connected && root.leftLevel >= 0
                                        charging: root.leftCharging
                                    }

                                    BatteryGauge {
                                        Layout.fillWidth: true
                                        label: "Right"
                                        iconName: "earbud_right"
                                        value: root.rightLevel
                                        known: root.connected && root.rightLevel >= 0
                                        charging: root.rightCharging
                                    }

                                    BatteryGauge {
                                        Layout.fillWidth: true
                                        label: "Case"
                                        iconName: "earbud_case"
                                        value: root.caseLevel
                                        known: root.connected && root.caseLevel >= 0
                                        charging: root.caseCharging
                                    }
                                }

                                // Pushed bud/lid state (event 2): only a daemon
                                // subscriber ever sees it.
                                StyledText {
                                    width: parent.width
                                    visible: root.budStatusText !== ""
                                    text: root.budStatusText
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    color: Theme.withAlpha(Theme.surfaceVariantText, 0.85)
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // --- controls ------------------------------------------------------
                        StyledRect {
                            width: parent.width
                            visible: root.cliAvailable
                            implicitHeight: controlsCol.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.nestedSurface
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.08)

                            Column {
                                id: controlsCol

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                // Everything here needs the earbuds, so mute it when they
                                // are unreachable instead of letting taps fail silently.
                                opacity: root.connected ? 1 : 0.45

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.mediumDuration
                                        easing.type: Theme.standardEasing
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: Theme.spacingXS

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        Column {
                                            spacing: 2
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter

                                            StyledText {
                                                text: "Game mode"
                                                font.pixelSize: Theme.fontSizeMedium
                                                color: Theme.surfaceText
                                            }

                                            StyledText {
                                                text: "Low-latency audio"
                                                font.pixelSize: Theme.fontSizeSmall - 1
                                                color: Theme.surfaceVariantText
                                            }
                                        }

                                        DankButtonGroup {
                                            Layout.alignment: Qt.AlignVCenter
                                            size: "small"
                                            selectionMode: "single"
                                            enabled: root.connected
                                            model: ["On", "Off"]
                                            currentIndex: root.gameModeIndex
                                            onSelectionChanged: (index, selected) => {
                                                if (!selected)
                                                    return;
                                                root.gameModeSent = index === 0 ? "on" : "off";
                                                root.runControl(["game", root.gameModeSent]);
                                            }
                                        }
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: root.gameModeNote
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        color: Theme.withAlpha(Theme.surfaceVariantText, 0.85)
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        // --- touch gestures (collapsible) ----------------------------------
                        Column {
                            width: parent.width
                            visible: root.cliAvailable
                            spacing: Theme.spacingS

                            Item {
                                width: parent.width
                                height: 26

                                // Not reachable -> the gesture table can't be read, so
                                // keep the section collapsed and non-interactive.
                                opacity: root.connected ? 1 : 0.5

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.mediumDuration
                                        easing.type: Theme.standardEasing
                                    }
                                }

                                SectionLabel {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Touch gestures"
                                }

                                DankIcon {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "expand_more"
                                    size: Theme.iconSizeSmall
                                    color: Theme.surfaceVariantText
                                    rotation: (root.gesturesExpanded && root.connected) ? 180 : 0

                                    Behavior on rotation {
                                        NumberAnimation {
                                            duration: Theme.shortDuration
                                            easing.type: Theme.standardEasing
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: root.connected
                                    cursorShape: root.connected ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.gesturesExpanded = !root.gesturesExpanded
                                }
                            }

                            Item {
                                width: parent.width
                                height: (root.gesturesExpanded && root.connected) ? gestureCard.implicitHeight : 0
                                clip: true

                                Behavior on height {
                                    NumberAnimation {
                                        duration: Theme.mediumDuration
                                        easing.type: Theme.standardEasing
                                    }
                                }

                                StyledRect {
                                    id: gestureCard

                                    width: parent.width
                                    implicitHeight: gestureBody.implicitHeight + Theme.spacingM * 2
                                    radius: Theme.cornerRadius
                                    color: Theme.nestedSurface
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.08)

                                    Column {
                                        id: gestureBody

                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: Theme.spacingM
                                        spacing: Theme.spacingM

                                        StyledText {
                                            width: parent.width
                                            visible: root.gestureRows.length > 0
                                            text: "Tap a gesture to change what it does."
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            color: Theme.withAlpha(Theme.surfaceVariantText, 0.85)
                                        }

                                        Repeater {
                                            model: {
                                                const out = [];
                                                if (root.leftGestures.length > 0)
                                                    out.push({ "ear": "left", "icon": "earbud_left", "rows": root.leftGestures });
                                                if (root.rightGestures.length > 0)
                                                    out.push({ "ear": "right", "icon": "earbud_right", "rows": root.rightGestures });
                                                return out;
                                            }

                                            delegate: Column {
                                                required property var modelData

                                                width: gestureBody.width
                                                spacing: Theme.spacingXS

                                                RowLayout {
                                                    width: parent.width
                                                    spacing: Theme.spacingXS

                                                    DankIcon {
                                                        name: modelData.icon
                                                        size: 14
                                                        color: Theme.surfaceVariantText
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }

                                                    StyledText {
                                                        text: modelData.ear === "left" ? "Left earbud" : "Right earbud"
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        font.weight: Font.Medium
                                                        color: Theme.surfaceVariantText
                                                        Layout.alignment: Qt.AlignVCenter
                                                        Layout.fillWidth: true
                                                    }
                                                }

                                                Repeater {
                                                    model: modelData.rows

                                                    delegate: GestureRow {
                                                        required property var modelData

                                                        row: modelData
                                                    }
                                                }
                                            }
                                        }

                                        StyledText {
                                            width: parent.width
                                            visible: root.gestureRows.length === 0
                                            text: "No gesture data yet."
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                    }
                                }
                            }
                        }

                        // --- footer --------------------------------------------------------
                        StyledText {
                            width: parent.width
                            visible: root.cliAvailable && root.cliVersion !== ""
                            text: "melodyctl " + root.cliVersion
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.withAlpha(Theme.surfaceVariantText, 0.8)
                            topPadding: Theme.spacingXS
                        }
                    }
                }
            }
        }
    }
}
