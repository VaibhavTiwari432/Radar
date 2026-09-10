"""preflight_check.py -- seven checks that must pass before Stage E goes on air.

    python preflight_check.py            # all seven, prompts once before keying TX
    python preflight_check.py --yes      # ...without the transmit prompt
    python preflight_check.py --skip-tx  # checks 1-5 and 7, never keys the PA
    python preflight_check.py --demo     # verdict logic self-check, no radio

Read-only apart from CHECK 6, which keys the transmitter for 5 ms at low gain.
No check runs an open-ended loop; the whole run is bounded by the UHD timeouts.

WHY THIS IMPORTS usrp_common RATHER THAN RESTATING THE CONSTANTS
The shared RF numbers CHECK 7 prints are the ones usrp_drone_payload.py
schedules against. A preflight with its own copy would happily print a matching
block while the payload used different numbers -- the exact failure verify_mac.py
was written to avoid. 21 Aug 2026: the last exception, a local N_PULSES = 32,
was deleted. It had a home in usrp_common from 20 Aug and this file kept its own
copy for a day, which is precisely the drift the paragraph above warns about.
CHECK 7 now prints uc.shared_constants_block(), the same eight lines
status_report.py prints, so there is one block on this machine and not three.

THREE PLACES THIS DEPARTS FROM THE BRIEF, EACH FOR A MEASURED REASON
1. CHECK 3 (USB speed) is a WARNING, not a hard failure. MEASURED 18 Aug: this
   board negotiates USB 2 on the cable in use. At fs = 1 Msps the link carries
   4 MB/s against ~35 MB/s available, so it affects no Stage E number. Failing
   hard here would NO-GO every run and skip checks 4-7, which is worse than
   useless. It escalates to a hard failure automatically if fs is ever raised
   past what USB 2 can carry -- see usb_verdict().
2. CHECK 5's pass band is -80..-55 dBFS, not the brief's -60..-30, and it tests
   the MEDIAN power rather than the mean. MEASURED 18-19 Aug with nothing
   transmitting: -69.8 to -70.6 dBFS, so the brief's band would fail every
   honest run. MEASURED 20 Aug: the mean drifts with 2.45 GHz ISM ambient
   (-68.5 -> -62.5 over one evening, board untouched) while the median holds at
   -71.2 to -72.2 -- see floor_verdict().
3. CHECK 6 still asks for the antenna confirmation. The brief says no cable is
   required, which is true -- nothing needs to receive this burst -- but keying
   a bare port is the one action here that can damage hardware.
"""
import argparse
import logging
import sys

import numpy as np

import usrp_common as uc

MIN_UHD_MAJOR = 4

# CHECK 5 band. [MEASURED 18-19 Aug 2026, this bench, nothing transmitting]
# -69.8, -70.3, -70.4, -70.6, -70.1 dBFS at 30 dB RX gain.
NOISE_FLOOR_MIN_DBFS = -80.0   # below this, the front end is not really listening
NOISE_FLOOR_MAX_DBFS = -55.0   # above this, something is transmitting or gain is wrong
NOISE_FLAT_DBFS = -120.0       # a true flatline: dead channel, not thermal noise

# CHECK 6. Deliberately far below the payload's TX_GAIN=30 and its 0.8 peak.
TX_TEST_GAIN_DB = 20
TX_TEST_AMPLITUDE = 0.2
TX_TEST_DURATION_S = 5e-3
TX_TEST_TONE_HZ = 100e3        # inside the 400 kHz chirp span, off DC to dodge LO leakage

PASS, FAIL, WARN, INFO = "PASS", "FAIL", "WARN", "DONE"


class Result:
    """One check's outcome. `hard` records that later checks depend on this one."""

    def __init__(self, num, name, status, detail, fallback=None, hard=False,
                 value=None):
        self.num, self.name = num, name
        self.status, self.detail = status, detail
        self.fallback, self.hard = fallback, hard
        # The one NUMBER this check measured, carried separately from the prose
        # so summary() can print a machine-readable line without re-parsing its
        # own detail string. None for checks that measure nothing.
        self.value = value

    @property
    def blocking(self):
        return self.status == FAIL

    def emit(self):
        logging.info("[CHECK %d] %s ... %s", self.num, self.name, self.status)
        logging.info("    %s", self.detail)
        if self.fallback:
            label = "FALLBACK" if self.status == FAIL else "NOTE"
            for i, line in enumerate(self.fallback.splitlines()):
                logging.info("    %s%s", (label + ": ") if i == 0 else "          ", line)


