"""cogengine.matlab_judge -- Phase 2 build-order step 5: wire a Scene into
the Phase 1 MATLAB judge (+radar/+track), the INDEPENDENT scorer.

Renders `scene` frame-by-frame (advancing each phantom's kinematics the
same way radar_twin.py does, summing all phantoms per frame -- a real
swarm's combined return), adds noise, and exports the resulting rx buffers
to a .mat file that +engine/runJudge.m runs through
radar.pulseCompress -> radar.cfarDetect -> track.runTracker ->
track.discriminator.

This is Rule 2's twin-vs-judge separation made concrete: the SAME Scene,
scored by BOTH the twin (radar_twin.predict, in imagination) and this
bridge (the real judge), so the gap between them is measured, never
assumed. This module does not import matlab, does not shell out to it, and
does not know anything about +radar/+track's internals -- it only knows
the rx-cube + config contract that +engine/runJudge.m reads.
"""
from __future__ import annotations

import numpy as np
from scipy.io import savemat

from cogengine.features import synthesize_tx_pulse
from cogengine.radar_twin import TwinConfig, advance_phantom
from cogengine.renderer import lfm_chirp, render_phantom_cpi
from cogengine.schema import RadarState, Scene


def export_scene_for_judge(scene: Scene, radar_state: RadarState, config: TwinConfig,
                            rng: np.random.Generator, out_path: str) -> list:
    """Render `scene` across config.num_frames frames (all phantoms summed
    per frame, each advancing its own kinematics frame-to-frame) and write
    the resulting [fast_time_samples x num_pulses_per_frame x num_frames]
    complex rx PULSE CUBE plus the config MATLAB needs to reconstruct the
    same waveform/CFAR/tracker parameters, to a .mat file at out_path.

    The cube (rather than one fast-time column per frame, which is what this
    exported until the Virtual Entity Engine build) is what gives the judge a
    slow-time axis to Doppler-process. Judge-side consequences, including
    which previously-published numbers move, are documented in
    +engine/runJudge.m's "DOPPLER IS NOW MEASURED" header block.

    Feature-matched synthesis is the ONLY path (mirrors radar_twin.predict) --
    the JUDGE must see the SAME synthesis treatment the twin planned
    against, or a twin-vs-judge comparison would compare apples to oranges.
    Returns the list of degraded_events (see cogengine.features.
    synthesize_tx_pulse) so callers can surface them -- this function has
    no Feedback object of its own to carry them, but they must not be
    swallowed silently either.
    """
    chirp = lfm_chirp(config.fs, config.pulse_width_s, config.bandwidth_hz)
    nominal_k = config.bandwidth_hz / config.pulse_width_s
    degraded_events = []

    live = list(scene.phantoms)
    # [fast_time x num_pulses x num_frames] -- a PULSE CUBE, not one column
    # per frame. The slow-time axis is not decoration: without it there is
    # physically nothing for +radar/rangeDoppler.m to transform, which is why
    # +engine/runJudge.m used to compute its "doppler" as diff(range)/dt and
    # hand that to track.discriminator -- making the discriminator's
    # Doppler/range-rate SIGN screen a tautology that passed every track it
    # ever saw. Exporting the cube is what makes that screen a real
    # measurement. See runJudge.m's "DOPPLER IS NOW MEASURED" header block.
    n_pulses = config.num_pulses_per_frame
    rx_frames = np.zeros(
        (config.fast_time_samples, n_pulses, config.num_frames), dtype=complex
    )

    for k in range(config.num_frames):
        chirp_override, degraded_event = synthesize_tx_pulse(
            chirp, config.fs, nominal_k, config.intercept_noise_amplitude, rng, frame=k,
        )
        if degraded_event is not None:
            degraded_events.append(degraded_event)

        frame_sum = np.zeros((config.fast_time_samples, n_pulses), dtype=complex)
        for phantom in live:
            frame_sum += render_phantom_cpi(
                phantom, radar_state, config.fs, radar_state.pri_s, n_pulses,
                config.fast_time_samples, config.pulse_width_s, config.bandwidth_hz, rng,
                chirp_override=chirp_override,
            )
        noise = config.noise_amplitude * (
            rng.standard_normal((config.fast_time_samples, n_pulses))
            + 1j * rng.standard_normal((config.fast_time_samples, n_pulses))
        ) / np.sqrt(2)
        rx_frames[:, :, k] = frame_sum + noise
        live = [advance_phantom(p, config.frame_interval_s) for p in live]

    savemat(out_path, {
        "rx_frames": rx_frames,
        "fs": config.fs, "pulse_width_s": config.pulse_width_s,
        "bandwidth_hz": config.bandwidth_hz, "prf_hz": radar_state.prf_hz,
        # Required by runJudge's cube path to turn a Doppler bin into a
        # range-rate. It refuses to guess a wavelength rather than silently
        # corrupt every velocity it reports.
        "carrier_hz": radar_state.carrier_hz,
        "cfar_pfa": config.cfar_pfa, "cfar_num_training": float(config.cfar_num_training),
        "cfar_num_guard": float(config.cfar_num_guard),
        "mofn_m": float(config.mofn_m), "mofn_n": float(config.mofn_n),
        "frame_interval_s": config.frame_interval_s,
    })
    return degraded_events
