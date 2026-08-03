function out = crossEyeSpike()
%CROSSEYESPIKE  Tier 2.3 -- feasibility of cross-eye jamming against this
%   project's monopulse co-bearing veto. FEASIBILITY ONLY: no scene, no CFAR,
%   no tracker. The question is narrow and answerable in closed form -- can a
%   two-element cross-eye pair move the REPORTED azimuth far enough to break
%   the co-bearing screen, and what phase stability does that demand?
%
%   WHY THIS IS THE ONLY CANDIDATE COUNTER. Section 4.8 / 7.7: range, Doppler
%   and amplitude can each be forged per-phantom, but azimuth cannot, because
%   it is set by where the transmitter physically is. The co-bearing screen
%   exploits exactly that and condemns 4/4 phantoms in 8/8 seeds. Cross-eye is
%   the one physically grounded technique that attacks the ANGLE MEASUREMENT
%   itself rather than trying to forge a bearing.
%
%   THE MECHANISM. Two coherent sources separated by a baseline D, radiating
%   with amplitude ratio a and relative phase phi_ce. The radar sums them in
%   both its channels, so the monopulse ratio it forms is
%
%       Delta/Sigma = i * [ s1*tan(phi1/2) + s2*tan(phi2/2) ] / (s1 + s2)
%
%   with s2/s1 = a*exp(i*phi_ce) and phi_k the monopulse phase of each
%   element. As a -> 1 and phi_ce -> 180 deg the DENOMINATOR vanishes while
%   the numerator does not, so the ratio -- and the apparent angle -- diverges.
%   That divergence is the entire technique: a tiny physical baseline
%   produces an unboundedly large apparent angle error.
%
%   EVERY NUMBER BELOW USES THIS PROJECT'S OWN ESTIMATOR, verbatim from
%   +engine/runJudge.m:299-303, so the measurement is of the real judge and
%   not of a textbook idealisation:
%       phiEst = 2*atan(imag(ratio));  sinTheta = phiEst*lambda/(2*pi*subSep)

    C = physics.Constants();
    lambda = C.lambda;
    subSep = 0.30;                       % radar subaperture separation [m]
    unambigDeg = asind(min(1, lambda/(2*subSep)));

    R  = 1800;                           % jammer range [m]
    D  = 1.0;                            % cross-eye baseline on the mother drone [m]
    thetaJammer = 0.8;                   % true bearing of the jammer [deg]

    fprintf('\n=== 2.3 CROSS-EYE FEASIBILITY vs the monopulse co-bearing veto ===\n');
    fprintf('radar subaperture %.2f m | lambda %.4f m | unambiguous sector +-%.3f deg\n', ...
        subSep, lambda, unambigDeg);
    fprintf('jammer at %.0f m, true bearing %+.2f deg | cross-eye baseline %.2f m\n', ...
        R, thetaJammer, D);
    fprintf('baseline subtends %.4f deg at that range -- the RAW angular size\n', ...
        2*atand(D/(2*R)));

    % The two elements, symmetric about the jammer's true bearing.
    dTheta = atand(D/(2*R));
    th1 = thetaJammer - dTheta;
    th2 = thetaJammer + dTheta;

    fprintf('\n%10s | %s\n', '', 'apparent bearing [deg] at phase phi_ce');
    fprintf('%10s |', 'ampl a');
    phases = [150 170 175 178 179 179.5 180];
    for ph = phases; fprintf(' %7.1f', ph); end
    fprintf('\n');

    amps = [0.5 0.8 0.9 0.95 0.99 1.00];
    app = nan(numel(amps), numel(phases));
    for i = 1:numel(amps)
        fprintf('%10.2f |', amps(i));
        for j = 1:numel(phases)
            app(i,j) = localApparent(th1, th2, amps(i), phases(j), lambda, subSep);
            fprintf(' %7.3f', app(i,j));
        end
        fprintf('\n');
    end

    % ---- does it break the co-bearing screen? ----------------------------
    % runJudge's screen: flag when the SPREAD of the tracks' mean azimuths is
    % smaller than 3x their own pooled within-track scatter. So the adversary
    % must induce a spread EXCEEDING 3*sigma_theta. sigma_theta at the
    % phantom's own SNR is the yardstick, taken from the same formula
    % tests/test_monopulse_snr_boundary.m uses.
    theta3dB = 3.0; kM = 1.6; snrDb = 20;
    sigTheta = theta3dB / (kM * sqrt(2 * 10^(snrDb/10)));
    needed = 3 * sigTheta;
    fprintf('\nCO-BEARING SCREEN THRESHOLD\n');
    fprintf('  sigma_theta at %+d dB SNR = %.4f deg -> screen needs a spread > %.4f deg\n', ...
        snrDb, sigTheta, needed);

    achievable = max(app(:)) - min(app(:));
    fprintf('  spread achievable across the swept (a, phi_ce) grid = %.3f deg\n', achievable);
    fprintf('  => cross-eye CAN exceed the screen threshold: %s\n', ...
        string(achievable > needed));

    % ---- a = 1 EXACTLY IS A NULL, and the reason is the estimator --------
    % The classic cross-eye result is that gain DIVERGES as a -> 1 with
    % phi_ce -> 180 deg, because Sigma vanishes. That divergence is in the
    % FULL COMPLEX ratio. This radar takes only its IMAGINARY part
    % (runJudge:301, phiEst = 2*atan(imag(ratio))), and at a = 1 exactly:
    %
    %   ratio = i*(t1 + z*t2)/(1 + z),  z = e^{i*phi}
    %         = i*(t1+t2)/2  -  (t2-t1)*tan(phi/2)/2
    %
    % The phi-dependent term is REAL, so imag(ratio) = (t1+t2)/2 -- the
    % MIDPOINT of the two elements, independent of phi_ce. The apparent
    % bearing is the jammer's own bearing and the technique does nothing.
    % Verified numerically in the a = 1.00 row above: 0.800 deg at every
    % phase, i.e. exactly the true bearing.
    %
    % So the phase-tolerance sweep must be run at the amplitude that actually
    % deflects, not at the textbook optimum. A first version swept at a = 1.00
    % and reported a 0.0001 deg offset at every phase -- measuring the null.
    [~, iBest] = max(max(abs(app - thetaJammer), [], 2));
    aBest = amps(iBest);
    fprintf('\nPHASE STABILITY REQUIRED (at a = %.2f, the amplitude that deflects)\n', aBest);
    tol = nan;
    for dphi = [0.1 0.2 0.5 1 2 5 10 20 30]
        e = abs(localApparent(th1, th2, aBest, 180 - dphi, lambda, subSep) - thetaJammer);
        fprintf('  phi_ce = 180 - %5.1f deg -> apparent offset from truth %.4f deg %s\n', ...
            dphi, e, string(e > needed));
        if e > needed; tol = dphi; end
    end
    fprintf('  => largest phase error still exceeding the screen threshold: %s deg\n', ...
        mat2str(tol));

    out = struct('apparent', app, 'amps', amps, 'phases', phases, ...
                 'sigThetaDeg', sigTheta, 'neededDeg', needed, ...
                 'achievableDeg', achievable, 'phaseTolDeg', tol, ...
                 'unambigDeg', unambigDeg);

    fprintf('\n=== 2.3 READING ===\n');
    fprintf(['  The apparent bearing SATURATES at the unambiguous sector edge\n' ...
             '  (+-%.3f deg), because runJudge estimates phi via 2*atan(imag(.)),\n' ...
             '  which is bounded by +-pi by construction. Cross-eye cannot push the\n' ...
             '  reported angle past that edge no matter how large the true induced\n' ...
             '  error becomes -- it can only move it ANYWHERE INSIDE the sector,\n' ...
             '  which is already enough to defeat a screen that tests for a SHARED\n' ...
             '  bearing.\n'], unambigDeg);
end

% ------------------------------------------------------------------------
function thetaAppDeg = localApparent(th1Deg, th2Deg, a, phiCeDeg, lambda, subSep)
%LOCALAPPARENT  Apparent bearing the JUDGE reports for a two-source cross-eye
%   pair. Uses +engine/runJudge.m's own estimator, not a textbook formula.
    phi1 = 2*pi * subSep * sind(th1Deg) / lambda;
    phi2 = 2*pi * subSep * sind(th2Deg) / lambda;

    s1 = 1;
    s2 = a * exp(1i * deg2rad(phiCeDeg));

    sig = s1 + s2;
    dif = 1i * (s1*tan(phi1/2) + s2*tan(phi2/2));
    if abs(sig) < eps
        thetaAppDeg = NaN; return;      % perfect null: no Sigma channel at all
    end

    ratio  = dif / sig;
    phiEst = 2 * atan(imag(ratio));                 % runJudge:301
    sinTh  = phiEst * lambda / (2*pi*subSep);       % runJudge:302
    thetaAppDeg = asind(max(-1, min(1, sinTh)));    % runJudge:303
end