def usb_verdict(speed_text, rate_hz):
    """(status, detail, fallback) for a USB link description. Pure -- see demo().

    4 bytes/sample on the wire (sc16), one direction at a time for these checks.
    USB 2 sustains roughly 35 MB/s in practice, USB 3 roughly 300 MB/s.
    """
    need_mbps = rate_hz * 4 / 1e6
    text = (speed_text or "").lower()
    if "super" in text or "usb 3" in text or "3.0" in text:
        return PASS, "SuperSpeed (USB 3.0), %.0f MB/s needed at fs=%.0f kHz" % (
            need_mbps, rate_hz / 1e3), None

    known_usb2 = "high" in text or "usb 2" in text or "2.0" in text
    label = "High-Speed (USB 2.0)" if known_usb2 else "UNKNOWN (%s)" % (speed_text or "no hint")
    if need_mbps > 30.0:
        return FAIL, "%s cannot carry %.0f MB/s at fs=%.0f kHz" % (
            label, need_mbps, rate_hz / 1e3), (
            "You are on a USB 2.0 port or hub and the configured sample rate needs more "
            "than it can carry.\nMove to a USB 3.0 (blue) port, remove any hub, and use a "
            "USB 3.0 cable.")
    return WARN, "%s -- carries ~35 MB/s, needs %.0f MB/s at fs=%.0f kHz, so it does not "\
                 "bind here" % (label, need_mbps, rate_hz / 1e3), (
        "Not blocking at this sample rate, but it caps fs and must be fixed before raising "
        "it.\nMEASURED 18 Aug: this board reported 'Operating over USB 2' on a USB 3.0 root "
        "hub, which\nmeans the CABLE is USB-2-only. Swap the cable, not just the port.")


def floor_verdict(dbfs, mean_dbfs=None):
    """(status, detail, fallback) for a measured noise floor. Pure -- see demo().

    `dbfs` is the MEDIAN instantaneous power, not the mean, and the difference
    decides whether this check works. MEASURED 20 Aug 2026, three runs across one
    evening on an untouched board: mean power drifted -68.5 -> -64.8 -> -62.5 dBFS
    against a -55 ceiling, purely from 2.45 GHz ISM ambient rising, while the
    median sat at -71.2 to -72.2 dBFS throughout. The mean measures thermal noise
    PLUS whatever else is in the band; only the median measures the front end.
    Testing the mean would have false-FAILED this check on a busy evening for a
    reason it is not meant to detect. The mean is still reported, because a large
    mean-minus-median gap is real information about the band -- see check_5.
    """
    detail = "%.1f dBFS median power over %d samples at %d dB RX gain [MEASURED] "\
             "(pass band %.0f..%.0f dBFS [ASSUMED])" % (
                 dbfs, uc.FRAME_SIZE, uc.RX_GAIN,
                 NOISE_FLOOR_MIN_DBFS, NOISE_FLOOR_MAX_DBFS)
    if mean_dbfs is not None and np.isfinite(mean_dbfs) and np.isfinite(dbfs):
        detail += "; mean %.1f dBFS, ambient %+.1f dB over thermal" % (
            mean_dbfs, mean_dbfs - dbfs)
    if not np.isfinite(dbfs) or dbfs <= NOISE_FLAT_DBFS:
        return FAIL, detail, (
            "Essentially a flatline -- RX2 is not receiving.\n"
            "Check the antenna is seated on RF B RX2, hand-tight. Check RX gain is not 0.")
    if dbfs > NOISE_FLOOR_MAX_DBFS:
        return FAIL, detail, (
            "Front end is hot -- either something nearby is transmitting or the gain is "
            "wrong.\nCheck nothing is radiating at high power close by. Check RX gain is "
            "not at max by mistake.\nIf the Mac is already keyed, that is not a fault: note "
            "it and re-run with the Mac off.")
    if dbfs < NOISE_FLOOR_MIN_DBFS:
        return FAIL, detail, (
            "Quieter than thermal noise, which is not physical -- the channel is likely "
            "dead.\nCheck the antenna on RF B RX2 and that RX gain is not 0.")
    return PASS, detail, None


