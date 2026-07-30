function out = analyzeTSMSCornerReflector(rootDir, perRange, outDir)
%ANALYZETSMSCORNERREFLECTOR  The two things a rigid known-RCS target at known
%   ranges can honestly tell this project, and nothing beyond them.
%
%   out = experiments.analyzeTSMSCornerReflector(rootDir, perRange, outDir)
%       rootDir : folder holding CornerReflector_<N>m/ extracted trees
%
%   (1) SHAPE TEST on the amplitude law. A two-way monostatic return has
%       power ~ 1/R^4, i.e. 20*log10(amplitude) falls at -40 dB/decade.
%       +engine/+entity/render.m already assumes exactly that form
%       (amplitude ~ sqrt(RCS)/R^2, anchored at ReferenceRangeM). This
%       measures whether the FORM holds against a real rigid reflector.
%
%   (2) SCINTILLATION. Standard deviation of 20*log10(amplitude) across
%       repetitions AT A FIXED RANGE. +engine/+entity/calibrateQ.m's
%       rcs_process_std_db = 0.233 dB currently comes from RadChar, which is
%       an emitter's own pulse train -- no target, no return, no motion. A
%       per-range spread from a real reflector is the first measurement of
%       that quantity from an actual target echo.
%
%   WHAT IS DELIBERATELY *NOT* DONE HERE
%   -----------------------------------
%   No absolute link budget is imported. This sensor is 24.125 GHz FMCW at
%   2-30 m; this project is 10 GHz pulse-Doppler at 1800-3800 m. Absolute
%   levels do not transfer and are not carried across. Only (1) a
%   dimensionless SHAPE and (2) a relative SPREAD leave this function, and
%   both are band-independent in a way an absolute power is not.
%
%   EXPECT MULTIPATH, AND DO NOT CALL IT A FAILURE. A two-ray ground bounce
%   at 2-30 m produces interference maxima and minima that ride on top of the
%   R^-4 trend. Deviation from -40 dB/decade is therefore an interpretable
%   measurement of the test range, not evidence against the radar equation.
%   Antenna near field is NOT a concern: the Fraunhofer distance for the
%   TinyRad's small aperture is ~0.4 m, well inside the closest station.

    if nargin < 2 || isempty(perRange); perRange = 100; end
    if nargin < 3 || isempty(outDir)
        here = fileparts(mfilename('fullpath'));
        outDir = fullfile(fileparts(here), 'results');
    end
    if ~isfolder(outDir); mkdir(outDir); end

    d = dir(fullfile(rootDir, 'CornerReflector_*m'));
    d = d([d.isdir]);
    assert(~isempty(d), 'experiments:cr:noDirs', ...
        'No CornerReflector_<N>m folders under %s', rootDir);
    rng_ = arrayfun(@(x) sscanf(x.name, 'CornerReflector_%dm'), d);
    [rng_, o] = sort(rng_); d = d(o);

    nR = numel(rng_);
    ampDb  = nan(nR, perRange);
    nUsed  = zeros(nR, 1);

    fprintf('analyzeTSMSCornerReflector: %d ranges: %s m\n', nR, mat2str(rng_'));
    t0 = tic;
    for ir = 1:nR
        files = dir(fullfile(d(ir).folder, d(ir).name, '**', '*.mat'));
        if isempty(files); fprintf('  %3dm : no .mat\n', rng_(ir)); continue; end
        [~, o2] = sort({files.name}); files = files(o2);
        take = min(perRange, numel(files));
        for k = 1:take
            a = localBodyAmplitude(fullfile(files(k).folder, files(k).name), rng_(ir));
            if ~isnan(a); ampDb(ir,k) = a; end
        end
        nUsed(ir) = nnz(isfinite(ampDb(ir,:)));
        fprintf('  %3dm : %4d reps | mean %7.2f dB | std %5.3f dB   [%.1f min]\n', ...
            rng_(ir), nUsed(ir), mean(ampDb(ir,:),'omitnan'), ...
            std(ampDb(ir,:),0,2,'omitnan'), toc(t0)/60);
    end

    meanDb = mean(ampDb, 2, 'omitnan');
    stdDb  = std(ampDb, 0, 2, 'omitnan');

    out = struct('ranges', rng_(:), 'ampDb', ampDb, 'meanDb', meanDb, ...
        'stdDb', stdDb, 'nUsed', nUsed, 'perRange', perRange, ...
        'elapsedMin', toc(t0)/60);

    % ---- shape test -------------------------------------------------
    g = isfinite(meanDb) & rng_(:) > 0;
    if nnz(g) >= 3
        x = log10(rng_(g)); y = meanDb(g);
        [p, S] = polyfit(x, y, 1);
        Cv = (S.normr^2/S.df) * inv(S.R'*S.R); %#ok<MINV>
        se = sqrt(Cv(1,1));
        out.slopeDbPerDecade = p(1);
        out.slopeCI = p(1) + [-1 1]*1.96*se;
        yhat = polyval(p, x);
        out.residDb = y - yhat;
        out.rmseDb  = sqrt(mean((y-yhat).^2));
        fprintf('\nAmplitude-law SHAPE TEST\n');
        fprintf('  measured %+.1f dB/decade  [95%% CI %+.1f, %+.1f]\n', ...
            out.slopeDbPerDecade, out.slopeCI(1), out.slopeCI(2));
        fprintf('  two-way ideal is -40.0 dB/decade -> deviation %+.1f dB/decade\n', ...
            out.slopeDbPerDecade + 40);
        fprintf('  residual RMSE about the fit = %.2f dB (multipath ripple lives here)\n', out.rmseDb);
    end

    fprintf('\nSCINTILLATION (spread at fixed range, the transferable quantity)\n');
    for ir = 1:nR
        fprintf('  %3dm : std %5.3f dB  (n=%d)\n', rng_(ir), stdDb(ir), nUsed(ir));
    end
    fprintf('  pooled std = %.3f dB   vs calibrateQ rcs_process_std_db = 0.233 dB (RadChar)\n', ...
        sqrt(mean(stdDb(isfinite(stdDb)).^2)));

    f = fullfile(outDir, 'tsms_cr_analysis.mat');
    save(f, '-struct', 'out');
    fprintf('\nsaved -> %s  (%.1f min)\n', f, out.elapsedMin);
end

% ========================================================================
function aDb = localBodyAmplitude(matFile, distanceM)
%LOCALBODYAMPLITUDE  Peak |RD| in a +-1 m window about the nominal station.
%   Range axis convention is the authors' own
%   (Example_FMCW_radar_processing.m): the RD map covers a 12 m window whose
%   offset depends on which distance bucket the capture belongs to.
    aDb = NaN;
    try
        S = load(matFile);
    catch
        return;
    end
    if ~isfield(S, 'RD'); return; end
    RD = S.RD;
    if isempty(RD); return; end

    nRangeBins = size(RD, 1);
    if distanceM <= 10
        vRangeExt = linspace(0, 12, nRangeBins);
    elseif distanceM <= 20
        vRangeExt = linspace(10, 22, nRangeBins);
    else
        vRangeExt = linspace(20, 32, nRangeBins);
    end

    sel = vRangeExt >= (distanceM - 1) & vRangeExt <= (distanceM + 1);
    if ~any(sel); return; end
    win = abs(RD(sel, :));
    pk = max(win(:));
    if ~(pk > 0); return; end
    aDb = 20*log10(pk);
end
