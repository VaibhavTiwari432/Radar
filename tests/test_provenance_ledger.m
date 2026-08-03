function tests = test_provenance_ledger
%TEST_PROVENANCE_LEDGER  Prove the untagged-quantity checker CAN fail before
%   any clean scan of it is believed.
%
%   The metric assurance.provenanceLedger reports ("untagged count = 0") is
%   worthless if the checker is structurally incapable of returning anything
%   else. So the planted-violation test comes first and the clean-scan test
%   second, deliberately in that order -- the same argument
%   web/scripts/verify-no-physics.mjs makes for its own self-test.
    tests = functiontests(localfunctions);
end

function test_planted_untagged_field_is_caught(tc)
    lg = localFakeLog();
    lg.somethingNobodyRegistered = 42;          % the planted violation
    L = assurance.provenanceLedger(lg);
    tc.verifyEqual(L.untaggedCount, 1, ...
        'the checker did not notice an unregistered field -- a clean scan proves nothing');
    tc.verifyEqual(L.untagged{1}, 'somethingNobodyRegistered');
    ix = find(strcmp({L.entries.name}, 'somethingNobodyRegistered'));
    tc.verifyEqual(L.entries(ix).tag, 'UNTAGGED');
end

function test_the_real_env_log_schema_is_fully_tagged(tc)
    % Now that the checker is known to fire, a zero here means something.
    L = assurance.provenanceLedger(localFakeLog());
    tc.verifyEqual(L.untaggedCount, 0, ...
        sprintf('unregistered observables: %s', strjoin(L.untagged, ', ')));
end

function test_every_entry_carries_a_derivation(tc)
    % Rule 1: a tag with no derivation beside it is a magic number wearing a
    % label. An empty derivation string is as bad as no tag.
    L = assurance.provenanceLedger(localFakeLog());
    for i = 1:numel(L.entries)
        tc.verifyNotEmpty(L.entries(i).derivation, ...
            sprintf('%s has a tag but no derivation', L.entries(i).name));
    end
end

function test_extra_assurance_fields_are_folded_in(tc)
    L = assurance.provenanceLedger(localFakeLog(), ...
            struct('inline_score', 0.83, 'judge_real', 0, 'conformal_uncertain', true));
    names = {L.entries.name};
    tc.verifyTrue(all(ismember({'inline_score','judge_real','conformal_uncertain'}, names)));
    tc.verifyEqual(L.untaggedCount, 0);
end

function test_the_cube_is_summarised_not_embedded(tc)
    % A ledger that embeds the received signal is a second copy of the data,
    % not an audit trail. 400x32x8 complex is ~1.6 MB per episode.
    lg = localFakeLog();
    lg.cubeFrames = complex(randn(400,32,8), randn(400,32,8));
    L = assurance.provenanceLedger(lg);
    ix = find(strcmp({L.entries.name}, 'cubeFrames'));
    tc.verifyLessThan(numel(L.entries(ix).summary), 100);
    tc.verifyTrue(contains(L.entries(ix).summary, '400'));
end

% ------------------------------------------------------------------------
function lg = localFakeLog()
%LOCALFAKELOG  agent.buildEnvEntity's `logged` schema, field for field.
%   Hand-built rather than produced by a rollout: this test is about the
%   SCHEMA being fully tagged, and an 8-frame render per assertion would
%   make a structural check cost a minute for nothing. tests that need real
%   values use experiments.ledgerAudit.
    lg = struct( ...
        'k', 8, 'range', 1650, 'dets', {{}}, 'times', 0:7, ...
        'rangeHist', 1800:-20:1660, 'ampHist', rand(1,8), 'rateHist', -60*ones(1,8), ...
        'detectedHist', true(1,8), 'confirmedCount', 1, ...
        'cmdVelHist', -60*ones(1,8), 'cmdRangeStep', -60, ...
        'eccmLabel', "real", 'phi', 0.7, 'rcsDbsm', -10, 'cubeFrames', []);
end
