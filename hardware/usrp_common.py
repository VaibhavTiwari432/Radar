"""Shared USRP B210 plumbing for the drone/transmitter payload (Windows side).

One module so the three scripts cannot drift apart on device setup, rates or
error handling. Everything here is thin: find the board, configure it, move
samples, report what actually happened.

Radio plan on the B210 (fixed by the antenna wiring in the task brief):
    channel 0  ->  RF A, antenna "TX/RX"  ->  TRANSMIT
    channel 1  ->  RF B, antenna "RX2"    ->  RECEIVE
Two separate ports so TX does not desensitise RX (~30-40 dB of port isolation
plus whatever the antenna spacing buys).
"""
import csv
import logging
import os
import sys
import time

import numpy as np

# --- Constants: matched to the Mac MATLAB radar. Do not change one side only.
RX_RATE = 1e6              # Hz, sample rate (must equal the Mac's)
TX_RATE = 1e6              # Hz
CENTER_FREQ = 2.45e9       # Hz, license-exempt ISM band
RX_GAIN = 30               # dB
TX_GAIN = 30               # dB, ISM-safe at short range with an antenna fitted
FRAME_SIZE = 2000          # samples per frame = 2.0 ms at 1 MHz
RX_TIMEOUT_SEC = 1.0       # max wait for a pulse before giving up on a frame

# Noise-only floor for estimate_snr_db(). With NO pulse present the estimator
# reports the CREST FACTOR of noise, not 0 dB -- measured 9.7-11.1 dB over
# 2000-sample frames on 18 Aug 2026 with nothing transmitting. So "did we hear
# anything?" must be tested against this, never against 0.
NOISE_ONLY_SNR_DB = 15.0

RX_CHAN, RX_ANT = 1, "RX2"
TX_CHAN, TX_ANT = 0, "TX/RX"

LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")


# --------------------------------------------------------------------------
# UHD import + device discovery
# --------------------------------------------------------------------------
def require_uhd():
    """Import uhd, or exit with an instruction the user can act on."""
    try:
        import uhd
        return uhd
    except ImportError:
        sys.exit(
            "[ERROR] The 'uhd' Python module is not installed.\n"
            "        Install the Ettus UHD binaries for Windows (they ship the\n"
            "        Python bindings), then make sure this interpreter sees them:\n"
            "          1. https://files.ettus.com/binaries/uhd/latest_release/\n"
            "          2. Add <UHD>\\lib\\site-packages to PYTHONPATH, or run\n"
            "             'pip install uhd' if your UHD build publishes a wheel.\n"
            "          3. Verify:  python -c \"import uhd; print(uhd.__version__)\"\n"
            "        See README_USRP_WINDOWS.md for the full walkthrough."
        )


def find_b210_serial(uhd):
    """Return the serial of the attached B210, or exit explaining why not.

    uhd.find() hands back version-dependent address objects, so read the
    serial defensively instead of assuming one accessor exists.
    """
    devices = uhd.find("type=b200")
    if not devices:
        sys.exit(
            "[ERROR] No USRP B210 found.\n"
            "        - Is the USB 3.0 cable in a blue (USB 3) port?\n"
            "        - Is the board powered (green LED lit)?\n"
            "        - Windows: if Device Manager shows an unknown device, install\n"
            "          the WinUSB driver for it with Zadig.\n"
            "        - Cross-check with:  uhd_find_devices"
        )
    serials = []
    for dev in devices:
        text = str(dev)
        serial = None
        try:
            serial = dev.get("serial")             # UHD >= 4.x device_addr
        except Exception:
            pass
        if not serial:                             # fall back to parsing "serial=XXXX"
            for token in text.replace(",", " ").split():
                if token.startswith("serial="):
                    serial = token.split("=", 1)[1]
        serials.append(serial or text)
    if len(serials) > 1:
        logging.warning("[INFO] %d B210s found (%s); using the first.",
                        len(serials), ", ".join(serials))
    return serials[0]


def open_usrp(uhd, serial):
    usrp = uhd.usrp.MultiUSRP("serial=%s" % serial)
    logging.info("[INFO] Opened B210 serial=%s", serial)
    return usrp


