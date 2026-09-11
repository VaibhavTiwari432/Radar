function [verdict, diag] = skinBacktrack(feedback)
%SKINBACKTRACK  Tie each far track to a NEARER track that shares its bearing, frame by frame.
%
%   [verdict, diag] = track.skinBacktrack(feedback)
%
%   verdict : [1 x nTracks] string, one of
%       "backtracked"   a nearer track carries this track's bearing series,
%                       frame for frame -- this return was radiated from there
%       "emitter"       the nearer member of such a pair (and not itself
%                       backtracked further): the platform's own skin echo
%       "unpaired"      no nearer track shares its bearing
%       "undetermined"  fewer than 4 usable azimuths, or the track fails
%                       runJudge's NIS test (not one coherent object)
%   diag    : per track, partner index (0 = none) and the pair's two z-scores
%
%   THE PHYSICS. A repeater radiates from its own aperture, so each phantom's
%   bearing IS its drone's bearing at every frame. The drone is a real object
%   and reflects the radar's pulse, so if its skin echo confirms, the scene
%   holds a NEAR track and a FAR track whose azimuth series are one series
%   plus independent noise. Two independent aircraft share a bearing series
%   only when one flies exactly behind the other with the same angular rate.
%
%   WHY PAIRWISE. runJudge's co-bearing screen asks whether ALL tracks share
%   one bearing, which catches one drone's N phantoms and nothing else: a
%   swarm's pairs sit at N different bearings and the scene-wide spread is
%   wide. This asks it per (nearer, farther) pair instead.
%
%   THE TEST, NO TUNED CONSTANT. d_k = az_far(k) - az_near(k) over the frames
%   both tracks hold. Fit d = a + b*t; the pair is co-bearing when BOTH the
%   mean of d (= the fit at mean t) and the slope b sit within 3 standard
%   errors of zero, each SE taken from d's own residual scatter. The mean test
%   rejects a constant offset, the slope test a formation whose bearings cross
%   mid-dwell (zero mean, non-zero trend). 3 sigma, as CO_BEARING_SIGMAS.
%
%   CAUSALITY picks the direction: a repeater cannot plant a phantom in front
%   of itself, so only a track NEARER by more than one range cell can be the
%   emitter.
%
%   DELIBERATELY NOT IN THE LABEL, same posture as emitterAttribution: reads
%   runJudge's exports only, so its false alarms can be measured in isolation.

    SIGMAS = 3;
    MIN_COMMON = 4;     % the slope fit needs K-2 >= 2 residual dof
    n = double(feedback.confirmed_tracks);
    verdict = repmat("undetermined", 1, n);
    diag = repmat(struct('partner', 0, 'z_mean', NaN, 'z_slope', NaN), 1, n);
    if n == 0 || isempty(feedback.track_azimuth_rad); return; end

    az = feedback.track_azimuth_rad; t = feedback.track_time_s;
    meanR = cellfun(@(r) mean(r(isfinite(r))), feedback.track_range_m);
    usable = cellfun(@(a) nnz(isfinite(a)) >= MIN_COMMON, az);
    % ONE OBJECT PER TRACK. A weak echo can be stitched to a neighbour's hits
    % (measured: a 0.03 m^2 skin track hopping 4403 <-> 3138 m, NIS 184 vs
    % 0.1-0.3 for clean tracks). Its azimuths then alternate between two
    % bearings, the pair scatter explodes, and it "pairs" with everything --
    % 40/80 genuine far aircraft backtracked before this gate. The splice's
    % root cause (runJudge's ungated series rebuild) is fixed; this stays as
    % the defence for any other incoherent track. runJudge's own NIS column is
    % the coherence test; absent (synthetic input) = pass.
    if isfield(feedback, 'track_nis_pass')
        usable = usable & logical(feedback.track_nis_pass(:)');
    end
    verdict(usable) = "unpaired";
    cellM = physics.Constants().range_per_sample;

    for j = find(usable)
        best = Inf;
        for i = find(usable & meanR < meanR(j) - cellM)
            [zm, zs] = localPairZ(t{i}, az{i}, t{j}, az{j}, MIN_COMMON);
            % Most consistent partner wins when several nearer tracks qualify.
            if zm < SIGMAS && zs < SIGMAS && max(zm, zs) < best
                best = max(zm, zs);
                diag(j) = struct('partner', i, 'z_mean', zm, 'z_slope', zs);
            end
        end
    end

    partner = [diag.partner];
    verdict(partner > 0) = "backtracked";
    emitters = unique(partner(partner > 0));
    verdict(emitters(verdict(emitters) ~= "backtracked")) = "emitter";
end


function [zm, zs] = localPairZ(ti, ai, tj, aj, minCommon)
%LOCALPAIRZ  z-scores of the mean and slope of az_j - az_i over shared frames.
%   Inf when too few shared frames -- never pairs.
    zm = Inf; zs = Inf;
    [tc, ii, jj] = intersect(round(ti(:), 6), round(tj(:), 6));
    d = aj(jj) - ai(ii); d = d(:);
    ok = isfinite(d); tc = tc(ok); d = d(ok);
    K = numel(d);
    if K < minCommon; return; end
    tc = tc - mean(tc);
    sxx = sum(tc.^2);
    if sxx <= 0; return; end
    b = sum(tc .* (d - mean(d))) / sxx;
    resid = d - mean(d) - b * tc;
    % max(.., eps): identical series give s = 0, which is a pair, not a veto.
    s = max(sqrt(sum(resid.^2) / (K - 2)), eps);
    zm = abs(mean(d)) / (s / sqrt(K));
    zs = abs(b) / (s / sqrt(sxx));
end
