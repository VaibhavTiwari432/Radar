"""status_report.py -- print this machine's configuration for copy-paste comparison.

    python status_report.py                  # the report
    python status_report.py --constants      # ONLY the shared block, for the Mac
    python status_report.py --mac FILE       # ...and diff against the Mac's block
    python status_report.py --demo           # self-check of the pure logic, no radio

NOT a check. Preflight decides GO/NO-GO; this only reports state. It never opens
a radio object, never transmits, and never writes a file, so it is safe to run at
any time and the output is stable across runs.

WHAT THIS SCRIPT WILL NOT DO
It will not print a value it cannot support. The point of the exercise is to
catch a silent mismatch between two machines, and a report that states assumed
values in the same voice as measured ones cannot do that -- it just moves the
silent mismatch into a document that LOOKS authoritative. So every line carries
a tag:

    [MEASURED]  read from hardware or from a log of this machine, this session
    [DERIVED]   computed here from a MEASURED value, arithmetic shown
    [DECLARED]  read from usrp_common.py -- true of the CODE, not of the world
    [ASSUMED]   nobody has verified this; it is an input, not a finding
    [ABSENT]    the brief asked for this and it does not exist in this tree

Same convention as common/provenance.py, and the reason CLAUDE.md Rule 1 exists.
"""
import argparse
import datetime
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
LOG_DIR = os.path.join(HERE, "logs")
WIDTH = 80

C_LIGHT = 299792458.0

# Fallbacks used ONLY if usrp_common cannot be imported. Kept identical to it.
INLINE = {"fc": 2.45e9, "fs": 1e6, "chirp_bw": 400e3, "chirp_duration": 100e-6,
          "prf": 100.0, "n_pulses": 32, "capture_window": 10.0e-3,
          "duplex_blind": 10.0}
# chirp_duration was 10e-6 here from 20 Aug until 8 Sep 2026 while
# usrp_common.PULSE_S moved to 100e-6 on 22 Aug -- a 10x drift in the one file
# whose stated job is catching drift, and invisible because the fallback only
# runs when the import that would contradict it has already failed. Fixed, and
# check_inline_drift() below now makes a recurrence loud instead of silent.
# N_PULSES moved into usrp_common.py on 20 Aug 2026 and this file kept a local
# copy until 21 Aug -- the same drift this report exists to catch. It now comes
# from load_constants() like every other number, and this fallback is used only
# when usrp_common cannot be imported at all.
N_PULSES_FALLBACK = 32

# Bench geometry, all [ASSUMED] -- this script cannot see an antenna.
ANTENNA_MODEL = "VERT2450"
ANTENNA_SEPARATION_M = 0.30
BENCH_RANGE_M = 1.5
ANTENNA_GAIN_DBI = 2.0
TX_GAIN_DB = 20        # preflight CHECK 6's test gain, NOT the payload's


def rule(char="="):
    return char * WIDTH


def field(label, value, tag=""):
    """One aligned 'Label: value [TAG]' line."""
    text = "%-24s %s" % (label, value)
    return "%s %s" % (text, tag) if tag else text


# --------------------------------------------------------------------------
# Sources
# --------------------------------------------------------------------------
def load_constants():
    """(dict, source_note). Prefers usrp_common so this cannot drift from it."""
    sys.path.insert(0, HERE)
    try:
        import usrp_common as uc
        return {"fc": uc.CENTER_FREQ, "fs": uc.RX_RATE,
                "chirp_bw": uc.CHIRP_F1 - uc.CHIRP_F0,
                "chirp_duration": uc.PULSE_S, "prf": 1.0 / uc.PRI_S,
                "n_pulses": uc.N_PULSES,
                "capture_window": uc.MAC_CAPTURE_WINDOW_S,
                "duplex_blind": uc.duplex_blind_samples()[0],
                "rx_gain": uc.RX_GAIN, "tx_gain_payload": uc.TX_GAIN,
                "frame_size": uc.FRAME_SIZE}, os.path.join(HERE, "usrp_common.py")
    except Exception as exc:
        out = dict(INLINE)
        out.update({"rx_gain": None, "tx_gain_payload": None, "frame_size": None})
        return out, "[INLINED] usrp_common.py unavailable (%s)" % exc


