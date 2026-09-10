function out = v3Ablation(numSeeds, outDir)
%V3ABLATION  The leave-one-out ablation the spec calls its contribution.
%
%   out = experiments.v3Ablation(numSeeds, outDir)
%
%   PHANTOM_GENERATOR_ARCHITECTURE_v1.md rung V3: seven arms, each violating
%   exactly ONE physical law, all scored by the same judge on the same
%   trajectory, so a detection can be attributed to a SCREEN rather than to
%   "the system". Its own words: "Each row isolates one physical law. This
%   table IS the contribution."
%
%   ARM  VIOLATION                          SHOULD BE EXPOSED BY
%    A   none -- the genuine control        nothing (false-alarm check)
%    B   tau rounded to a whole sample      range-rate continuity
%    C   f_d unlocked from tau-dot (x0.1)   screen 2d, rangeRateConsistency
%    D   phi randomised every pulse         pulse-pair Doppler (screen 2)
%    E   A constant, no 1/R^4               amplitude-range slope (screen 1)
%    F   Swerling off, sigma constant       amplitude residual (screen 4)
%    G   kinematic bounds removed           velocity ambiguity -> screen 2
%
%   EVERY ARM SHARES ONE TRAJECTORY. The violations are applied to the DERIVED
%   quantities inside generator/tests/build_scene.py, after project_action's
%   vetoes have run -- so no arm is physically impossible, and two arms differ
%   in exactly one observable. Corrupting the trajectory instead would move
%   detection as well as the label, and a row would stop being an attribution.
%   generator/tests/test_render_identity.py asserts that orthogonality arm by
%   arm; this file assumes it.
%
%   WHAT THIS TABLE DOES AND DOES NOT MEASURE. It measures ATTRIBUTION -- which
%   screen catches which violation. It does NOT measure absolute deception
%   rates, and on this instrument it could not:
%
%     * C.bandwidth = 2 MHz against C.fs = 3.2 MHz ALIASES the transmit
%       waveform (MEASURED: 18.2% of the chirp's energy folds past +-fs/2, and
%       radar.agileWaveform's Up chirp sweeps +104 kHz to -1377 kHz). Sub-bin
%       interpolation is therefore left OFF here -- it recovers nothing at this
%       fs/B, per radar.subBinPeak's header.
%     * There is no P_confirm(real target) to divide by. The spec's own
%       section 5.3 metric D = P_confirm(phantom)/P_confirm(real) needs rung
%       V4, which needs hardware this bench does not have.
%
%   So quote a row as "screen X catches violation Y", never as a percentage.

    if nargin < 1 || isempty(numSeeds); numSeeds = 5; end
    if nargin < 2 || isempty(outDir);   outDir = fullfile('results', 'v3_ablation'); end
    if ~exist(outDir, 'dir'); mkdir(outDir); end

    C = physics.Constants();

    % The genuine arm is FRACTIONAL-DELAY and FLUCTUATING, deliberately. A
    % control that rounded its own delay would make arm B a comparison of a
    % thing with itself, and one with sigma constant would make arm F the same.
    % Both are only expressible because +generator/render.m gained
    % FractionalDelay and build_scene's Swerling path was repaired (21 Aug 2026
    % -- it raised FrozenInstanceError on every call before that, so no scene in
    % this repo had ever been rendered with target fluctuation).
    % ARM G ALSO HAS TO FIT. At -80 m/s over 40 frames the phantom ends at
    % 6000 - 3120 = 2880 m, clear of the 1799 m blind range (c*PW/2); at the
    % earlier 2200 m start it ended INSIDE it and project_action refused the
    % scene, correctly. Every arm uses the same start, because giving G its own
    % would break the one property that makes this a leave-one-out table.
    % 6000 m AND 40 FRAMES, AND BOTH NUMBERS WERE MEASURED, NOT CHOSEN.
    % The genuine control has to PASS or no row below means anything, and
    % screen 1 (log A vs log R, slope -2) is far harder to satisfy than its
    % description suggests. Sweeping start range, track length and Swerling
    % case, 21 Aug 2026, label of the GENUINE arm under {'amplitude'} alone:
    %
    %     R0    frames  lever   sw0     sw1     sw3
    %    2600      8    2.5 dB  decoy   decoy   decoy
    %    2600     16    5.9 dB  real    decoy   decoy
    %    4500     32    7.3 dB  real    decoy   real
    %    6000     32    5.2 dB  real    decoy   real
    %    6000     40    6.8 dB  real    REAL    real
    %
    % Two independent things have to be bought. A LEVER: at 8 frames the range
    % only walks 2600 -> 2250 m, which is 2.5 dB of amplitude, and a log-log
    % slope cannot be fitted through that -- the screen condemns a genuine
    % target with NO fluctuation at all. And SAMPLES: Swerling 1 is
    % exponential (CV = 1), so even with a good lever the fit needs ~40 points
    % before the slope settles; Swerling 3 (chi-square 4 dof, gentler) settles
    % by 32.
    %
    % This corroborates the discriminator's own note that screen 1 "passes only
    % 12% of genuine targets at 8 frames", and claim E4 -- the amplitude screen
    % rejecting physically-consistent targets through measurement noise rather
    % than discrimination. Every scene shorter than this in the repo is running
    % screen 1 outside its usable envelope.
    base = {'NumFrames', 40, 'NumPulses', 32, 'MotherRangeM', 900, ...
            'MotherVelocityMps', [0 3 0], 'Swerling', 1, ...
            'FractionalDelay', true};
    startRangeM = 6000;

    arms = struct( ...
      'name',  {'A genuine', 'B integer delay', 'C doppler unlocked', ...
                'D random phase', 'E flat amplitude', 'F no swerling', ...
                'G unbounded kinematics'}, ...
      'rate',  {-50, -50, -50, -50, -50, -50, -80}, ...
      'extra', {{}, ...
                {'FractionalDelay', false}, ...
                {'Ablation', struct('doppler_scale', 0.1)}, ...
                {'Ablation', struct('random_phase', true)}, ...
                {'Ablation', struct('constant_amplitude', true)}, ...
                {'Swerling', 0}, ...
                {'CheckVelocityAmbiguity', false}}, ...
      ... % The screens that can SEE this arm's violation. Each mask holds at
      ... % least one SCORING screen on purpose: discriminator.m scores an empty
      ... % screen set 0.5 and `> 0.5` is false, so a veto-only mask returns
      ... % "decoy" for EVERY scene from the floor rule rather than from a
      ... % catch. MEASURED: {'micro'}, {'rangerate'} and {'residual'} alone
      ... % each condemn the GENUINE arm for exactly that reason.
      'targeted', {{'amplitude', 'doppler'}, ...
                   {'amplitude', 'rangerate'}, ...
                   {'doppler', 'rangerate'}, ...
                   {'doppler'}, ...
                   {'amplitude'}, ...
                   {'amplitude', 'residual'}, ...
                   {'doppler'}});

    % Every screen that any arm below can violate, including 'rangerate',
    % which postdates the published numbers. An ablation run is exactly the
    % place to switch a new screen on: the point is to see which one fires,
    % not to preserve a baseline.
    %
    % 'bearing' (screen 2c) IS DELIBERATELY EXCLUDED, and not because it is
    % weak. It tests whether a track's bearing obeys R^2*dtheta/dt = const,
    % which a phantom satisfies only when the mother's radial policy is
    % PROPORTIONAL to the phantom's own: Rdot_m/R_m(0) == Rdot_p/R_p(0). This
    % scene's platform crosses at 3 m/s with no radial component, so that
    % ratio is 0 against the phantom's, and 2c correctly condemns EVERY arm --
    % including the genuine control, MEASURED at flagged 1.00 in the first run
    % of this file. A screen that fires on all seven rows carries no
    % attribution, and leaving it in would have made the control useless.
    %
    % Testing 2c needs a purpose-built geometry with a matched mother radial
    % rate; +experiments/bearingHeadroom.m already characterises that basin
    % (peak at exactly the matched -19.6 m/s for a 2300 m phantom closing at
    % -50). That is a separate experiment, not a row here.
    screens = {'amplitude', 'doppler', 'micro', 'rangerate', 'residual'};

    nArms = numel(arms);
    confirmed = zeros(nArms, numSeeds);
    flagged   = zeros(nArms, numSeeds);
    survived  = zeros(nArms, numSeeds);
    flaggedT  = zeros(nArms, numSeeds);

    for a = 1:nArms
        for s = 1:numSeeds
            rng(s, 'twister');
            tag = sprintf('v3_%d_%d', a, s);
            judgeMat = renderPhantomScene(startRangeM, arms(a).rate, base{:}, ...
                           'Seed', s, 'Tag', tag, arms(a).extra{:});
            fb = engine.runJudge(judgeMat, 'EccmScreens', screens);

            confirmed(a, s) = double(fb.confirmed_tracks);
            lbl = string(fb.track_label);
            flagged(a, s)  = sum(lbl == "decoy");
            survived(a, s) = sum(lbl == "real");

            % ...and again under the arm's OWN screens. The gap between the
            % two columns is not bookkeeping: it is the dilution effect this
            % project has now measured three times (CLAIMABLE_RESULTS.md F5,
            % DECEPTION_MAP_RESULTS.md section 6, and here).
            fbT = engine.runJudge(judgeMat, 'EccmScreens', arms(a).targeted);
            flaggedT(a, s) = sum(string(fbT.track_label) == "decoy");
        end
        fprintf('  %-24s conf %.2f  flag(full) %.2f  flag(own) %.2f\n', ...
            arms(a).name, mean(confirmed(a,:)), mean(flagged(a,:)), mean(flaggedT(a,:)));
    end

    fprintf('\n');
    fprintf('V3 LEAVE-ONE-OUT ABLATION -- %d seeds, screens {%s}\n', ...
        numSeeds, strjoin(screens, ','));
    fprintf('%-24s %6s %20s %20s  %s\n', 'arm', 'conf', ...
        'P(flag) FULL mask', 'P(flag) own screen', 'own screens');
    fprintf('%s\n', repmat('-', 1, 104));
    pFlag = zeros(nArms,1); loF = pFlag; hiF = pFlag;
    pT = pFlag; loT = pFlag; hiT = pFlag;
    for a = 1:nArms
        [pFlag(a), loF(a), hiF(a)] = localWilsonCI(sum(flagged(a,:)  >= 1), numSeeds);
        [pT(a),    loT(a), hiT(a)] = localWilsonCI(sum(flaggedT(a,:) >= 1), numSeeds);
        fprintf('%-24s %6.2f     %.2f [%.2f, %.2f]      %.2f [%.2f, %.2f]  {%s}\n', ...
            arms(a).name, mean(confirmed(a,:)), pFlag(a), loF(a), hiF(a), ...
            pT(a), loT(a), hiT(a), strjoin(arms(a).targeted, ','));
    end
    fprintf('%s\n', repmat('-', 1, 104));
    fprintf('A row caught by its OWN SCREEN but not by the FULL MASK is DILUTION:\n');
    fprintf('the verdict is mean(scores) > 0.5, so a passing screen averages a\n');
    fprintf('failing one back to `real`. Third independent measurement of it.\n');
    fprintf('Arm A is the FALSE-ALARM control: a non-zero P(flagged) there is the\n');
    fprintf('judge condemning a physically consistent target, not a catch.\n');
    fprintf('Attribution only -- see this file''s header for why no percentage\n');
    fprintf('in this table is a deception rate.\n');

    out = struct('arms', {{arms.name}}, 'numSeeds', numSeeds, ...
                 'screens', {screens}, 'confirmed', confirmed, ...
                 'flagged', flagged, 'survived', survived, ...
                 'flaggedTargeted', flaggedT, 'targeted', {{arms.targeted}}, ...
                 'pFlagged', pFlag, 'ciLo', loF, 'ciHi', hiF, ...
                 'pFlaggedTargeted', pT, 'ciLoT', loT, 'ciHiT', hiT);
    save(fullfile(outDir, 'v3_ablation.mat'), '-struct', 'out');
    fprintf('\nwrote %s\n', fullfile(outDir, 'v3_ablation.mat'));
end

function [pHat, lo, hi] = localWilsonCI(s, n)
% Same form as +generator/screenAblation.m's, kept local rather than shared
% because that one is a file-local helper there too -- promoting it to a
% package function is a refactor with its own regression surface.
    z = 1.96; pHat = s / n;
    denom = 1 + z^2/n;
    centre = (pHat + z^2/(2*n)) / denom;
    half = (z/denom) * sqrt(pHat*(1-pHat)/n + z^2/(4*n^2));
    lo = max(0, centre - half); hi = min(1, centre + half);
end
