function checkAgilityMechanism(fixtureDir)
%CHECKAGILITYMECHANISM  Diagnostic backing Phase B's agility row
%   (PHASE_B_RESULTS.md): proves the sweep-mismatch penalty is actually
%   live and reproduces this project's previously-documented ~14 dB loss,
%   before trusting a P_confirm=1.00 headline cell as "no effect" rather
%   than "effect too small to flip the label at N=5".
%
%   generator.checkAgilityMechanism(fixtureDir)
%       fixtureDir : contains phaseB_1phantom_agile.mat, written by
%                    python generator/tests/build_phase_b_scenes.py <dir>

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
    fprintf('\nIsolated check: up-chirp echo, matched(up) vs mismatched(down) filter\n');
    fprintf('  matched    peak power = %.4f\n', max(powerMatched));
    fprintf('  mismatched peak power = %.4f\n', max(powerMismatched));
    fprintf('  loss = %.2f dB\n', 10*log10(max(powerMatched)/max(powerMismatched)));
end