def check_inline_drift():
    """[] if INLINE agrees with usrp_common, else one line per disagreement.

    The fallback above is only ever READ when usrp_common cannot be imported,
    so nothing else in this file can ever notice it going stale. This is the
    only place that compares them, and demo()/main() call it.
    """
    live, src = load_constants()
    if src.startswith("[INLINED]"):
        return ["usrp_common.py did not import; INLINE could not be checked"]
    # duplex_blind is NOT a constant: usrp_common.duplex_blind_samples() scrapes
    # it out of whatever loopback logs are on this disk, so it moves for honest
    # reasons and INLINE's value is the documented no-log fallback. Comparing it
    # would report drift on every machine that has ever run a loopback.
    derived_at_runtime = {"duplex_blind"}
    return ["INLINE[%r] = %g but usrp_common gives %g" % (k, INLINE[k], live[k])
            for k in INLINE
            if k not in derived_at_runtime and k in live and INLINE[k] != live[k]]


def shared_block(fc_fs_measured):
    """usrp_common's block, or an inlined copy of it if the import failed.

    The block is what gets sent to the Mac, so it prints even when this machine
    cannot import its own constants -- but it says which case it is, because a
    block generated from INLINE describes this FILE and not the payload.
    """
    sys.path.insert(0, HERE)
    try:
        import usrp_common as uc
        return uc.shared_constants_block(fc_fs_measured=fc_fs_measured)
    except Exception as exc:
        return ["=== SHARED CONSTANTS (WINDOWS) ===",
                "# WARNING: usrp_common.py did not import (%s)." % exc,
                "# These are status_report's own fallbacks and may NOT be what the",
                "# payload transmits. Fix the import before sending this to the Mac.",
                "fc               = %ge9        # [ASSUMED] inlined" % (INLINE["fc"] / 1e9),
                "fs               = %ge6          # [ASSUMED] inlined" % (INLINE["fs"] / 1e6),
                "chirp_bw         = %ge3        # [ASSUMED] inlined"
                % (INLINE["chirp_bw"] / 1e3),
                "chirp_duration   = %ge-6        # [ASSUMED] inlined"
                % (INLINE["chirp_duration"] / 1e-6),
                "prf              = %g          # [ASSUMED] inlined" % INLINE["prf"],
                "n_pulses         = %d           # [ASSUMED] inlined"
                % N_PULSES_FALLBACK,
                "capture_window   = %ge-3         # [ASSUMED] inlined"
                % (INLINE["capture_window"] / 1e-3),
                "duplex_blind     = %-12.1f # [ASSUMED] inlined"
                % INLINE["duplex_blind"],
                "===================================="]


def uhd_state():
    """(version, serial, usb, note). Enumerates only -- never opens the device."""
    try:
        import uhd
    except ImportError as exc:
        return None, "NOT FOUND", "UNKNOWN", "uhd import failed: %s" % exc
    version = getattr(uhd, "__version__", "unknown")
    if not hasattr(uhd, "find"):
        return version, "NOT FOUND", "UNKNOWN", "bindings present but no UHD runtime"
    try:
        devices = list(uhd.find("type=b200"))
    except Exception as exc:
        return version, "NOT FOUND", "UNKNOWN", "uhd.find raised: %s" % exc
    if not devices:
        return version, "NOT FOUND", "UNKNOWN", "no B210 enumerated right now"

    serial = None
    try:
        serial = devices[0].get("serial")
    except Exception:
        pass
    if not serial:
        for token in str(devices[0]).replace(",", " ").split():
            if token.startswith("serial="):
                serial = token.split("=", 1)[1]
    # USB speed is not exposed without opening the device, and opening it is out
    # of scope here. Preflight CHECK 3 owns that question; see its docstring for
    # why even IT reports UNKNOWN on UHD 4.10.
    return version, serial or str(devices[0]), "UNKNOWN", None


