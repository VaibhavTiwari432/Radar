# RadChar Dataset — Download & Placement

The simulation cross-checks its native MATLAB scenes against **RadChar**, a
synthetic radar-signal dataset (ICASSP 2023). This folder is where the `.h5`
file goes. **Start with RadChar-Tiny (50,000 signals).**

## What RadChar is (verified schema)

| Item | Value |
|---|---|
| HDF5 datasets | `/iq` and `/labels` |
| `/iq` | `(N, 512)` complex baseband IQ, one row per signal |
| Sampling rate | 3.2 MHz |
| Samples/signal | 512 complex |
| Signal types | 0 = coherent pulse train, 1 = Barker, 2 = polyphase Barker, 3 = Frank, 4 = LFM |
| `/labels` fields | `index`, `signal_type`, `number_of_pulses` (2–6), `pulse_width` (s), `time_delay` (s), `pulse_repetition_interval` (s), `signal_to_noise_ratio` (dB, −20…+20) |

Variants: `RadChar-Tiny` (50k) · `-Small` (500k) · `-Baseline` (1M) · `-Large` (2M).

## Option A — Kaggle API (recommended)

1. Install the CLI (once):
   ```powershell
   pip install kaggle
   ```
2. Get an API token: kaggle.com → your profile → **Settings → API → Create New Token**.
   This downloads `kaggle.json`. Put it at `C:\Users\<you>\.kaggle\kaggle.json`.
3. Download straight into this folder and unzip:
   ```powershell
   kaggle datasets download -d abcxyzi/radchar-icassp-2023 -p E:\Radar\data --unzip
   ```

## Option B — Manual

1. Open https://www.kaggle.com/datasets/abcxyzi/radchar-icassp-2023
2. **Download**, unzip, and copy `RadChar-Tiny.h5` into `E:\Radar\data\`.

## Verify it loaded (in MATLAB, from the project root)

```matlab
startup                                   % add project paths
h5disp('data/RadChar-Tiny.h5','/labels')  % peek at the label schema
D = data.loadRadChar('data/RadChar-Tiny.h5','MaxSignals',1000);
fprintf('Loaded %d signals; IQ is %dx%d\n', D.N, size(D.iq,1), size(D.iq,2));
tabulate(D.signal_type)                    % class balance across the 5 types
```

Then run the data-integration test:
```matlab
runAllTests('DataIntegration')
```

## Notes

- The `.h5` file is large — it is **git-ignored on purpose**; do not commit it.
- RadChar is **baseband** (no RF carrier) and was built for *classification*.
  Treat it as a realistic **waveform source**, not as ground-truth ranges.
  Ground-truth ranges/velocities come from the native `phased.*` scenes
  (POA Part 3).

## Source
- Dataset: https://www.kaggle.com/datasets/abcxyzi/radchar-icassp-2023
- Code/schema: https://github.com/abcxyzi/RadChar
- Paper: *Multi-task Learning for Radar Signal Characterisation*, arXiv:2306.13105