# --------------------------------------------------------------------------
# The checks
# --------------------------------------------------------------------------
def check_1_uhd():
    try:
        import uhd
    except ImportError as exc:
        return None, Result(1, "UHD Import and Version", FAIL, "import uhd failed: %s" % exc, (
            "UHD Python bindings not installed or not on PYTHONPATH. Reinstall UHD with "
            "Python bindings\nenabled, or 'pip install uhd' if using the PyPI package, then "
            "retry.\nMEASURED: the PyPI wheel ships libpyuhd.pyd ONLY -- it is not a UHD "
            "install. You also need\nthe Ettus Win64 installer at the SAME version, or "
            "import succeeds while uhd.find does not exist.\nPython 3.13 cannot run this at "
            "all: libpyuhd needs numpy 1.x, which has no cp313 wheel. Use 3.12."),
            hard=True)

    version = getattr(uhd, "__version__", "unknown")
    try:
        major = int(str(version).split(".")[0])
    except (ValueError, IndexError):
        major = -1
    if major < MIN_UHD_MAJOR:
        return None, Result(1, "UHD Import and Version", FAIL,
                            "uhd %s, need >= %d.0" % (version, MIN_UHD_MAJOR), (
            "Old UHD version may lack B210 features used later. Upgrade UHD to >= 4.0 "
            "before continuing."), hard=True)

    # An import that succeeds proves nothing on its own -- see the fallback above.
    if not hasattr(uhd, "find"):
        return None, Result(1, "UHD Import and Version", FAIL,
                            "uhd %s imported but has no find(): bindings only, no UHD "
                            "runtime" % version, (
            "This is the PyPI-wheel-without-UHD case. Install the Ettus Win64 UHD at "
            "exactly this\nversion (%s), then re-run." % version), hard=True)
    return uhd, Result(1, "UHD Import and Version", PASS, "uhd %s, find() present" % version)


def check_2_enumerate(uhd):
    try:
        devices = list(uhd.find("type=b200"))
    except Exception as exc:
        return None, Result(2, "Device Enumeration", FAIL, "uhd.find raised: %s" % exc, (
            "uhd.find exists but failed. Usually a driver binding problem -- see the "
            "no-device fallback."), hard=True)

    if not devices:
        return None, Result(2, "Device Enumeration", FAIL, "no B210 found", (
            "Check the USB cable is seated (unplug/replug) and that you are on a USB 3.0 "
            "(blue) port.\nRun 'uhd_find_devices' from a terminal to cross-check outside "
            "Python.\nIf still empty, check Device Manager. On Windows the B210 needs the "
            "WinUSB driver BOUND:\n  pnputil /add-driver \"C:\\Program Files\\UHD\\share\\"
            "uhd\\usbdriver\\erllc_uhd_b200.inf\" /install\nthen REPLUG -- Windows only "
            "matches drivers at enumeration, so a device already at Code 28\nwill not "
            "re-bind on its own. Zadig is not needed."), hard=True)

    serials = []
    for dev in devices:
        serial = None
        try:
            serial = dev.get("serial")
        except Exception:
            pass
        if not serial:
            for token in str(dev).replace(",", " ").split():
                if token.startswith("serial="):
                    serial = token.split("=", 1)[1]
        serials.append(serial or str(dev))

    if len(serials) > 1:
        return None, Result(2, "Device Enumeration", FAIL,
                            "%d B210s found: %s" % (len(serials), ", ".join(serials)), (
            "Only one B210 should be connected to this machine. Disconnect the extras, or "
            "specify the\nserial explicitly in the device args."), hard=True)
    return serials[0], Result(2, "Device Enumeration", PASS,
                              "one B210, serial %s" % serials[0])