def newest_preflight():
    """(dict, path) parsed from the most recent preflight log, or (None, None)."""
    try:
        logs = [os.path.join(LOG_DIR, f) for f in os.listdir(LOG_DIR)
                if f.startswith("preflight_check_") and f.endswith(".log")]
    except OSError:
        return None, None
    if not logs:
        return None, None
    path = max(logs, key=os.path.getmtime)
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    out = {"checks": {}, "verdict": None, "floor": None, "when": None}
    for num, status in re.findall(r"\[(\d)\] .*?\.{3,} (PASS|FAIL|WARN|DONE|SKIP)", text):
        out["checks"][int(num)] = status
    verdict = re.search(r"VERDICT: (.+?)\s*$", text, re.M)
    if verdict:
        out["verdict"] = verdict.group(1).strip()
    floor = re.search(r"(-?\d+\.\d+) dBFS (?:median|mean) power", text)
    if floor:
        out["floor"] = float(floor.group(1))
    stamp = re.search(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", text, re.M)
    if stamp:
        out["when"] = stamp.group(1)
    return out, path


def newest_stage_e():
    """(dict, path) parsed from the most recent Stage E log, or (None, None).

    THIS EXISTS BECAUSE THE LINE IT FEEDS WAS A HARDCODED STRING. Until 21 Aug
    this report printed "Stage E: BLOCKED - Mac never heard" from a literal, and
    kept printing it after the 20 Aug 21:45 run recorded "Mac is audible" -- so
    the one document written to stop two machines drifting apart was itself
    stating something the logs on the same disk contradicted. A status report
    that can be wrong about the state is worse than no status report, because it
    is quoted.

    Two facts are pulled out, both from lines Stage E already writes:
      "Mac is audible"           -> the precondition passed, 3+ of 10 windows
      "transmitted  N"           -> how many of the attempted pulses left
    A log that reaches neither is a run that aborted before the precondition.
    """
    try:
        logs = [os.path.join(LOG_DIR, f) for f in os.listdir(LOG_DIR)
                if f.startswith("stage_e_naive_") and f.endswith(".log")]
    except OSError:
        return None, None
    if not logs:
        return None, None
    path = max(logs, key=os.path.getmtime)
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    out = {"mac_audible": "Mac is audible" in text, "attempted": None,
           "transmitted": None, "no_pulse": None, "slot_missed": None, "when": None}
    for key, pattern in (("attempted", r"pulses attempted\s+(\d+)"),
                         ("transmitted", r"transmitted\s+(\d+)"),
                         ("slot_missed", r"slot already past\s+(\d+)"),
                         ("no_pulse", r"no pulse heard\s+(\d+)")):
        match = re.search(pattern, text)
        if match:
            out[key] = int(match.group(1))
    stamp = re.search(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", text, re.M)
    if stamp:
        out["when"] = stamp.group(1)
    return out, path


def stage_e_state(run):
    """(status, tag, notes) for the Stage E line. Pure -- see demo().

    `run` is newest_stage_e()'s dict, or None if no Stage E log exists at all.
    Four states, and the difference between the last two is the whole point:
    "the Mac was never heard" and "the Mac was heard and we transmitted nothing"
    are different blockers with different fixes, and were reported identically.
    """
    if run is None:
        return "NOT ATTEMPTED - no Stage E log", "[MEASURED]", [
            "Stage E has never been run on this machine. Nothing is claimed about",
            "the link in either direction."]
    when = run.get("when") or "unknown time"
    if not run["mac_audible"]:
        return "BLOCKED - Mac not heard in last run", "[MEASURED]", [
            "Last Stage E run (%s) never reached its precondition: fewer than 3 of" % when,
            "10 windows carried the Mac's 10.000 ms PRI. Nothing was transmitted."]
    sent, attempted = run.get("transmitted"), run.get("attempted")
    if sent is None or attempted is None:
        return "RAN - Mac heard, no result block", "[MEASURED]", [
            "Last Stage E run (%s) heard the Mac but did not reach its summary." % when]
    if sent == 0:
        return "BLOCKED - Mac heard, 0/%d transmitted" % attempted, "[MEASURED]", [
            "Last Stage E run (%s) DID hear the Mac -- the precondition passed and" % when,
            "the intercept path is proven in one direction. It then transmitted 0 of",
            "%d pulses: %s with the slot already past, %s with no pulse found in the"
            % (attempted, run.get("slot_missed"), run.get("no_pulse")),
            "frame. Both have since been addressed in code and NEITHER has been re-run:",
            "next_slot() k-PRI lookahead (stage_e_naive_drfm.py) and the matched-filter",
            "find_pulse() (usrp_common.py, 21 Aug). Until a run says otherwise, the",
            "blocker is the reply path, NOT the intercept path."]
    return "RAN - %d/%d pulses transmitted" % (sent, attempted), "[MEASURED]", [
        "Last Stage E run (%s) transmitted %d of %d pulses. Whether the Mac SAW" % (
            when, sent, attempted),
        "them is the Mac's answer to give, not this machine's."]


def find_path(*relative):
    """Absolute path if it exists, else None."""
    candidate = os.path.join(REPO, *relative)
    return candidate if os.path.exists(candidate) else None


def installed(name):
    try:
        module = __import__(name)
        return getattr(module, "__version__", "present")
    except Exception:
        return None


# --------------------------------------------------------------------------
# Pure arithmetic, unit-tested in demo()
# --------------------------------------------------------------------------
def fspl_db(distance_m, freq_hz):
    """Free-space path loss, 20*log10(4*pi*d/lambda). [DERIVED]"""
    import math
    lam = C_LIGHT / freq_hz
    return 20.0 * math.log10(4.0 * math.pi * distance_m / lam)


def dbm_to_watts(dbm):
    return 10.0 ** ((dbm - 30.0) / 10.0)


def watts_to_dbm(watts):
    import math
    return 10.0 * math.log10(watts) + 30.0


def parse_constants_block(text):
    """Pull name=value pairs out of a pasted SHARED CONSTANTS block, any case."""
    out = {}
    for line in (text or "").splitlines():
        # The trailing "# [TAG] why" the block now carries is stripped here, so
        # a block pasted from either machine still diffs cleanly.
        match = re.match(r"\s*([A-Za-z_]+)\s*=\s*([-\d.eE+]+)\s*(?:#.*)?$", line)
        if match:
            try:
                out[match.group(1).strip().lower()] = float(match.group(2))
            except ValueError:
                pass
    return out


def compare_constants(mine, theirs):
    """[(name, mine, theirs, verdict)] for every key either side declares."""
    rows = []
    for key in sorted(set(mine) | set(theirs)):
        a, b = mine.get(key), theirs.get(key)
        if a is None:
            rows.append((key, None, b, "MAC ONLY"))
        elif b is None:
            rows.append((key, a, None, "WINDOWS ONLY"))
        elif a == b:
            rows.append((key, a, b, "match"))
        else:
            rows.append((key, a, b, "MISMATCH"))
    return rows


# --------------------------------------------------------------------------
def report(mac_file=None):
    lines = []
    emit = lines.append

    const, const_source = load_constants()
    version, serial, usb, uhd_note = uhd_state()
    pre, pre_path = newest_preflight()
    run_e, e_path = newest_stage_e()
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    emit(rule())
    emit("WINDOWS DRONE GENERATOR - SYSTEM STATUS REPORT")
    emit(rule())
    emit(field("Timestamp:", now))
    emit(field("Python Version:", sys.version.splitlines()[0]))
    emit(field("UHD Version:", version or "NOT FOUND"))
    emit(field("UHD Python Bindings:",
               "PRESENT (hasattr find = %s)" % (version is not None and usb is not None)))
    emit("")
    emit("TAGS  [MEASURED] read from hardware/logs   [DERIVED] computed here")
    emit("      [DECLARED] read from code            [ASSUMED] unverified input")
    emit("      [ABSENT]   asked for, not in tree")
    emit(rule())
    emit("")

    # --- HARDWARE
    emit("HARDWARE")
    emit("-" * 8)
    emit(field("B210 Serial Number:", serial, "[MEASURED]" if serial != "NOT FOUND" else ""))
    emit(field("USB Connection:", usb,
               "[ASSUMED] not queryable without opening the device"))
    emit(field("RF A TX/RX Antenna:", "%s (declared)" % ANTENNA_MODEL, "[ASSUMED]"))
    emit(field("RF B RX2 Antenna:", "%s (declared)" % ANTENNA_MODEL, "[ASSUMED]"))
    emit(field("Antenna Separation:", "~%.0f cm, vertical" % (ANTENNA_SEPARATION_M * 100),
               "[ASSUMED]"))
    emit("")
    emit("  ! No software on this machine can identify an antenna. The three lines")
    emit("    above are what the OPERATOR declared, not what is measured. On")
    emit("    21 Aug 2026 the operator confirmed VERT2450 (2.4 GHz band) fitted,")
    emit("    superseding the 19 Aug note that recorded out-of-band VERT900s.")
    emit("    That is a spoken confirmation, not an instrument reading: only a")
    emit("    directional coupler or a power meter can settle it, and this bench")
    emit("    has neither. Treat every link-budget number below as resting on it.")
    if uhd_note:
        emit("  ! %s" % uhd_note)
    emit("")

    # --- RF CONSTANTS
    emit("RF CONSTANTS")
    emit("-" * 12)
    # Engineering notation, pinned per line, so these read the same as the
    # SHARED CONSTANTS block below and as the Mac's. "%g" alone prints fc as
    # 2.45e+09 and chirp_duration as 1e-05 -- same numbers, undiffable by eye.
    emit(field("Center Frequency (fc):", "%ge9 Hz (%.2f GHz)" % (const["fc"] / 1e9,
                                                                 const["fc"] / 1e9),
               "[DECLARED]"))
    emit(field("Sample Rate (fs):", "%ge6 Hz (%.0f MHz)" % (const["fs"] / 1e6,
                                                            const["fs"] / 1e6),
               "[DECLARED]"))
    emit(field("Chirp Bandwidth:", "%ge3 Hz (%.0f kHz)" % (const["chirp_bw"] / 1e3,
                                                           const["chirp_bw"] / 1e3),
               "[DECLARED]"))
    emit(field("Chirp Duration:", "%ge-6 s (%.0f us)" % (const["chirp_duration"] / 1e-6,
                                                         const["chirp_duration"] * 1e6),
               "[DECLARED]"))
    emit(field("PRF:", "%g Hz (PRI = %.0f ms)" % (const["prf"], 1000.0 / const["prf"]),
               "[DECLARED]"))
    emit(field("N_Pulses per Burst:", "%d (coherent)"
               % const.get("n_pulses", N_PULSES_FALLBACK),
               "[DECLARED] usrp_common.py, never checked against the Mac"))
    emit(field("Range per sample:", "%.1f m" % (C_LIGHT / (2 * const["fs"])), "[DERIVED]"))
    emit(field("Constants source:", const_source))
    emit("")

    # --- GENERATOR
    emit("GENERATOR CONFIGURATION")
    emit("-" * 23)
    emit(field("Feature Extractor:", "none in active tree", "[ABSENT]"))
    emit(field("Feature Vector Size:", "n/a", "[ABSENT]"))
    emit(field("Planner Type:", "NEITHER is wired to the radio", "[MEASURED]"))
    emit(field("Phantom Model:", "DRFM delay-amplitude-phase", "[DECLARED]"))
    emit(field("Max Phantoms per Scene:", "1 from one aperture", "[MEASURED]"))
    emit(field("TX Timing Constraint:", "%.0f ms (one PRI)" % (1000.0 / const["prf"]),
               "[DECLARED]"))
    emit(field("Measured TX latency:", "0.168-0.299 ms software loop", "[MEASURED]"))
    emit("")
    emit("  ! The brief asked for a 16-channel/8-tap polyphase filter bank and a")
    emit("    54-dimension feature vector. Neither exists here: that generator was")
    emit("    ARCHIVED on 7 Aug 2026 to trash/legacy-generator-20260807/. Reporting")
    emit("    it would describe deleted code. The active path is")
    emit("    generator/physics_projection.py -> hardware/consistent_plan.py.")
    emit("  ! Planner: generator/decision/ holds a D3QN, and Gate C is NOT MET")
    emit("    across three runs (0.97 vs 0.92 heuristic, p = 0.61). There is no CEM")
    emit("    in this tree. Neither planner feeds the payload -- the radio is driven")
    emit("    by physics_projection, not by a learned policy.")
    emit("  ! 'Max phantoms 1-3' is not available from one aperture: this project's")
    emit("    own Gate B measured 2-phantom survival collapse to 0.00 with monopulse")
    emit("    on. One B210 is a single-bearing emitter.")
    emit("")

    # --- CODE READINESS
    emit("CODE READINESS")
    emit("-" * 14)
    payload = find_path("hardware", "usrp_drone_payload.py")
    emit(field("Generator Code Path:", payload or "NOT SET"))
    emit(field("Physics Projection:",
               find_path("generator", "physics_projection.py") or "NOT SET"))
    emit(field("UHD Support:", os.environ.get("UHD_PKG_PATH", "SYSTEM-WIDE")))
    deps = []
    for name in ("numpy", "scipy", "uhd"):
        got = installed(name)
        deps.append("%s %s" % (name, got) if got else "%s MISSING" % name)
    emit(field("Python Dependencies:", ", ".join(deps)))
    emit(field("Test/Data Folder:", LOG_DIR if os.path.isdir(LOG_DIR) else "NOT SET"))
    emit(field("Shared Constants Module:", const_source))
    emit("")

    # --- LINK BUDGET
    emit("LINK BUDGET (BENCH ESTIMATE)")
    emit("-" * 28)
    path_loss = fspl_db(BENCH_RANGE_M, const["fc"])
    emit(field("TX Power (EIRP):", "UNCALIBRATED", "[ASSUMED] no power reference"))
    emit(field("TX Gain @ B210:", "%d dB (preflight test gain)" % TX_GAIN_DB, "[MEASURED]"))
    emit(field("TX Gain @ payload:", "%s dB" % (const.get("tx_gain_payload") or "?"),
               "[DECLARED]"))
    emit(field("%s Gain @ 2.45 GHz:" % ANTENNA_MODEL, "~%.0f dBi omni" % ANTENNA_GAIN_DBI,
               "[ASSUMED]"))
    emit(field("Path Loss @ %.1f m:" % BENCH_RANGE_M, "%.1f dB" % path_loss,
               "[DERIVED] 20log10(4*pi*d/lambda)"))
    if pre and pre.get("floor") is not None:
        emit(field("Measured noise floor:", "%.1f dBFS" % pre["floor"], "[MEASURED]"))
    emit(field("Expected RX SNR:", "NOT ESTIMATED", "[ASSUMED] see note"))
    emit("")
    emit("  ! Two arithmetic errors in the brief, corrected here rather than copied:")
    emit("    - '~0.1 W (-10 dBm)'. 0.1 W is +20 dBm; -10 dBm is 0.1 mW. Those differ")
    emit("      by a factor of 1000. Neither is measurable here anyway: the B210 has")
    emit("      no absolute power reference in this setup, so EIRP reads UNCALIBRATED.")
    emit("    - 'Path loss @ 1.5 m: ~60 dB'. Free-space at 2.45 GHz over 1.5 m is")
    emit("      %.1f dB, not 60. Overstating loss by ~16 dB would hide a link that is" % path_loss)
    emit("      actually working, or excuse one that is not.")
    emit("  ! Expected RX SNR is left unestimated on purpose: with EIRP uncalibrated")
    emit("    and the fitted antenna unverified, a '15-25 dB' figure would be two")
    emit("    guesses multiplied together and printed as a prediction.")
    emit("  ! The brief's phantom-success figures ('<10%' naive, '20-40%' smart) have")
    emit("    no measurement behind them. What this project DID measure, in")
    emit("    DECEPTION_MAP_RESULTS.md: 8/8 phantoms survive at 100% against a")
    emit("    SINGLE-APERTURE radar, and 0 survive at N = 2, 4 and 8 once bearing is")
    emit("    resolved. Quote those, not the placeholders.")
    emit("")

    # --- PREFLIGHT
    emit("PREFLIGHT STATUS")
    emit("-" * 16)
    if not pre:
        emit(field("Preflight:", "NOT RUN YET"))
    else:
        names = {1: "UHD Import/Version", 2: "Device Enumeration", 3: "USB Link Speed",
                 4: "USRP Object Open", 5: "Self-Noise Floor", 6: "TX Self-Test",
                 7: "Shared Constants"}
        for num in range(1, 8):
            status = pre["checks"].get(num, "<not reached>")
            extra = ""
            if num == 5 and pre.get("floor") is not None:
                extra = "  (%.1f dBFS)" % pre["floor"]
            emit(field("[%d] %s:" % (num, names[num]), "%s%s" % (status, extra)))
        emit(field("Overall Verdict:", pre["verdict"] or "unknown", "[MEASURED]"))
        emit(field("Run at:", pre["when"] or "unknown"))
        emit(field("Log:", pre_path))
        if pre["checks"].get(6, "").startswith("SKIP"):
            emit("")
            emit("  ! The newest preflight ran with --skip-tx, so the TX chain is")
            emit("    unverified in THIS log. Re-run without --skip-tx before Stage E.")
    emit("")

    # --- STAGE READINESS
    emit("STAGE READINESS")
    emit("-" * 15)
    emit(field("Stage C (Loopback):", "DONE on this machine 19 Aug", "[MEASURED]"))
    emit(field("Stage D (Corner Ref):", "NOT INVOLVED (Mac only)"))
    stage_e, stage_e_status, stage_e_notes = stage_e_state(run_e)
    emit(field("Stage E (Naive DRFM):", stage_e, stage_e_status))
    emit(field("Stage F (Real Phantom):", "BLOCKED behind E"))
    emit("")
    emit("  ! Stage C is not 'Mac only': hardware/usrp_loopback.py closed the timed-")
    emit("    transmit loop on this board on 19 Aug -- 9-sample jitter timed, against")
    emit("    131 free-running. That is the B3 blocker, measured and closed here.")
    for i, line in enumerate(stage_e_notes):
        emit("  %s %s" % ("!" if i == 0 else " ", line))
    if e_path:
        emit("    source: %s" % e_path)
    emit("")

    # --- SHARED CONSTANTS
    # ONE source for this block, shared with preflight CHECK 7. fc and fs are
    # tagged [MEASURED] only when a preflight log says CHECK 4 read them back off
    # the device; nothing here opens the radio, so this report cannot confirm
    # them itself and must not imply that it did.
    tuned = bool(pre and pre["checks"].get(4) == "PASS")
    for line in shared_block(tuned):
        emit(line)
    emit("")

    # --- MISMATCHES
    emit("CONSTANT MISMATCHES")
    emit("-" * 19)
    mine = {"fc": const["fc"], "fs": const["fs"], "chirp_bw": const["chirp_bw"],
            "chirp_duration": const["chirp_duration"], "prf": const["prf"],
            "n_pulses": float(const.get("n_pulses", N_PULSES_FALLBACK)),
            "capture_window": const.get("capture_window"),
            "duplex_blind": const.get("duplex_blind")}
    mine = {k: v for k, v in mine.items() if v is not None}
    if not mac_file:
        emit("Not yet compared - no Mac block supplied.")
        emit("Save the Mac's SHARED CONSTANTS block to a file and re-run:")
        emit("    python status_report.py --mac mac_constants.txt")
    elif not os.path.exists(mac_file):
        emit("Mac block file not found: %s" % mac_file)
    else:
        with open(mac_file, "r", encoding="utf-8", errors="replace") as handle:
            theirs = parse_constants_block(handle.read())
        if not theirs:
            emit("No 'name = value' lines found in %s" % mac_file)
        else:
            bad = 0
            for name, a, b, verdict in compare_constants(mine, theirs):
                if verdict == "match":
                    emit("  %-16s %-12g match" % (name, a))
                else:
                    bad += 1
                    emit("  %-16s WINDOWS=%-12s MAC=%-12s %s" % (
                        name, "%g" % a if a is not None else "-",
                        "%g" % b if b is not None else "-", verdict))
            emit("")
            emit("  %d mismatch(es)." % bad if bad else
                 "  All constants match the Mac's report.")
    emit("")

    emit(rule())
    emit("COPY THE ENTIRE BLOCK ABOVE AND PASTE IN CLAUDE CHAT")
    emit(rule())
    emit("Compare with the Mac's status_report output.")
    emit("Lines tagged [ASSUMED] are inputs nobody verified - check those first.")
    emit(rule())
    return "\n".join(lines)


def demo():
    """Self-check of the arithmetic and the diff. No radio, no files."""
    # INLINE must agree with usrp_common. It did not between 22 Aug and 8 Sep
    # 2026 (chirp_duration 10e-6 vs 100e-6) and nothing noticed, because the
    # fallback is only read once the import that contradicts it has failed.
    assert not check_inline_drift(), check_inline_drift()

    # Free-space loss at the bench range. The brief said ~60 dB; it is not.
    loss = fspl_db(1.5, 2.45e9)
    assert 43.0 < loss < 44.5, loss
    assert abs(fspl_db(3.0, 2.45e9) - loss - 6.02) < 0.05   # doubling d = +6 dB

    # The brief's own unit slip: 0.1 W is +20 dBm, not -10 dBm.
    assert abs(watts_to_dbm(0.1) - 20.0) < 1e-9
    assert abs(dbm_to_watts(-10.0) - 1e-4) < 1e-12

    block = ("=== SHARED CONSTANTS (MAC) ===\n"
             "FC              = 2.4e9\n"
             "FS              = 1e6\n"
             "CHIRP_BW        = 400e3\n"
             "N_PULSES        = 32\n")
    theirs = parse_constants_block(block)
    assert theirs["fc"] == 2.4e9 and theirs["n_pulses"] == 32.0, theirs

    # OUR OWN block must round-trip through that same parser, tags and all --
    # it is pasted into a file on the Mac and diffed by this code, so a block
    # the parser cannot read is a block that silently compares nothing.
    ours = parse_constants_block(chr(10).join(shared_block(True)))
    for name in ("fc", "fs", "chirp_bw", "chirp_duration", "prf", "n_pulses",
                 "capture_window", "duplex_blind"):
        assert name in ours, "%s lost to the '# [TAG]' comment: %s" % (name, sorted(ours))
    # 10e-3, the Mac's RUNTIME window, not the 2e-3 in their config.
    assert ours["capture_window"] == 10e-3, ours["capture_window"]
    # And a Mac block still carrying the withdrawn field must read MAC ONLY.
    stale = parse_constants_block("tx_gate_duration = 10e-6")
    verdicts = dict((r[0], r[3]) for r in compare_constants(ours, stale))
    assert verdicts["tx_gate_duration"] == "MAC ONLY", verdicts

    # The Stage E line must come from the log, and must tell the two blockers
    # apart. This is the regression that made it worth writing at all.
    assert "NOT ATTEMPTED" in stage_e_state(None)[0]
    never = stage_e_state({"mac_audible": False, "when": "t"})[0]
    assert "not heard" in never, never
    heard_none_sent = stage_e_state({"mac_audible": True, "attempted": 320,
                                     "transmitted": 0, "slot_missed": 93,
                                     "no_pulse": 227, "when": "2026-08-20 21:45:11"})
    assert "0/320" in heard_none_sent[0], heard_none_sent[0]
    assert any("DID hear the Mac" in n for n in heard_none_sent[2])
    ran = stage_e_state({"mac_audible": True, "attempted": 320, "transmitted": 311,
                         "when": "t"})[0]
    assert "311/320" in ran, ran

    mine = {"fc": 2.45e9, "fs": 1e6, "chirp_bw": 400e3, "prf": 100.0}
    rows = dict((r[0], r[3]) for r in compare_constants(mine, theirs))
    assert rows["fc"] == "MISMATCH", rows        # the exact trap the workflow describes
    assert rows["fs"] == "match"
    assert rows["prf"] == "WINDOWS ONLY"
    assert rows["n_pulses"] == "MAC ONLY"
    print("status_report demo: all assertions passed.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--constants", action="store_true",
                        help="print ONLY the shared constants block, for pasting "
                             "to the Mac. Nothing else, so it can be piped to a file")
    parser.add_argument("--mac", metavar="FILE",
                        help="file holding the Mac's SHARED CONSTANTS block, to diff")
    parser.add_argument("--demo", action="store_true", help="self-check, no radio")
    args = parser.parse_args()
    if args.demo:
        return demo()
    if args.constants:
        # fc/fs are only [MEASURED] if a preflight log says CHECK 4 read them
        # back off the device -- same rule as the full report, since this is the
        # same block and must not get a better tag for being printed alone.
        pre, _ = newest_preflight()
        for line in shared_block(bool(pre and pre["checks"].get(4) == "PASS")):
            print(line)
        return 0
    print(report(args.mac))
    return 0


if __name__ == "__main__":
    sys.exit(main())
