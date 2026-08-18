function [verdict, diag] = emitterAttribution(feedback)
%EMITTERATTRIBUTION  Which of these positions are real, and which were radiated?
%
%   [verdict, diag] = track.emitterAttribution(feedback)
%
%   verdict : [1 x nTracks] string, one of
%       "radiated-fake"   this track sweeps at an angular rate set by an
%                         aperture NEARER than itself -- it was transmitted,
%                         not reflected
%       "source-or-real"  the nearest member of a shared-rate group. This test
%                         cannot condemn it, and says so rather than clearing
%                         it (see below)
%       "undetermined"    nothing to compare against, and the per-track
%                         fallback could not decide either. THE HONEST ANSWER,
%                         and the one the map exists to make visible
%   diag    : struct array, per track, carrying every quantity the verdict was
%             computed from, so a verdict can be explained rather than trusted
%
%   THE PHYSICS, WHICH IS THE WHOLE RULE. A repeater transmits from ONE
%   aperture. Every phantom it radiates therefore leaves that aperture at the
%   platform's own bearing and sweeps at the platform's own angular rate,
%   while each phantom independently reports a range of its choosing. That is
%   architectural in this project, not incidental: +generator/render.m has one
%   bearing per frame shared by every phantom and no per-phantom angle
%   argument exists to pass (Blueprint 2.4).
%
%   So a group of tracks at DIFFERENT ranges sharing ONE angular rate is a
%   group radiated from one place. Independent aircraft cannot produce it:
%   for a real target omega = v_cross / R, and neither term is shared, so a
%   genuine formation of N members has N angular rates. Equivalently, in
%   metres per second, each member's implied tangential speed R*omega stands
%   in exact proportion to its claimed range -- a formation flying in that
%   precise arrangement is not a scenario anyone need worry about.
%
%   WHY THE NEAREST MEMBER IS NOT CONDEMNED, and why that is not a hedge.
%   Causality forbids a repeater from planting a phantom in front of itself
%   (R_phantom >= R_emitter), so within a shared-rate group only the NEAREST
%   track can be the source. For that one track, omega really is produced by
%   its own motion -- v_cross = R*omega is simply how fast it is going -- and
%   no amount of processing can distinguish "the real platform" from "another
%   phantom, with the platform undetected behind it". "source-or-real" states
%   that ambiguity instead of resolving it by assumption.
%
%   WHY THE SINGLE-TRACK CASE IS SEPARATE. With one track there is no second
%   rate to compare against, so the multi-track argument is unavailable
%   entirely and the decision falls to +track/bearingRateScreen.m (screen 2c),
%   which tests one track's bearing against its OWN range curvature. That
%   screen is genuinely weaker, and predictably so: it separates "theta linear
%   in 1/R" from "theta linear in t", and as range grows the dwell's
%   fractional range change shrinks until the two models converge. Measured on
%   this project's own standard engagement: 0.062 at 3600 m, but 0.494 and
%   0.524 at 5200 and 6800 m -- indistinguishable. When it lands there, this
%   function returns "undetermined" rather than guessing.
%
%   DELIBERATELY NOT A SCREEN, and not inside +engine/runJudge.m or
%   +track/discriminator.m. Those produce the real/decoy LABEL, which has its
%   own documented weaknesses (the amplitude screen's short lever arm, screen
%   2b's measured inertness). Folding attribution into the label would make
%   any failure here impossible to attribute to one or the other. This reads
%   runJudge's exported measurements and nothing else.
%
%   NO TUNED CONSTANT. Tracks are grouped by comparing their angular rates
%   against the scatter of their OWN fits -- the same self-calibrating posture
%   as the co-bearing screen's spread-versus-scatter ratio, which adapts to
%   SNR, dwell length and geometry instead of being set to a number.

    n = double(feedback.confirmed_tracks);
    verdict = strings(1, n);
    diag = repmat(struct('omega_rad_s', NaN, 'sigma_omega_rad_s', NaN, ...
                         'implied_cross_speed_mps', NaN, 'mean_range_m', NaN, ...
                         'group', NaN, 'bearing_screen_score', NaN, ...
                         'reason', ""), 1, max(n, 1));
    if n == 0
        verdict = strings(1, 0); diag = diag([]);
        return
    end

    % ---- per track: the angular rate, and how well that rate is known ------
    omega = nan(1, n); sigOmega = nan(1, n); meanR = nan(1, n); cross = nan(1, n);
    for i = 1:n
        az = double(feedback.track_azimuth_rad{i}(:));
        t  = double(feedback.track_time_s{i}(:));
        R  = double(feedback.track_range_m{i}(:));
        ok = isfinite(az) & isfinite(t) & isfinite(R);
        meanR(i) = mean(R(ok));
        % 3 points minimum: a 2-parameter fit through 2 points has no
        % residual, so sigma_omega would be 0 and the grouping test below
        % would become infinitely strict.
        if nnz(ok) < 3 || (max(t(ok)) - min(t(ok))) <= 0; continue; end
        [omega(i), sigOmega(i)] = localSlopeAndSigma(t(ok), az(ok));
        cross(i) = omega(i) * meanR(i);
    end

    % ---- group tracks that share an angular rate --------------------------
    % Single-link agglomeration on |omega_i - omega_j| <= 2*sqrt(s_i^2+s_j^2):
    % two rates are "the same" when they differ by no more than the combined
    % uncertainty of the two fits that produced them. 2 sigma on a difference
    % of two independent estimates, not a threshold chosen for an outcome.
    group = nan(1, n);
    g = 0;
    for i = 1:n
        if ~isfinite(omega(i)) || ~isnan(group(i)); continue; end
        g = g + 1; group(i) = g;
        grew = true;
        while grew
            grew = false;
            members = find(group == g);
            for j = 1:n
                if ~isfinite(omega(j)) || ~isnan(group(j)); continue; end
                for mIdx = members
                    tol = 2 * sqrt(sigOmega(mIdx)^2 + sigOmega(j)^2);
                    if abs(omega(mIdx) - omega(j)) <= tol
                        group(j) = g; grew = true; break
                    end
                end
            end
        end
    end

    % ---- the verdicts -----------------------------------------------------
    for i = 1:n
        diag(i).omega_rad_s = omega(i);
        diag(i).sigma_omega_rad_s = sigOmega(i);
        diag(i).implied_cross_speed_mps = cross(i);
        diag(i).mean_range_m = meanR(i);
        diag(i).group = group(i);
    end

    for gi = 1:g
        members = find(group == gi);
        if numel(members) >= 2
            % Causality: only the nearest member can be the source.
            [~, iNear] = min(meanR(members));
            src = members(iNear);
            for m = members
                if m == src
                    verdict(m) = "source-or-real";
                    diag(m).reason = sprintf(...
                        ['nearest of %d tracks sharing omega=%.4f mrad/s; ' ...
                         'causality makes it the only possible source, and a ' ...
                         'source''s own omega is its real motion'], ...
                        numel(members), omega(m)*1e3);
                else
                    verdict(m) = "radiated-fake";
                    diag(m).reason = sprintf(...
                        ['shares omega=%.4f mrad/s with a track at %.0f m, ' ...
                         'nearer than its own %.0f m: its %.2f m/s implied ' ...
                         'cross speed is that aperture''s motion scaled by ' ...
                         '%.2fx'], omega(m)*1e3, meanR(src), meanR(m), ...
                        cross(m), meanR(m)/meanR(src));
                end
            end
        else
            % Alone in its rate: fall back to the per-track screen.
            m = members;
            s = track.bearingRateScreen(feedback.track_azimuth_rad{m}, ...
                    feedback.track_range_m{m}, feedback.track_time_s{m});
            diag(m).bearing_screen_score = s;
            if isnan(s)
                verdict(m) = "undetermined";
                diag(m).reason = ['alone in its angular rate, and screen 2c ' ...
                                  'abstained (bearing or range did not move ' ...
                                  'enough to judge)'];
            elseif s < 0.25
                verdict(m) = "radiated-fake";
                diag(m).reason = sprintf(['alone in its angular rate; screen ' ...
                    '2c scores %.3f -- its bearing follows time, not its own ' ...
                    'range curvature'], s);
            elseif s > 0.75
                verdict(m) = "source-or-real";
                diag(m).reason = sprintf(['alone in its angular rate; screen ' ...
                    '2c scores %.3f -- bearing and range are mutually ' ...
                    'consistent with straight-line motion'], s);
            else
                % THE BUCKET THAT MATTERS. 0.25-0.75 is where the two models
                % fit comparably well, which at long range is where an honest
                % screen 2c always lands. Reported, never rounded to a side.
                verdict(m) = "undetermined";
                diag(m).reason = sprintf(['alone in its angular rate; screen ' ...
                    '2c scores %.3f, too close to 0.5 to separate the two ' ...
                    'models'], s);
            end
        end
    end

    % Tracks with no usable bearing at all (no angle channel, or too few hits)
    % never entered a group. They are not suspicious, they are unmeasured.
    for i = 1:n
        if strlength(verdict(i)) == 0
            verdict(i) = "undetermined";
            diag(i).reason = ['no usable azimuth series: this receiver had no ' ...
                              'difference channel, or the track held too few hits'];
        end
    end
end


function [slope, sigmaSlope] = localSlopeAndSigma(x, y)
%LOCALSLOPEANDSIGMA  First-order LS slope and its standard error.
%   sigma_slope = sigma_resid / sqrt(sum((x - xbar).^2)), the textbook result.
%   It is what makes the grouping self-calibrating: a short dwell or a noisy
%   bearing widens the tolerance automatically, so the test never claims more
%   resolution than the measurement has.
    x = x(:); y = y(:); K = numel(x);
    p = polyfit(x, y, 1);
    slope = p(1);
    resid = y - polyval(p, x);
    sxx = sum((x - mean(x)).^2);
    if K <= 2 || sxx <= 0
        sigmaSlope = Inf;    % undetermined: force any comparison to be lenient
        return
    end
    sigmaSlope = sqrt(sum(resid.^2) / (K - 2) / sxx);
end