def usb_speed_hint(uhd, usrp, serial):
    """Best available USB-speed string, or None.

    UHD exposes this inconsistently across versions, so try the cheap sources in
    order and admit None rather than guessing. An UNKNOWN that warns is honest;
    a fabricated PASS is the failure mode this whole script exists to prevent.

    MEASURED 20 Aug 2026, UHD 4.10.0.0: all three sources come back empty on this
    build, so CHECK 3 reports UNKNOWN in practice and can never reach PASS. UHD
    does know -- it prints "[B200] Operating over USB 2" from C++ at device open --
    but that goes to its own log sink, not anywhere these accessors can see. The
    upgrade, if CHECK 3 ever needs to be load-bearing (i.e. if fs is raised past
    what USB 2 carries), is to redirect fd 2 around the open_usrp call and scrape
    that line. Not worth the machinery while the check cannot bind at fs = 1 MHz.
    """
    try:
        info = usrp.get_usrp_rx_info(0)
        for key in ("usb_speed", "link_speed", "mboard_id"):
            try:
                value = info[key]
            except Exception:
                continue
            if value and any(t in str(value).lower() for t in ("super", "high", "usb")):
                return str(value)
    except Exception:
        pass

    for getter in (lambda: usrp.get_pp_string(),
                   lambda: str(uhd.find("serial=%s" % serial))):
        try:
            text = getter()
        except Exception:
            continue
        for line in str(text).splitlines():
            low = line.lower()
            if "usb" in low and ("speed" in low or "operating over" in low):
                return line.strip()
    return None


def check_3_usb(uhd, usrp, serial):
    status, detail, fallback = usb_verdict(usb_speed_hint(uhd, usrp, serial), uc.RX_RATE)
    return Result(3, "USB Link Speed", status, detail, fallback)


def check_4_open(uhd, usrp):
    """Configure both chains. The streams are returned for checks 5 and 6."""
    try:
        rx_stream = uc.setup_rx(uhd, usrp)
    except Exception as exc:
        antennas = "unavailable"
        try:
            antennas = ", ".join(usrp.get_rx_antennas(uc.RX_CHAN))
        except Exception:
            pass
        return None, None, Result(4, "USRP Object Open (TX/RX)", FAIL,
                                  "RX config failed on ch%d antenna '%s': %s" % (
                                      uc.RX_CHAN, uc.RX_ANT, exc), (
            "Confirm the antenna is on RF B RX2, hand-tight.\n"
            "Valid RX antenna names on this daughterboard: %s\n"
            "If '%s' is not in that list, the naming differs on this UHD version -- correct "
            "it in usrp_common.py." % (antennas, uc.RX_ANT)), hard=True)

    try:
        tx_stream = uc.setup_tx(uhd, usrp, gain=TX_TEST_GAIN_DB)
    except Exception as exc:
        antennas = "unavailable"
        try:
            antennas = ", ".join(usrp.get_tx_antennas(uc.TX_CHAN))
        except Exception:
            pass
        return rx_stream, None, Result(4, "USRP Object Open (TX/RX)", FAIL,
                                       "TX config failed on ch%d antenna '%s': %s" % (
                                           uc.TX_CHAN, uc.TX_ANT, exc), (
            "Confirm the antenna is on RF A TX/RX, hand-tight.\n"
            "Valid TX antenna names on this daughterboard: %s\n"
            "'TX/RX' vs 'TX2' varies by daughterboard -- if '%s' is absent, correct it in "
            "usrp_common.py." % (antennas, uc.TX_ANT)), hard=True)

    detail = "fc %.3f GHz, fs %.3f Msps, TX ch%d '%s' @ %d dB, RX ch%d '%s' @ %d dB" % (
        usrp.get_rx_freq(uc.RX_CHAN) / 1e9, usrp.get_rx_rate(uc.RX_CHAN) / 1e6,
        uc.TX_CHAN, uc.TX_ANT, TX_TEST_GAIN_DB, uc.RX_CHAN, uc.RX_ANT, uc.RX_GAIN)
    return rx_stream, tx_stream, Result(4, "USRP Object Open (TX/RX)", PASS, detail)


def check_5_noise_floor(uhd, rx_stream):
    samples, error, _t0 = uc.receive_frame(uhd, rx_stream, num_samples=uc.FRAME_SIZE,
                                           timeout=uc.RX_TIMEOUT_SEC)
    if error:
        return Result(5, "Self-Noise-Floor Capture", FAIL, "capture failed: %s" % error, (
            "RX2 may not be receiving. Check the antenna is seated on RF B RX2 and that RX "
            "gain is not 0.\nAn overflow here instead means the host fell behind -- see "
            "CHECK 3."))
    # Median of instantaneous power, matching verify_mac.py's floor so the two
    # scripts report the same number for the same band. uc.power_dbfs() is the
    # MEAN and is kept only as the ambient indicator -- see floor_verdict().
    power = np.abs(samples) ** 2
    median_dbfs = 10.0 * np.log10(max(float(np.median(power)), 1e-30)) \
        if samples.size else float("nan")
    status, detail, fallback = floor_verdict(median_dbfs, uc.power_dbfs(samples))
    return Result(5, "Self-Noise-Floor Capture", status, detail, fallback,
                  value=median_dbfs)


