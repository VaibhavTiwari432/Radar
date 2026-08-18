function evasionRouteCompare(seeds, NF, Rp0)
%EVASIONROUTECOMPARE  Which of the two escapes from screen 2c actually pays?
%
%   +experiments/bearingHeadroom.m found two, and the re-derived scripted
%   baseline has to prefer the right one or it is not the honest bar Gate C
%   requires:
%
%     MATCHED   close fast and fly the platform on a proportional trajectory,
%               so 2c is ACTIVE and scores near 1.0 -- which also RESCUES a
%               mediocre amplitude score, since the label is the mean.
%     ABSTAIN   close slowly, so the phantom's range span falls under
%               bearingRateScreen's 3-range-cell guard, 1/R is constant and
%               2c cannot judge at all. Free of the bearing constraint, but
%               it forfeits that rescue AND shortens the lever arm the
%               amplitude screen's log-log slope fit depends on -- which
%               CLAUDE.md already records as that screen's documented
%               weakness.
%
%   Judged under the environment's own screen set {amplitude, bearing}
%   (generator/decision/env.py ECCM_SCREENS), because that is the radar the
%   agent is actually training against.

    if nargin < 1 || isempty(seeds); seeds = 1:8; end
    if nargin < 2 || isempty(NF); NF = 8; end
    if nargin < 3 || isempty(Rp0); Rp0 = 2300; end
    Rm0 = 900; cross = 3; t = 0:NF-1;
    masks = {'amplitude', 'bearing'};

    routes = struct( ...
        'name',  {'matched  (-50, Rdot_m=-20)', 'abstain  (-20, Rdot_m=-20)', ...
                   'abstain  (-20, Rdot_m=+20)', 'naive    (-50, Rdot_m=  0)'}, ...
        'rate',  {-50, -20, -20, -50}, ...
        'mrdot', {-20, -20,  20,   0});

    fprintf('\nphantom R0=2300, mother R0=%d cross=%g, screens {amplitude,bearing}\n\n', ...
            Rm0, cross);
    fprintf('%-28s %-10s %-12s %s\n', 'route', 'real/n', 'mean 2c', 'span [m]');
    for i = 1:numel(routes)
        Rm = Rm0 + routes(i).mrdot * t;
        az = atan2(cross * t, Rm);
        nR = 0; nC = 0; sc = [];
        for s = seeds
            rng(s, 'twister');
            mat = renderPhantomScene(Rp0, routes(i).rate, 'NumFrames', NF, ...
                'SourceAzimuthRad', az, 'MotherRangeM', min(Rm), ...
                'Tag', sprintf('evr_%d_%d', i, s));
            fb = engine.runJudge(mat, 'EccmScreens', masks);
            if fb.confirmed_tracks < 1; continue; end
            nC = nC + 1;
            nR = nR + double(fb.track_label{1} == "real");
            sc(end+1) = track.bearingRateScreen(fb.track_azimuth_rad{1}, ...
                            fb.track_range_m{1}, fb.track_time_s{1}); %#ok<AGROW>
        end
        fprintf('%-28s %d/%-8d %-12.3f %.0f\n', routes(i).name, nR, nC, ...
                mean(sc, 'omitnan'), abs(routes(i).rate) * (NF - 1));
    end
end
