function L = provenanceLedger(lg, extra)
%PROVENANCELEDGER  Per-episode audit trail: every observable the engine
%   produced, the provenance tag it carries, and the derivation behind it.
%
%   L = assurance.provenanceLedger(lg)
%   L = assurance.provenanceLedger(lg, extra)
%       lg    : the environment's episode log (agent.buildEnvEntity /
%               agent.buildEnvDoppler's fourth step() output)
%       extra : optional struct of assurance-layer quantities to fold in
%               (inline_score, judge_label, conformal set, ...)
%       L     : struct with .entries (name/tag/derivation/summary),
%               .untagged (cellstr) and .untaggedCount
%
%   WHY THIS IS A CHECK AND NOT A DECLARATION. A hand-written table of tags
%   is complete by construction and therefore measures nothing -- "untagged
%   count = 0" is only a real metric if a quantity CAN go untagged. So this
%   walks the log struct's ACTUAL fields at runtime and reports any field
%   with no registry entry. Add a field to buildEnvEntity's `logged` without
%   registering its provenance here and the count goes non-zero.
%
%   THE CHECKER IS ITSELF CHECKED. tests/test_provenance_ledger.m plants an
%   unregistered field and asserts this function catches it, before trusting
%   any clean scan -- the same discipline web/scripts/verify-no-physics.mjs
%   already applies to its own banned-token scan. A checker that has never
%   been seen to fail is indistinguishable from a checker that cannot.
%
%   TAGS, matching the report's own scheme:
%     MEASURED     read off the simulated receiver or a judge component
%     DERIVED      computed from other logged quantities by a stated relation
%     ASSUMED      chosen, not derived from data -- the honest weak spots
%     UNVALIDATED  present but never checked against anything
%
%   NOT A JUDGE-SIDE ARTEFACT (CLAUDE.md Rule 2). Everything here describes
%   what the ADVERSARY emitted and believed. The judge's verdict may be
%   folded in via `extra` as a recorded outcome, but nothing in this file
%   can influence it.

    if nargin < 2; extra = struct(); end

    reg = localRegistry();
    names = fieldnames(lg);
    entries = struct('name', {}, 'tag', {}, 'derivation', {}, 'summary', {});
    untagged = {};

    for i = 1:numel(names)
        n = names{i};
        if isfield(reg, n)
            entries(end+1) = struct('name', n, 'tag', reg.(n){1}, ...
                'derivation', reg.(n){2}, 'summary', localSummary(lg.(n))); %#ok<AGROW>
        else
            untagged{end+1} = n; %#ok<AGROW>
            entries(end+1) = struct('name', n, 'tag', 'UNTAGGED', ...
                'derivation', '(no provenance registered)', ...
                'summary', localSummary(lg.(n))); %#ok<AGROW>
        end
    end

    % Assurance-layer quantities, tagged the same way. These are DERIVED --
    % every one is a stated function of the log above and the judge's
    % recorded verdict, with no free parameters beyond alpha.
    ex = fieldnames(extra);
    for i = 1:numel(ex)
        entries(end+1) = struct('name', ex{i}, 'tag', 'DERIVED', ...
            'derivation', 'assurance layer: see +assurance/conformalFit.m', ...
            'summary', localSummary(extra.(ex{i}))); %#ok<AGROW>
    end

    L = struct('entries', entries, 'untagged', {untagged}, ...
               'untaggedCount', numel(untagged));
end

% ------------------------------------------------------------------------
function reg = localRegistry()
%LOCALREGISTRY  name -> {tag, derivation}. The derivations are the point;
%   a tag with no derivation next to it is the magic-number habit wearing a
%   label (CLAUDE.md Rule 1).
    reg = struct( ...
    'k',              {{'DERIVED',  'frame counter, 1..framesPerEpisode'}}, ...
    'range',          {{'DERIVED',  'entity true range: R + rangeRate*dt, clamped to [rangeMinM rangeMaxM]'}}, ...
    'rangeHist',      {{'MEASURED', 'CFAR peak bin -> (bin-1)*C.range_per_sample = c/(2*fs)'}}, ...
    'ampHist',        {{'MEASURED', 'sqrt of the pulse-compressed peak power at the detected bin'}}, ...
    'rateHist',       {{'MEASURED', 'slow-time Doppler bin -> -lambda*f_d/2 (radar.rangeDoppler)'}}, ...
    'detectedHist',   {{'MEASURED', 'CA-CFAR threshold crossing, radar.cfarDetect'}}, ...
    'dets',           {{'MEASURED', 'objectDetection built from the frame CFAR peaks'}}, ...
    'times',          {{'DERIVED',  'frame index * dt (frame_interval_s)'}}, ...
    'confirmedCount', {{'MEASURED', 'numel(track.runTracker(...)) -- trackerGNN M-of-N confirmation'}}, ...
    'cmdVelHist',     {{'DERIVED',  'action index -> spec.velOptionsMps lookup'}}, ...
    'cmdRangeStep',   {{'DERIVED',  'commanded range-rate * dt'}}, ...
    'eccmLabel',      {{'MEASURED', 'track.discriminator verdict on the measured range/amp/doppler series'}}, ...
    'phi',            {{'DERIVED',  'potential-based shaping term from the discriminator score'}}, ...
    'rcsDbsm',        {{'ASSUMED',  'chosen from spec.rcsOptionsDbsm -- an identity, not derived from measured RCS data'}}, ...
    'cubeFrames',     {{'MEASURED', 'the received [fastTime x pulses x frames] cube, entity render + thermal noise'}}, ...
    'rcsAmp',         {{'DERIVED',  'RCS dBsm -> linear amplitude, 10^(dBsm/20)'}} ...
    );
end

% ------------------------------------------------------------------------
function s = localSummary(v)
%LOCALSUMMARY  A short, loggable description. Never the full cube -- a
%   ledger that embeds the received signal is not an audit trail, it is a
%   second copy of the data.
    if isempty(v)
        s = 'empty';
    elseif ischar(v) || isstring(v)
        s = char(string(v));
    elseif iscell(v)
        s = sprintf('cell{%s}', mat2str(size(v)));
    elseif isnumeric(v) || islogical(v)
        f = v(isfinite(v));
        if isempty(f)
            s = sprintf('%s numeric, all non-finite', mat2str(size(v)));
        elseif numel(v) == 1
            s = sprintf('%.6g', double(v));
        else
            s = sprintf('%s numeric, [%.4g .. %.4g]', mat2str(size(v)), ...
                double(min(real(f(:)))), double(max(real(f(:)))));
        end
    else
        s = sprintf('%s', class(v));
    end
end