def check_6_tx(uhd, tx_stream):
    n = int(round(TX_TEST_DURATION_S * uc.TX_RATE))
    t = np.arange(n) / uc.TX_RATE
    tone = (TX_TEST_AMPLITUDE * np.exp(2j * np.pi * TX_TEST_TONE_HZ * t)).astype(np.complex64)
    try:
        # The first RF this session. Stamped for the Mac operator -- 5 ms at
        # 20 dB is far too short and too quiet to be a link test, but if the
        # Mac IS listening this is the first thing it could possibly hear.
        uc.announce_tx("preflight CHECK 6, %.0f ms tone at %d dB"
                       % (TX_TEST_DURATION_S * 1e3, TX_TEST_GAIN_DB))
        sent, bad = uc.transmit_burst(uhd, tx_stream, tone, timeout=1.0)
    except Exception as exc:
        return Result(6, "TX Self-Test", FAIL, "transmit raised: %s" % exc, (
            "The TX chain threw before any async message arrived. Re-check CHECK 4's "
            "antenna configuration."))

    detail = "%d/%d samples sent, %.1f ms at %d dB, peak %.2f, %d underrun/late events" % (
        sent, n, TX_TEST_DURATION_S * 1e3, TX_TEST_GAIN_DB, TX_TEST_AMPLITUDE, bad)
    if bad or sent < n:
        return Result(6, "TX Self-Test", FAIL, detail, (
            "USB throughput issue -- likely a USB 2.0 port, a hub in the path, or CPU load "
            "too high.\nClose other applications, check Task Manager, confirm CHECK 3, and "
            "temporarily disable\nantivirus real-time scanning if it is intercepting UHD "
            "calls."), value=0.0)
    # 21 Aug 2026: this note used to say the fitted parts were VERT900s run out
    # of band. VERT2450s are now fitted, so the 20-40 dB of mismatch it warned
    # about is gone -- but the SENSE of the note stands and is the reason it is
    # kept: a clean async status means UHD accepted the samples, and says
    # nothing about what left the antenna.
    return Result(6, "TX Self-Test", PASS, detail, (
        "A clean TX does NOT mean the energy radiated. UHD reports that the samples were "
        "accepted\nby the FPGA, not that RF left the port -- a disconnected or badly seated "
        "antenna passes this\ncheck. Only usrp_loopback.py, which hears the burst on RF B "
        "RX2, can tell you it radiated."), value=1.0)


def check_7_constants(tuned_ok=False):
    """Print the eight shared numbers. `tuned_ok` is CHECK 4's verdict.

    The exponent is pinned per line inside shared_constants_block() so the block
    is byte-comparable with the Mac's: "%g" alone would print fc as 2.45e+09 and
    chirp_duration as 1e-05, the same numbers in a shape nobody can diff by eye
    at a bench.

    fc and fs are tagged [MEASURED] only when CHECK 4 passed, because CHECK 4 is
    what read them back off the device after tuning. If the board never opened,
    the block still prints -- it is what gets sent to the Mac -- but it says so.
    """
    logging.info("")
    for line in uc.shared_constants_block(fc_fs_measured=tuned_ok):
        logging.info("%s", line)
    logging.info("")
    return Result(7, "Shared Constants Printed", INFO,
                  "eight constants printed above, all from usrp_common.py", (
        "MANUAL STEP: send this block to the Mac and compare, before proceeding.\n"
        "TWO OF THESE WERE ALREADY CAUGHT WRONG on 21 Aug, both by exchanging the\n"
        "block. capture_window was the Mac CONFIG (2000 samples) against a runtime of\n"
        "at least one full PRI, and tx_gate_duration was their chirp_duration answering\n"
        "a question about something else -- the Mac has NO transmit gate. That field is\n"
        "now WITHDRAWN and replaced by duplex_blind, measured on THIS board. Treat the\n"
        "remaining [ASSUMED] lines as wrong the same way until the Mac says otherwise.\n"
        "When the Mac block comes back:  python status_report.py --mac mac_constants.txt"))


