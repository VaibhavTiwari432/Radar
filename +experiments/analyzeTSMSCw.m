function out = analyzeTSMSCw(cwRoot, perCell, outDir)
%ANALYZETSMSCW  Measure, from the TSMS-Drone CW radar set, the two quantities
%   this project has never had from real data:
%
%     1. AMPLITUDE vs RANGE, using the CORNER REFLECTOR as the control.
%        +engine/+entity/calibrateQ.m documents that it could derive only an
%        amplitude FLOOR (0.233 dB) from RadChar, because RadChar is an
%        emitter's own pulse train -- no target, no return, no motion. A
%        corner reflector has stable known RCS and NO rotor modulation, so
%        measuring it at 2..30 m isolates the propagation law and the
%        receiver's own scintillation from target modulation. That is the
%        measurement calibrateQ says it cannot make.
%
%     2. MICRO-DOPPLER COMB STATISTICS per drone type.
%        +engine/+entity/render.m applies `1 + MICRO_DEPTH*cos(2*pi*microHz*t)`
%        -- a single tone, which yields exactly TWO sidebands -- with
%        MICRO_DEPTH = 0.3 carrying a `ponytail:` comment admitting the flash
%        shape is not physically derived. The 15-MB FMCW sample already showed
%        ~15 lines at depth 0.115. This measures it properly, across targets
%        and ranges, with repetitions.
%
%   out = experiments.analyzeTSMSCw(cwRoot, perCell, outDir)
%       cwRoot  : folder containing the extracted CW set (searched recursively)
%       perCell : repetitions to use per (target, range) cell (default 25).
%                 The set ships 500; 25 is enough for a mean and a spread and
%                 keeps a full pass to minutes. Raise it for a final number.
%
%   SIGNAL CHAIN IS THE AUTHORS' OWN (Example_CW_radar_processing.m): take the
%   complex I/Q in `data`, resample 1:16 (-> 4096 Hz), FFT, fftshift. Their
%   recipe is followed rather than improved on, so these numbers are
%   comparable to anything else published against this dataset. The cosmetic
%   thresholding in their script (clipping, DC replacement) is NOT applied --
%   that exists to make images legible and would corrupt a measurement.
%
%   TARGET AND RANGE COME FROM THE FILENAME, not the directory layout:
%   '{Model}_{N}m_{idx}.mat', e.g. 'Inspire 2_12m_001.mat'. Layout-tolerant on
%   purpose, so an archive that unpacks a level up or down still works.

    if nargin < 2 || isempty(perCell); perCell = 25; end
    if nargin < 3 || isempty(outDir)
        here = fileparts(mfilename('fullpath'));
        outDir = fullfile(fileparts(here), 'results');
    end
    if ~isfolder(outDir); mkdir(outDir); end
    assert(isfolder(cwRoot), 'experiments:analyzeTSMSCw:noRoot', 'Not a folder: %s', cwRoot);

    FS_RAW = 65536;            % 4096 Hz after the authors' 1:16 decimation
    DEC    = 16;
    FS     = FS_RAW / DEC;

    files = dir(fullfile(cwRoot, '**', '*.mat'));
    assert(~isempty(files), 'experiments:analyzeTSMSCw:noFiles', ...
        'No .mat under %s', cwRoot);
    fprintf('analyzeTSMSCw: %d .mat files under %s\n', numel(files), cwRoot);

    % ---- parse '{Model}_{N}m_{idx}.mat' -------------------------------
    tok = regexp({files.name}, '^(.*)_(\d+)m_(\d+)\.mat$', 'tokens', 'once');
    keep = ~cellfun(@isempty, tok);
    files = files(keep); tok = tok(keep);
    assert(~isempty(files), 'experiments:analyzeTSMSCw:noParse', ...
        'No filenames matched {Model}_{N}m_{idx}.mat -- check the layout.');
    model = string(cellfun(@(t) t{1}, tok, 'uni', 0))';
    rangeM = cellfun(@(t) str2double(t{2}), tok)';
    repIdx = cellfun(@(t) str2double(t{3}), tok)';

    models = unique(model);
    ranges = unique(rangeM);
    fprintf('  targets: %s\n', strjoin(cellstr(models)', ', '));
    fprintf('  ranges : %s m\n', mat2str(ranges'));

    nM = numel(models); nR = numel(ranges);
    bodyDb   = nan(nM, nR, perCell);   % NaN by design -- ungated CW, see localSpectrum
    sbDepth  = nan(nM, nR, perCell);   % NaN by design -- needs a range gate
    sbFrac   = nan(nM, nR, perCell);   % resolved-line power / residual power
    leakDb   = nan(nM, nR, perCell);   % Tx->Rx leakage level [dB]
    nLines   = nan(nM, nR, perCell);   % sideband count
    lineHz   = nan(nM, nR, perCell);   % median line spacing [Hz] = blade passage
    maxHz    = nan(nM, nR, perCell);   % micro-Doppler extent [Hz]

    t0 = tic;
    for im = 1:nM
        for ir = 1:nR
            sel = find(model == models(im) & rangeM == ranges(ir));
            if isempty(sel); continue; end
            [~, o] = sort(repIdx(sel)); sel = sel(o);
            sel = sel(1:min(perCell, numel(sel)));
            for k = 1:numel(sel)
                f = fullfile(files(sel(k)).folder, files(sel(k)).name);
                m = localSpectrum(f, DEC, FS);
                if isempty(m); continue; end
                bodyDb(im,ir,k)  = m.bodyDb;
                sbDepth(im,ir,k) = m.depth;
                sbFrac(im,ir,k)  = m.sbFrac;
                leakDb(im,ir,k)  = m.leakDb;
                nLines(im,ir,k)  = m.nLines;
                lineHz(im,ir,k)  = m.lineHz;
                maxHz(im,ir,k)   = m.maxHz;
            end
        end
        fprintf('  %-18s done (%.1f min)\n', models(im), toc(t0)/60);
    end

    out = struct('models', models, 'ranges', ranges, 'perCell', perCell, ...
        'fs', FS, 'bodyDb', bodyDb, 'sbDepth', sbDepth, 'sbFrac', sbFrac, ...
        'leakDb', leakDb, 'nLines', nLines, 'lineHz', lineHz, 'maxHz', maxHz, ...
        'elapsedMin', toc(t0)/60);

    % NO amplitude-vs-range fit is attempted here. An ungated CW receiver
    % cannot separate a static or hovering target's body return from the
    % Tx->Rx leakage sitting on the same zero-Doppler bin, so any slope
    % fitted from this data would be a property of the leakage. The first
    % version of this file did fit one and got ~0 dB/decade for every target
    % including the corner reflector, against a two-way law of -40 -- which
    % is exactly what a leakage measurement looks like. That fit is removed
    % rather than caveated. The measurement needs the range-gated FMCW set.

    f = fullfile(outDir, 'tsms_cw_analysis.mat');
    save(f, '-struct', 'out');
    fprintf('analyzeTSMSCw: saved -> %s  (%.1f min)\n', f, out.elapsedMin);

    fprintf('\n--- micro-Doppler comb, after leakage notch (pooled over range) ---\n');
    fprintf('  %-18s %8s %8s %10s %10s\n', 'target', 'lines', 'sbFrac', 'spacing', 'extent');
    for im = 1:nM
        l = lineHz(im,:,:); n = nLines(im,:,:); x = maxHz(im,:,:); s = sbFrac(im,:,:);
        fprintf('  %-18s %8.1f %8.4f %8.1f Hz %8.0f Hz\n', models(im), ...
            mean(n(:),'omitnan'), mean(s(:),'omitnan'), ...
            median(l(:),'omitnan'), mean(x(:),'omitnan'));
    end
    fprintf(['\nCONTROL: "Corner Reflector" is rigid and must show NO rotor lines.\n' ...
             'If its row is not clearly the lowest, the chain is measuring something\n' ...
             'other than micro-Doppler and the drone rows must not be used.\n']);
end

% ========================================================================
function m = localSpectrum(matFile, DEC, FS)
%LOCALSPECTRUM  CW micro-Doppler spectrum, WITH the leakage notch.
%
%   WHY THE NOTCH IS NOT OPTIONAL -- this function got it wrong once.
%   A first version skipped the DC handling in the authors'
%   Example_CW_radar_processing.m, on the reasoning that its clipping and
%   rescaling were cosmetic (they are -- they exist to make images legible).
%   But the DC step is NOT cosmetic. A CW radar transmits and receives
%   simultaneously, so direct Tx->Rx LEAKAGE sits at zero Doppler and
%   dominates every other return by orders of magnitude.
%
%   Taking max(P) as the "body line" therefore measured the leakage, which is
%   independent of where the target was standing. THE CORNER REFLECTOR CAUGHT
%   IT: a rigid reflector with no moving parts reported the same modulation
%   depth (0.501) and the same sideband count (2.0) as a quadcopter, and
%   amplitude-vs-range came out at ~0 dB/decade for every target when the
%   two-way law requires -40. Both are signatures of measuring leakage.
%
%   WHAT CW CAN AND CANNOT GIVE, after the notch:
%     CAN  line spacing (= blade passage rate) and micro-Doppler extent.
%          Both are offsets FROM the carrier, so they survive the notch.
%          Line spacing is mechanical and carrier-independent, which is what
%          makes it directly usable as render.m's micro_doppler_hz.
%     CANNOT  modulation depth relative to the body return, or an
%          amplitude-vs-range law. A CW radar has NO range gate, so a
%          static/hovering target's own body return sits underneath the
%          leakage and cannot be separated from it. Those two quantities need
%          a range-gated sensor -- i.e. the FMCW set, whose RD map put the
%          body cleanly at 8.09 m. Reported as NaN here rather than as a
%          number that would be leakage in disguise.

    m = [];
    try
        S = load(matFile);
    catch
        return;
    end
    if ~isfield(S, 'data'); return; end
    x = S.data;
    if isempty(x); return; end
    x = double(x(:,1));
    if numel(x) < 64*DEC; return; end
    x = resample(x, 1, DEC, 20);

    N = numel(x);
    X = fftshift(fft(x .* hann(N), N));
    P = abs(X);
    fAx = (-N/2 : N/2-1)' * (FS / N);
    df = FS / N;

    % ---- notch the leakage ------------------------------------------
    % Width is derived, not tuned: the leakage is a pure tone, so its
    % footprint is the Hann mainlobe (4 bins wide) plus a bin of margin.
    % Anything wider would start eating real low-rate blade lines.
    notchHz = 5 * df;
    [leakPk, iLeak] = max(P);
    fLeak = fAx(iLeak);
    m.leakDb = 20*log10(leakPk + eps);
    keep = abs(fAx - fLeak) > notchHz;

    Pn = P; Pn(~keep) = 0;
    if ~any(Pn); return; end

    % Sideband peaks, on the leakage-free residual. Prominence is referenced
    % to the RESIDUAL's own scale, not to the leakage -- referencing it to
    % the leakage peak was the second half of the original bug.
    med = median(Pn(keep));
    [pks, locs] = findpeaks(Pn, 'MinPeakProminence', 6*med, 'MinPeakDistance', 2);
    fSb = fAx(locs) - fLeak;

    m.nLines = numel(fSb);
    % Sideband power fraction: how much of the non-leakage energy is in
    % resolved lines. A rigid reflector should sit near zero; this is the
    % control quantity that the broken version could not produce.
    m.sbFrac = sum(pks.^2) / (sum(Pn(keep).^2) + eps);
    m.bodyDb = NaN;      % see header: not recoverable from ungated CW
    m.depth  = NaN;
    if isempty(pks)
        m.lineHz = NaN; m.maxHz = 0;
    else
        m.maxHz = max(abs(fSb));
        d = diff(sort(fSb));
        d = d(d > df);
        if isempty(d); m.lineHz = NaN; else; m.lineHz = median(d); end
    end
end
