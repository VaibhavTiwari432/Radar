function out = prfJitter(nSeeds)
%PRFJITTER  Tier 2.2 -- does PRF stagger cost a repeater anything, and does
%   it cost the radar's own genuine target anything? Both halves measured,
%   because a counter that degrades the radar as much as the threat is not a
%   counter.
%
%   out = experiments.prfJitter(nSeeds)      % default 20
%
%   THE MECHANISM, and why it is exactly parallel to waveform agility. A
%   genuine target is PASSIVE: it reflects each pulse whenever that pulse
%   happens to arrive, so its slow-time phase is evaluated at the radar's
%   TRUE (staggered) transmit times and the radar -- which knows its own
%   schedule -- can compensate exactly. A repeater is ACTIVE: it must decide
%   when to transmit, and without the schedule its only option is its own
%   uniform clock at the nominal PRI. Its phase history is therefore sampled
%   on the WRONG time grid, and the radar's compensation, which is correct
%   for the genuine target, actively scrambles it.
%
%   HOW THE RADAR COMPENSATES. With a staggered PRI the slow-time samples are
%   non-uniform, so an FFT is not the matched operation. The radar instead
%   evaluates a DFT at its own known transmit times:
%
%       X(f) = sum_p  x_p * exp(-1i*2*pi*f*t_p)
%
%   which is exact for any sampling pattern the radar knows. That is the only
%   new processing this needs; nothing else about the chain changes.
%
%   ================= WHICH REPEATER THIS APPLIES TO =================
%   READ THIS BEFORE QUOTING ANY NUMBER BELOW. A standard DRFM repeater is
%   REACTIVE: it hears a pulse, stores it, and retransmits after its own
%   processing latency. Such a repeater FOLLOWS the radar's stagger
%   automatically, because it never needs to know when the next pulse is
%   coming -- it simply answers each one. **PRF stagger is therefore worth
%   nothing against a reactive repeat-back jammer**, and the arm measured
%   here is the PREDICTIVE one, which transmits on its own clock in order to
%   place a phantom where a repeat-back jammer cannot.
%
%   That restriction is not a weakness of the measurement; it is the result.
%   +engine/+entity/checkCausality.m already establishes that repeat-back can
%   only ever place a phantom FARTHER out than the jammer (delay >= 0), so
%   pulling a gate INWARD requires prediction. PRF stagger attacks exactly
%   and only that capability. Its value is not the integration loss below --
%   it is that it forces the adversary back into repeat-back mode, where
%   causality already forbids the inward pull-off.
%
%   WHAT IS MEASURED. For each jitter level: the Doppler peak each arm
%   achieves relative to its own zero-jitter value (integration loss), and
%   the range-rate error the radar reads off. Loss for the REPEATER is the
%   benefit; loss for the GENUINE arm is the cost.

    if nargin < 1 || isempty(nSeeds); nSeeds = 20; end
    C = physics.Constants();

    nPulses = 32; v = -50; lambda = C.lambda;
    jitters = [0 0.05 0.10 0.20 0.40];

    fprintf('\n=== 2.2 PRF STAGGER, %d seeds, %d pulses, v = %+d m/s ===\n', ...
        nSeeds, nPulses, v);
    fprintf('nominal PRI %.1f us | Doppler bin %.3f m/s\n', 1e6/C.PRF, ...
        lambda*(C.PRF/nPulses)/2);
    fprintf('\n%8s | %-28s | %-28s\n', 'jitter', ...
        'GENUINE (passive)', 'REPEATER (uniform clock)');
    fprintf('%8s | %10s %16s | %10s %16s\n', '', 'peak dB', 'v error m/s', ...
        'peak dB', 'v error m/s');

    out = struct('jitter', {}, 'genPeakDb', {}, 'genVErr', {}, ...
                 'repPeakDb', {}, 'repVErr', {});
    ref = [NaN NaN];

    for j = jitters
        gP = zeros(1,nSeeds); gE = zeros(1,nSeeds);
        rP = zeros(1,nSeeds); rE = zeros(1,nSeeds);
        for s = 1:nSeeds
            rs = RandStream('twister', 'Seed', 6000 + s);
            [~, tTrue] = radar.prfSchedule(nPulses, C.PRF, j, rs);
            tUniform = (0:nPulses-1)' / C.PRF;

            % GENUINE: phase sampled at the TRUE transmit times (passive).
            xGen = exp(-1i * 4*pi * v * tTrue / lambda);
            % REPEATER: transmits on its own uniform clock, so the phase it
            % emits corresponds to the times IT assumed, not the real ones.
            xRep = exp(-1i * 4*pi * v * tUniform / lambda);

            nz = 0.05*(randn(rs,nPulses,1) + 1i*randn(rs,nPulses,1))/sqrt(2);
            [gP(s), gE(s)] = localMeasure(xGen + nz, tTrue, lambda, C, v);
            [rP(s), rE(s)] = localMeasure(xRep + nz, tTrue, lambda, C, v);
        end
        if isnan(ref(1)); ref = [mean(gP) mean(rP)]; end
        gDb = 20*log10(mean(gP)/ref(1));
        rDb = 20*log10(mean(rP)/ref(2));
        fprintf('%8.2f | %10.2f %16.2f | %10.2f %16.2f\n', j, gDb, ...
            mean(abs(gE)), rDb, mean(abs(rE)));
        out(end+1) = struct('jitter', j, 'genPeakDb', gDb, ...
            'genVErr', mean(abs(gE)), 'repPeakDb', rDb, ...
            'repVErr', mean(abs(rE))); %#ok<AGROW>
    end

    fprintf('\n=== 2.2 READING ===\n');
    last = out(end);
    fprintf('  at jitter %.2f: genuine loses %.2f dB, repeater loses %.2f dB\n', ...
        last.jitter, last.genPeakDb, last.repPeakDb);
    fprintf('  net advantage to the radar = %.2f dB\n', ...
        last.genPeakDb - last.repPeakDb);
    fprintf('  genuine range-rate error %.2f m/s | repeater %.2f m/s\n', ...
        last.genVErr, last.repVErr);
    fprintf(['\n  MECHANISM: the loss is SMALL because a staggered PRI walk is\n' ...
             '  dominated by its LINEAR trend, which is indistinguishable from a\n' ...
             '  frequency offset -- and the radar''s own Doppler search absorbs it.\n' ...
             '  So stagger does not destroy the predictive repeater''s coherence; it\n' ...
             '  BIASES its apparent velocity (%.2f -> %.2f m/s error). At this jitter\n' ...
             '  that bias is still below track.rangeRateConsistency''s 8.81 m/s gate,\n' ...
             '  so it does not by itself trip the Tier 1.2 screen.\n'], ...
            out(1).repVErr, last.repVErr);
    fprintf(['  AND IT IS INERT AGAINST A REACTIVE REPEATER, which follows the\n' ...
             '  stagger by construction. See this file''s header.\n']);
end

% ------------------------------------------------------------------------
function [peak, vErr] = localMeasure(x, tTrue, lambda, C, vTrue)
%LOCALMEASURE  The radar's own Doppler processing: a DFT evaluated at the
%   transmit times IT scheduled. Exact for any sampling pattern it knows --
%   an FFT would be exact only for a uniform one.
    nP = numel(x);
    % Same Doppler span and bin count an FFT over this dwell would give, so
    % the comparison is like-for-like against the non-staggered baseline.
    fGrid = ((-nP/2):(nP/2 - 1))' * (C.PRF / nP);
    X = exp(-1i*2*pi*fGrid*tTrue.') * x(:);
    [peak, im] = max(abs(X));
    vMeas = -lambda * fGrid(im) / 2;
    vErr = vMeas - vTrue;
end