# --------------------------------------------------------------------------
def summary(results, skipped_tx):
    names = {1: "UHD Import/Version", 2: "Device Enumeration", 3: "USB Link Speed",
             4: "USRP Object Open (TX/RX)", 5: "Self-Noise-Floor Capture",
             6: "TX Self-Test", 7: "Shared Constants Printed"}
    by_num = {r.num: r for r in results}

    logging.info("")
    logging.info("==========================================")
    logging.info("PREFLIGHT SUMMARY -- WINDOWS DRONE GENERATOR")
    logging.info("==========================================")
    for num in range(1, 8):
        label = names[num]
        dots = "." * max(1, 36 - len(label))
        result = by_num.get(num)
        if result is None:
            state = "SKIP  (--skip-tx)" if (num == 6 and skipped_tx) else "SKIP  (not reached)"
            logging.info("[%d] %s %s %s", num, label, dots, state)
        else:
            extra = "  -- compare with Mac manually" if result.status == INFO else ""
            logging.info("[%d] %s %s %s%s", num, label, dots, result.status, extra)
    logging.info("==========================================")

    failed = [r for r in results if r.blocking]
    if failed:
        logging.info("VERDICT: NO-GO -- resolve [CHECK %s] before proceeding",
                     "], [CHECK ".join(str(r.num) for r in failed))
        logging.info("==========================================")
        for r in failed:
            logging.info("")
            logging.info("[CHECK %d] %s -- %s", r.num, r.name, r.detail)
            for line in (r.fallback or "").splitlines():
                logging.info("    %s", line)
        # Printed on NO-GO too: a failing run is exactly when the floor number
        # is wanted, and re-running to get it costs another capture.
        machine_readable(by_num, skipped_tx)
        return 1

    if skipped_tx:
        logging.info("VERDICT: GO (PARTIAL) -- TX self-test skipped, run without --skip-tx "
                     "before Stage E")
    else:
        logging.info("VERDICT: GO -- proceed to Stage E prep (naive DRFM)")
    for r in [r for r in results if r.status == WARN]:
        logging.info("         WARNING from [CHECK %d]: %s", r.num, r.detail)
    logging.info("==========================================")
    machine_readable(by_num, skipped_tx)
    return 0


def machine_readable(by_num, skipped_tx):
    """The two numbers worth reading back, on parseable lines.

    The per-check list above is for a human at the bench. This block exists so
    the floor and the TX verdict can be quoted, diffed run-to-run, or pasted
    into a report without anyone re-reading CHECK 5's prose and transcribing the
    number by hand -- which is how a -71.3 becomes a -71.9 in a document.
    """
    floor = by_num.get(5)
    tx = by_num.get(6)
    logging.info("")
    logging.info("=== PREFLIGHT SUMMARY (PARSEABLE) ===")
    if floor is not None and floor.value is not None and np.isfinite(floor.value):
        logging.info("noise_floor_dbfs = %.1f          # [MEASURED] median power, %d "
                     "samples at %d dB RX gain", floor.value, uc.FRAME_SIZE, uc.RX_GAIN)
    else:
        logging.info("noise_floor_dbfs = none          # CHECK 5 did not produce a number")
    logging.info("noise_floor_pass = %s",
                 "none" if floor is None else str(floor.status == PASS).lower())
    if tx is None:
        logging.info("tx_self_test     = skipped       # %s",
                     "--skip-tx, the PA was never keyed" if skipped_tx else "not reached")
    else:
        logging.info("tx_self_test     = %-13s # %s",
                     "pass" if tx.status == PASS else "fail", tx.detail)
    logging.info("=====================================")


