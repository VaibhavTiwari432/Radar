function out = checkAgilityMechanism(fixtureDir)
%CHECKAGILITYMECHANISM  Diagnostic backing Phase B's agility row
%   (PHASE_B_RESULTS.md): proves the sweep-mismatch penalty is actually
%   live and reproduces this project's previously-documented ~14 dB loss,
%   before trusting a P_confirm=1.00 headline cell as "no effect" rather
%   than "effect too small to flip the label at N=5".
%
%   out = generator.checkAgilityMechanism(fixtureDir)
%       fixtureDir : contains phaseB_1phantom_agile.mat, written by
%                    python generator/tests/build_phase_b_scenes.py <dir>
%
%   The output struct is what makes claim C2 testable rather than merely
%   printed -- tests/test_generator_agility.m asserts on these fields. C2
%   ("agility costs a stale repeater 14.2 dB and 24x range smearing") was
%   marked FROZEN when test_waveform_agility.m broke in the 7 Aug archive;
%   returning the numbers instead of only fprintf-ing them is the whole
%   cost of un-freezing it, since this function already re-derives the
%   measurement on the REBUILT generator.
%
%       out.lossDb            matched/mismatched peak power ratio [dB]
%       out.matchedBins       bins within 3 dB of the matched peak
%       out.mismatchedBins    same, mismatched -- the smearing
%       out.smearRatio        mismatchedBins / matchedBins
%       out.fbOmni, out.fbStale   judge feedback, omniscient vs stale belief

    here = fileparts(fileparts(mfilename('fullpath')));
    addpath(here);
    agileMat = fullfile(fixtureDir, 'phaseB_1phantom_agile.mat');

    rng(1, 'twister');
    omniJudge = fullfile(fixtureDir, 'check_omniscient_judge.mat');
    generator.render(agileMat, omniJudge, 'IncludeAngleChannel', true);
    fbOmni = engine.runJudge(omniJudge, 'FilterModel', 'imm');

    rng(1, 'twister');
    staleJudge = fullfile(fixtureDir, 'check_stale_judge.mat');
    generator.render(agileMat, staleJudge, 'IncludeAngleChannel', true, ...
        'PhantomSweepSchedule', ones(1,8));
    fbStale = engine.runJudge(staleJudge, 'FilterModel', 'imm');

    fprintf('OMNISCIENT belief : confirmed=%d label=%s reconstructed_detections=%d\n', ...
        fbOmni.confirmed_tracks, fbOmni.eccm_label, numel(fbOmni.track_range_m{1}));
    fprintf('STALE belief      : confirmed=%d label=%s reconstructed_detections=%d\n', ...
        fbStale.confirmed_tracks, fbStale.eccm_label, numel(fbStale.track_range_m{1}));

    % Isolated check: matched vs mismatched single-pulse peak, same waveform
    % params this fixture uses -- reproduces RADAR_REALISM_AUDIT.md's own
    % documented ~14.2 dB loss / 24x smearing, confirming the MECHANISM
    % (not this scene's SNR margin) is real and wired, before reading
    % Table 1's plus_agility row as a genuine null result.
    S = load(agileMat);
    fs = double(S.fs); pw = double(S.pulse_width_s); bw = double(S.bandwidth_hz); prf = double(S.prf_hz);
    [~, upPulse] = radar.agileWaveform(1, fs, pw, prf, bw);
    wavDown = radar.agileWaveform(-1, fs, pw, prf, bw);
    rx = complex(zeros(400,1));
    rx(51:50+numel(upPulse)) = upPulse;   % transmitted up-chirp echo
    powerMatched = radar.pulseCompress(rx, radar.agileWaveform(1, fs, pw, prf, bw));
    powerMismatched = radar.pulseCompress(rx, wavDown);
    % Smearing, measured the same way for both arms: bins within 3 dB of
    % that arm's OWN peak. A -3 dB width is the standard main-lobe measure
    % and is self-referencing, so it reports spreading independently of the
    % 14 dB level drop happening at the same time -- an absolute threshold
    % would conflate the two effects and overstate the smearing.
    matchedBins    = nnz(powerMatched    >= max(powerMatched)    / 2);
    mismatchedBins = nnz(powerMismatched >= max(powerMismatched) / 2);
    lossDb = 10*log10(max(powerMatched)/max(powerMismatched));

    fprintf('\nIsolated check: up-chirp echo, matched(up) vs mismatched(down) filter\n');
    fprintf('  matched    peak power = %.4f  (%d bins within 3 dB)\n', max(powerMatched), matchedBins);
    fprintf('  mismatched peak power = %.4f  (%d bins within 3 dB)\n', max(powerMismatched), mismatchedBins);
    fprintf('  loss = %.2f dB, smearing = %.1fx\n', lossDb, mismatchedBins/matchedBins);

    out = struct('lossDb', lossDb, ...
                 'matchedBins', matchedBins, ...
                 'mismatchedBins', mismatchedBins, ...
                 'smearRatio', mismatchedBins / matchedBins, ...
                 'fbOmni', fbOmni, 'fbStale', fbStale);
end
