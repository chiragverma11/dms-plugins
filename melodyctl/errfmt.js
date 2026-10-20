.pragma library

// Turn raw melodyctl stderr into a short, friendly message plus the raw detail.
//
// The CLI (>= 1.2.0) emits a structured object under --json:
//   {"error": {"code": "busy", "message": "...", "hint": "..."}}
// Older versions and unexpected failures fall back to pattern matching, so the
// widget/settings never dump a raw traceback into the UI.

var TITLES_BY_CODE = {
    busy: "Earbuds busy",
    refused: "Earbuds unreachable",
    unreachable: "Earbuds unreachable",
    no_adapter: "Bluetooth is off",
    timeout: "No response from the earbuds",
    no_bluetooth_support: "Bluetooth support missing",
    disconnected: "Earbuds disconnected",
    error: "melodyctl failed"
};

var HINTS_BY_CODE = {
    busy: "Another app (e.g. HeyMelody) is using the earbuds\u2014only one connection is allowed at a time.",
    refused: "The earbuds refused the connection (off, out of range, or not paired).",
    unreachable: "The earbuds are unreachable (off or out of range).",
    no_adapter: "No Bluetooth adapter found\u2014is Bluetooth enabled?",
    timeout: "No response from the earbuds (timed out).",
    no_bluetooth_support: "melodyctl needs a system Python with Bluetooth support.",
    disconnected: "The earbuds idle, or go back in the case, and drop the link; it comes back on its own.",
    error: ""
};

// Codes that are not a failure of their own: another agent owns the link and is
// retrying, so they render as an info line rather than a red error card.
var TRANSIENT_CODES = {busy: true, disconnected: true};

function emptyResult() {
    return {title: "", hint: "", detail: "", code: "", transient: false};
}

function humanize(text) {
    var raw = (text === undefined || text === null) ? "" : String(text).trim();
    if (raw === "")
        return emptyResult();

    // 1) structured error from the CLI (--json)
    if (raw.charAt(0) === "{") {
        try {
            var obj = JSON.parse(raw);
            if (obj && obj.error) {
                var code = obj.error.code || "error";
                return {
                    title: TITLES_BY_CODE[code] || "melodyctl failed",
                    hint: obj.error.hint || HINTS_BY_CODE[code] || "",
                    detail: obj.error.message || raw,
                    code: code,
                    transient: TRANSIENT_CODES[code] === true
                };
            }
        } catch (e) {
            // not JSON after all; fall through to pattern matching
        }
    }

    // Collapse to the non-empty lines; the details box still gets the full raw text.
    var lines = raw.split("\n").map(function (l) { return l.trim(); })
        .filter(function (l) { return l !== ""; });
    var first = lines.length > 0 ? lines[0].replace(/^error:\s*/i, "") : raw;

    // 2) Python traceback -> short title, full text kept as detail
    if (raw.indexOf("Traceback (most recent call last)") !== -1) {
        return {
            title: "melodyctl crashed",
            hint: "Please report this at github.com/chiragverma11/melodyctl/issues.",
            detail: raw,
            code: "crash",
            transient: false
        };
    }

    // 3) pattern-match the common one-line failures
    function match(code) {
        return {title: TITLES_BY_CODE[code], hint: HINTS_BY_CODE[code],
                detail: first, code: code, transient: TRANSIENT_CODES[code] === true};
    }
    if (/\(Errno 16\)|resource busy/i.test(raw))
        return match("busy");
    if (/Connection reset by peer|peer closed the connection|Errno 104/i.test(raw))
        return match("disconnected");
    if (/\(Errno 111\)|connection refused/i.test(raw))
        return match("refused");
    if (/\(Errno 11[23]\)|host is down|no route to host/i.test(raw))
        return match("unreachable");
    if (/\(Errno 19\)|no such device/i.test(raw))
        return match("no_adapter");
    if (/AF_BLUETOOTH/i.test(raw))
        return match("no_bluetooth_support");

    return {title: "melodyctl failed", hint: "", detail: first,
            code: "error", transient: false};
}