def demo():
    """Self-check of the two verdict rules and the summary. No radio.

    python preflight_check.py --demo
    """
    assert usb_verdict("SuperSpeed", 1e6)[0] == PASS
    # The measured case: USB 2 at 1 Msps warns, it does not fail.
    assert usb_verdict("Operating over USB 2", 1e6)[0] == WARN
    assert usb_verdict(None, 1e6)[0] == WARN
    # ...and the same link at a rate it genuinely cannot carry does fail.
    assert usb_verdict("Operating over USB 2", 20e6)[0] == FAIL
    assert usb_verdict("SuperSpeed", 20e6)[0] == PASS

    # Every measured floor must pass. The brief's -60..-30 band would fail them all.
    for measured in (-69.8, -70.3, -70.4, -70.6, -70.1, -71.2, -72.2):
        assert floor_verdict(measured)[0] == PASS, measured
    assert floor_verdict(-200.0)[0] == FAIL          # flatline
    assert floor_verdict(float("nan"))[0] == FAIL    # empty capture
    assert floor_verdict(-10.0)[0] == FAIL           # saturated
    assert floor_verdict(-90.0)[0] == FAIL           # below thermal: dead channel

    # The regression this check was rewritten for: 20 Aug, a busy band pushed the
    # MEAN to -62.5 dBFS while the median held at -71.2. Testing the mean would
    # have been 7.5 dB from a false FAIL; testing the median passes, and the gap
    # is reported rather than hidden.
    status, detail, _ = floor_verdict(-71.2, -62.5)
    assert status == PASS
    assert "ambient +8.7 dB over thermal" in detail, detail
    assert floor_verdict(-71.2, float("nan"))[0] == PASS   # mean unavailable is fine

    # The parseable block must carry the NUMBER, not re-parse CHECK 5's prose.
    measured = Result(5, "floor", PASS, "-", value=-71.3)
    assert measured.value == -71.3
    assert Result(6, "tx", PASS, "-", value=1.0).status == PASS
    machine_readable({5: measured, 6: Result(6, "tx", PASS, "clean", value=1.0)}, False)
    machine_readable({}, True)          # nothing measured must not raise

    ok = [Result(1, "a", PASS, "-"), Result(7, "b", INFO, "-")]
    assert summary(ok, skipped_tx=False) == 0
    assert summary(ok + [Result(3, "c", WARN, "-")], skipped_tx=False) == 0
    assert summary(ok + [Result(5, "d", FAIL, "-", "fix it")], skipped_tx=False) == 1
    print("")
    print("preflight_check demo: all assertions passed.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--yes", action="store_true",
                        help="skip the transmit confirmation before CHECK 6")
    parser.add_argument("--skip-tx", action="store_true",
                        help="run every check except CHECK 6; never keys the PA")
    parser.add_argument("--demo", action="store_true",
                        help="verdict-logic self-check, no radio")
    args = parser.parse_args()

    if args.demo:
        logging.basicConfig(level=logging.INFO, format="%(message)s")
        return demo()

    uc.setup_logging("preflight_check")
    logging.info("[INFO] Preflight for Stage E. CHECK 6 keys the PA for %.0f ms at %d dB; "
                 "every other check is read-only.",
                 TX_TEST_DURATION_S * 1e3, TX_TEST_GAIN_DB)
    logging.info("")
    results = []

    def record(result):
        result.emit()
        results.append(result)
        logging.info("")
        return result

    uhd, r1 = check_1_uhd()
    if record(r1).blocking:
        return summary(results, args.skip_tx)

    serial, r2 = check_2_enumerate(uhd)
    if record(r2).blocking:
        return summary(results, args.skip_tx)

    # Checks 3 and 4 both need the board open. Open it once here so CHECK 3 can
    # read the link description, and hand the same handle to CHECK 4.
    try:
        usrp = uc.open_usrp(uhd, serial)
    except Exception as exc:
        record(Result(4, "USRP Object Open (TX/RX)", FAIL,
                      "MultiUSRP('serial=%s') raised: %s" % (serial, exc), (
            "The board enumerated but would not open. Usually another process still holds "
            "it -- close\nany running payload, loopback or uhd_usrp_probe, then retry. If it "
            "persists, replug the board\nto reset the FPGA."), hard=True))
        return summary(results, args.skip_tx)

    record(check_3_usb(uhd, usrp, serial))

    rx_stream, tx_stream, r4 = check_4_open(uhd, usrp)
    if record(r4).blocking:
        return summary(results, args.skip_tx)

    # 5 and 6 are both terminal: neither makes the other meaningless, so run both
    # even if the first fails, and report every fallback rather than only the first.
    record(check_5_noise_floor(uhd, rx_stream))

    if args.skip_tx:
        logging.info("[CHECK 6] TX Self-Test ... SKIPPED (--skip-tx), the PA was never keyed")
        logging.info("")
    else:
        uc.confirm_transmit(assume_yes=args.yes, gain_db=TX_TEST_GAIN_DB)
        record(check_6_tx(uhd, tx_stream))

    record(check_7_constants(tuned_ok=(r4.status == PASS)))
    return summary(results, args.skip_tx)


if __name__ == "__main__":
    sys.exit(main())