# --------------------------------------------------------------------------
# Streams
# --------------------------------------------------------------------------
def setup_rx(uhd, usrp):
    usrp.set_rx_rate(RX_RATE, RX_CHAN)
    usrp.set_rx_freq(uhd.types.TuneRequest(CENTER_FREQ), RX_CHAN)
    usrp.set_rx_gain(RX_GAIN, RX_CHAN)
    usrp.set_rx_antenna(RX_ANT, RX_CHAN)
    args = uhd.usrp.StreamArgs("fc32", "sc16")
    args.channels = [RX_CHAN]
    logging.info("[RX ] ch%d %s  %.3f MHz  %.3f Msps  %.0f dB",
                 RX_CHAN, RX_ANT, usrp.get_rx_freq(RX_CHAN) / 1e6,
                 usrp.get_rx_rate(RX_CHAN) / 1e6, usrp.get_rx_gain(RX_CHAN))
    return usrp.get_rx_stream(args)


def setup_tx(uhd, usrp):
    usrp.set_tx_rate(TX_RATE, TX_CHAN)
    usrp.set_tx_freq(uhd.types.TuneRequest(CENTER_FREQ), TX_CHAN)
    usrp.set_tx_gain(TX_GAIN, TX_CHAN)
    usrp.set_tx_antenna(TX_ANT, TX_CHAN)
    args = uhd.usrp.StreamArgs("fc32", "sc16")
    args.channels = [TX_CHAN]
    logging.info("[TX ] ch%d %s  %.3f MHz  %.3f Msps  %.0f dB",
                 TX_CHAN, TX_ANT, usrp.get_tx_freq(TX_CHAN) / 1e6,
                 usrp.get_tx_rate(TX_CHAN) / 1e6, usrp.get_tx_gain(TX_CHAN))
    return usrp.get_tx_stream(args)


def receive_frame(uhd, rx_stream, num_samples=FRAME_SIZE, timeout=RX_TIMEOUT_SEC):
    """Capture exactly num_samples. Returns (samples, error_string_or_None).

    A short or failed capture is RETURNED as an error, not raised: the payload
    loop has to be able to skip one bad frame and keep going.
    """
    cmd = uhd.types.StreamCMD(uhd.types.StreamMode.num_done)
    cmd.num_samps = num_samples
    cmd.stream_now = True
    rx_stream.issue_stream_cmd(cmd)

    md = uhd.types.RXMetadata()
    buf = np.zeros((1, rx_stream.get_max_num_samps()), dtype=np.complex64)
    out = np.zeros(num_samples, dtype=np.complex64)
    got, deadline = 0, time.time() + timeout
    while got < num_samples and time.time() < deadline:
        n = rx_stream.recv(buf, md, timeout)
        if md.error_code != uhd.types.RXMetadataErrorCode.none:
            if md.error_code == uhd.types.RXMetadataErrorCode.timeout:
                return out[:got], "timeout waiting for samples (no pulse heard?)"
            if md.error_code == uhd.types.RXMetadataErrorCode.overflow:
                logging.warning("[RX ] overflow - host fell behind, samples dropped")
            else:
                return out[:got], "RX error: %s" % md.strerror()
        take = min(n, num_samples - got)
        out[got:got + take] = buf[0, :take]
        got += take
    if got < num_samples:
        return out[:got], "short capture: %d/%d samples in %.1fs" % (got, num_samples, timeout)
    return out, None


