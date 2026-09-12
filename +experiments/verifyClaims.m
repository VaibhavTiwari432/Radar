function V = verifyClaims(varargin)
%VERIFYCLAIMS  Re-test the 10-11 Sep 2026 swarm conclusions (F10-F15) [SIM].
%
%   V = experiments.verifyClaims('Name', value, ...)
%
%   T0 replays one published cell on its ORIGINAL seeds and must match
%   results/swarm/multi_swarm_thermal.log exactly (determinism). T1-T5 re-run
%   each headline on UNSEEN seeds (SeedOffset+1 .. SeedOffset+NumSeeds) and
%   check the CONCLUSION, not the digits. Every threshold below was fixed
%   before the run (12 Sep 2026). ~300 judge calls at the defaults.
%
%   'NumSeeds'   10
%   'SeedOffset' 20     the published runs used seeds 1-20
%
%   Returns V, a struct array (name, ok); prints PASS/FAIL per check.

    p = inputParser;
    p.addParameter('NumSeeds', 10);
    p.addParameter('SeedOffset', 20);
    p.parse(varargin{:});
    ns = p.Results.NumSeeds; off = p.Results.SeedOffset;
    held = {'NumSeeds', ns, 'SeedOffset', off};
    V = struct('name', {}, 'ok', {});

    % T0 -- determinism: the 1x4 rows of multi_swarm_thermal.log, seeds 1-20.
    try
        r = experiments.skinBacktrackCheck('N', 1, 'K', 4, 'PlatformRcs', 1, 'GapM', 2400, ...
            'NumSeeds', 20, 'Arms', ["swarm", "genuine"]);
        s = r(1); g = r(2);
        V(end+1) = chk('T0 replay 1x4 swarm == log: 80/80 backtracked to own, 0/80 real, cob 20/20, EA 80', ...
            s.k == 80 && s.toOwnDrone == 80 && s.farReal == 0 && s.cobFlagged == 1 && round(s.farFake * s.n) == 80);
        V(end+1) = chk('T0 replay 1x4 genuine == log: 0/80 backtracked, 80/80 real, cob 0/20, EA 3', ...
            g.k == 0 && g.farReal == 1 && g.cobFlagged == 0 && round(g.farFake * g.n) == 3);
    catch e
        V(end+1) = chk(['T0 crashed: ' e.message], false);
    end

    % T1 -- F10: one aperture's phantoms never survive; a spread swarm does.
    try
        r = experiments.swarmSweep('Ns', [2 8], 'SpreadsDeg', [0 2 7], held{:});
        for x = r
            if x.spreadDeg == 0
                V(end+1) = chk(sprintf('T1 F10 N=%d, one aperture: no phantom survives', x.N), ...
                    x.pAllReal == 0 && x.meanSurvivors == 0); %#ok<AGROW>
            else
                V(end+1) = chk(sprintf('T1 F10 N=%d, spread %g deg: swarm survives, P(all real) >= 0.8', ...
                    x.N, x.spreadDeg), x.pAllReal >= 0.8); %#ok<AGROW>
            end
        end
    catch e
        V(end+1) = chk(['T1 crashed: ' e.message], false);
    end

    % T2 -- F11: the second baseline cannot tell a moving swarm from a formation.
    try
        r = experiments.swarmEmitterCheck('N', 8, 'UseBaseline2', true, held{:});
        m = r(strcmp({r.mode}, 'moving')); g = r(strcmp({r.mode}, 'genuine'));
        V(end+1) = chk('T2 F11 label untouched: moving swarm and formation both 8/8 real', ...
            m.meanSurvivors == 8 && g.meanSurvivors == 8);
        V(end+1) = chk('T2 F11 no separation: |moving - genuine| radiated-fake <= 1.5, genuine >= 4/8', ...
            abs(m.meanRadiatedFake - g.meanRadiatedFake) <= 1.5 && g.meanRadiatedFake >= 4);
    catch e
        V(end+1) = chk(['T2 crashed: ' e.message], false);
    end

    % T3 -- F12: the skin backtrack catches a visible swarm and spares a formation.
    try
        r = experiments.skinBacktrackCheck('N', 4, 'PlatformRcs', [1 0.01], 'GapM', 2400, held{:});
        pick = @(arm, rcs) r(strcmp({r.arm}, arm) & [r.rcs] == rcs);
        s1 = pick('swarm', 1); g1 = pick('genuine', 1); t1 = pick('trailing', 1);
        s0 = pick('swarm', 0.01); g0 = pick('genuine', 0.01);
        V(end+1) = chk('T3 F12 1 m^2: swarm backtracked >= 0.9, every one to its OWN drone', ...
            s1.farBacktracked >= 0.9 && s1.toOwnDrone == s1.k);
        V(end+1) = chk('T3 F12 1 m^2: genuine formation <= 0.05, swarm CI clear of it', ...
            g1.farBacktracked <= 0.05 && s1.ciLow > g1.ciHigh);
        V(end+1) = chk('T3 F12 1 m^2: trailing formation is the hard case, 0.10-0.60', ...
            t1.farBacktracked >= 0.10 && t1.farBacktracked <= 0.60);
        V(end+1) = chk('T3 F12 0.01 m^2: far drone lost, catch 0.25-0.70, >= 0.2 above genuine', ...
            s0.skinByDrone(end) == 0 && s0.farBacktracked >= 0.25 && s0.farBacktracked <= 0.70 && ...
            s0.farBacktracked - g0.farBacktracked >= 0.2);
        V(end+1) = chk('T3 F12 D5: label untouched, every far object real in every arm', all([r.farReal] == 1));

        r = experiments.skinBacktrackCheck('N', 4, 'PlatformRcs', 3, 'Arms', "swarm", held{:});
        V(end+1) = chk('T3b F12 CFAR masking: at the default 1200 m gap drone 4 is never seen, even at 3 m^2', ...
            isequal(r.skinByDrone, [ns ns ns 0]));
    catch e
        V(end+1) = chk(['T3 crashed: ' e.message], false);
    end

    % T4 -- F14: a mother's speed matters only through whether the radar sees it.
    for env = ["clutter_mti", "thermal"]
        try
            T = experiments.motherSpeedSweep('SpeedMps', 20, 'HeadingDeg', [0 90], 'K', 1, 'Env', env, held{:});
            at = @(hd, arm) T(T.heading == hd & strcmp(T.arm, arm), :);
            if env == "clutter_mti"
                V(end+1) = chk('T4 F14 clutter+MTI, crossing 20 m/s: drone notched, lone phantom real >= 0.8', ...
                    at(90, 'swarm').farReal >= 0.8); %#ok<AGROW>
                V(end+1) = chk('T4 F14 clutter+MTI, closing 20 m/s: drone seen, phantom real <= 0.2', ...
                    at(0, 'swarm').farReal <= 0.2); %#ok<AGROW>
            else
                V(end+1) = chk('T4 F14 thermal: drone always seen, phantom real 0 at both headings', ...
                    at(0, 'swarm').farReal == 0 && at(90, 'swarm').farReal == 0); %#ok<AGROW>
                V(end+1) = chk('T4 F14 open defect: genuine formation crossing 20 m/s flagged >= 0.8, closing 0', ...
                    at(90, 'genuine').cobFlagged >= 0.8 && at(0, 'genuine').cobFlagged == 0); %#ok<AGROW>
            end
        catch e
            V(end+1) = chk(sprintf('T4 %s crashed: %s', env, e.message), false); %#ok<AGROW>
        end
    end

    % T5 -- F15: a second drone switches the co-bearing screen off for everyone.
    try
        r = experiments.skinBacktrackCheck('N', 2, 'K', 4, 'PlatformRcs', 1, 'GapM', 2400, ...
            'Arms', ["swarm", "genuine"], held{:});
        s = r(1); g = r(2);
        V(end+1) = chk('T5 F15 2x4: co-bearing never fires, phantoms 100% real', ...
            s.cobFlagged == 0 && s.farReal == 1);
        V(end+1) = chk('T5 F15 2x4: backtrack still ties phantoms >= 0.9, genuine <= 0.05', ...
            s.farBacktracked >= 0.9 && g.farBacktracked <= 0.05);
    catch e
        V(end+1) = chk(['T5 crashed: ' e.message], false);
    end

    fprintf('\n=== VERIFY CLAIMS [SIM]: %d/%d checks pass (unseen seeds %d-%d; T0 on 1-20) ===\n', ...
        nnz([V.ok]), numel(V), off + 1, off + ns);
    for v = V(~[V.ok]); fprintf('  FAIL: %s\n', v.name); end
end

function v = chk(name, ok)
    words = ["FAIL", "PASS"];
    fprintf('\n>>> %s  %s\n', words(ok + 1), name);
    v = struct('name', name, 'ok', ok);
end
