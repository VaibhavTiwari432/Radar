# Preflight — Windows drone generator

Run `python preflight_check.py` from `E:\Radar\hardware` with the 3.12 venv
interpreter (`.venv312\Scripts\python.exe`) and no arguments, with an antenna
fitted to **RF A TX/RX** and to **RF B RX2**, before every Stage E session. It
runs seven checks in order — UHD import and version, device enumeration, USB
link speed, TX/RX channel configuration, a 25 ms receive-only noise-floor
capture, a 5 ms low-power TX burst that only confirms the transmit chain runs
clean, and a printout of the six shared RF constants — stopping early if checks
1–4 fail, since nothing after them would mean anything. Everything is read-only
except check 6, which keys the PA briefly and prompts you to confirm the antenna
first (`--yes` skips the prompt, `--skip-tx` omits the transmit entirely and
returns a partial GO, `--demo` exercises the verdict logic with no radio). Each
check prints PASS/FAIL, a one-line detail, and on failure a specific remedy; a
timestamped copy lands in `logs/`. **GO** means checks 1–6 passed and you may
proceed to Stage E prep — but check 7 is a manual step the script cannot do for
you, so diff its constants block against the Mac's printout by eye before going
on air. **NO-GO** names every failed check, not just the first, and prints each
one's fallback again at the bottom; fix them all and re-run.

## Three thresholds that differ from the original brief

Each was changed because the bench measured otherwise, and each is commented at
the point it is applied:

1. **Check 3 (USB speed) warns, it does not fail.** This board negotiates USB 2
   on the cable in use (measured 18 Aug, on a USB 3.0 root hub — so the *cable*
   is the USB-2-only part, not the port). At `fs = 1 MHz` the link needs 4 MB/s
   against roughly 35 MB/s available, so it constrains nothing in Stage E. A
   hard failure would NO-GO every run and skip checks 4–7. It becomes a hard
   failure automatically if `fs` is ever raised past what USB 2 can carry.
2. **Check 5 passes on −80…−55 dBFS, not −60…−30, and it tests the median.**
   Measured on this bench with nothing transmitting: −69.8 to −70.6 dBFS at
   30 dB RX gain, so the brief's band would have failed every honest run. It
   tests *median* instantaneous power rather than mean because 2.45 GHz ISM
   ambient inflates the mean without touching the front end: on 20 Aug the mean
   drifted −68.5 → −64.8 → −62.5 dBFS across one evening on an untouched board,
   7.5 dB from a false FAIL, while the median held at −71.2 to −72.2. The mean
   is still printed as an ambient indicator (`ambient +10.3 dB over thermal`),
   and the median now matches `verify_mac.py`'s floor exactly, so the two
   scripts report the same number for the same band.
3. **Check 6 keeps the antenna confirmation** even though no cable is required.
   Nothing needs to receive the burst, but keying a bare port is the one thing
   here that can damage hardware.

## What preflight still cannot tell you

A clean check 6 means the TX chain ran without underruns. It does **not** mean
the energy radiated. The VERT900 antennas on this bench are 900/1800 MHz parts
being run at 2.45 GHz, and preflight has no directional coupler with which to
see that — so a GO verdict is not a link budget. Fit correct 2.4 GHz antennas
before reading anything into Stage E's received power.

Check 7's `n_pulses = 32` is the only one of the six constants with no shared
source on the Windows side — the other five are read from `usrp_common.py`, so
they cannot drift from what the payload actually schedules against. Nothing here
consumes `n_pulses` yet, which means a mismatch with the Mac would go unnoticed
until Stage E. Check that line first.