def transmit_burst(uhd, tx_stream, samples, timeout=1.0):
    """Send one burst. Returns (num_sent, num_underruns)."""
    md = uhd.types.TXMetadata()
    md.start_of_burst = True
    md.end_of_burst = True
    md.has_time_spec = False
    buf = np.ascontiguousarray(samples, dtype=np.complex64).reshape(1, -1)
    sent = tx_stream.send(buf, md, timeout)

    underruns = 0
    amd = uhd.types.TXAsyncMetadata()
    while tx_stream.recv_async_msg(amd, 0.1):       # drain what the FPGA reported
        code = amd.event_code
        if code in (uhd.types.TXMetadataEventCode.underflow,
                    uhd.types.TXMetadataEventCode.underflow_in_packet):
            underruns += 1
            logging.warning("[TX ] UNDERRUN at %s", time.strftime("%H:%M:%S"))
        elif code in (uhd.types.TXMetadataEventCode.seq_error,
                      uhd.types.TXMetadataEventCode.seq_error_in_burst):
            logging.warning("[TX ] sequence error (packet dropped on the USB link)")
    return sent, underruns


# --------------------------------------------------------------------------
# Measurements
# --------------------------------------------------------------------------
def estimate_snr_db(samples):
    """Peak-to-noise-floor SNR estimate, in dB.

    Noise floor = median instantaneous power (robust: a short pulse inside a
    long frame leaves the median untouched). Signal = peak power above that
    floor. An estimate, not a calibrated measurement -- with no pulse present
    it reports the crest factor of noise (a few dB), not 0 dB.
    """
    if samples.size == 0:
        return float("nan")
    power = np.abs(samples) ** 2
    noise = float(np.median(power))
    if noise <= 0:
        return float("nan")
    return 10.0 * np.log10(max(float(power.max()) - noise, 1e-30) / noise)


def power_dbfs(samples):
    """Mean power in dB relative to full scale (|x| = 1).

    NOT calibrated dBm: the B210 has no absolute power reference in this
    setup and the antenna/cable losses are unmeasured. Recorded in the CSV's
    tx_power_dbm column for schema compatibility -- read it as dBFS.
    """
    if samples.size == 0:
        return float("nan")
    return 10.0 * np.log10(max(float(np.mean(np.abs(samples) ** 2)), 1e-30))


def normalize(samples, target_peak=0.8):
    """Scale to target_peak so the DAC never clips. Returns (scaled, factor)."""
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    factor = target_peak / (peak + float(np.finfo(np.float32).eps))
    out = (samples * factor).astype(np.complex64)
    new_peak = float(np.max(np.abs(out))) if out.size else 0.0
    if new_peak > 0.9:
        logging.warning("[TX ] clipping risk: normalized peak %.3f > 0.9", new_peak)
    return out, factor


# --------------------------------------------------------------------------
# Logging / CSV / safety
# --------------------------------------------------------------------------
def setup_logging(name):
    """Console + timestamped file. Returns the log file path."""
    os.makedirs(LOG_DIR, exist_ok=True)
    path = os.path.join(LOG_DIR, "%s_%s.log" % (name, time.strftime("%Y%m%d_%H%M%S")))
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        handlers=[logging.FileHandler(path, encoding="utf-8"),
                  logging.StreamHandler(sys.stdout)])
    logging.info("[INFO] Logging to %s", path)
    return path


class CsvLog:
    """One row per iteration, flushed immediately so a Ctrl-C keeps the data."""

    def __init__(self, path, columns):
        self.file = open(path, "w", newline="", encoding="utf-8")
        self.writer = csv.DictWriter(self.file, fieldnames=columns)
        self.writer.writeheader()
        self.file.flush()
        logging.info("[INFO] CSV -> %s", path)

    def row(self, **kwargs):
        self.writer.writerow(kwargs)
        self.file.flush()

    def close(self):
        self.file.close()


def confirm_transmit(assume_yes=False):
    """Refuse to key the transmitter until a human says the antenna is fitted."""
    if assume_yes:
        logging.info("[INFO] --yes given, skipping the transmit confirmation.")
        return
    print("")
    print("  ABOUT TO TRANSMIT")
    print("  %.3f GHz, %d dB gain, RF A TX/RX port." % (CENTER_FREQ / 1e9, TX_GAIN))
    print("  Confirm an antenna (or a matched load) is fitted to RF A TX/RX.")
    print("  Transmitting into an open port can damage the PA.")
    if input("  Type 'yes' to transmit: ").strip().lower() != "yes":
        sys.exit("[INFO] Aborted by user, nothing transmitted.")
