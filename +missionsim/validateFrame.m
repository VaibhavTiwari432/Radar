function [valid, errors] = validateFrame(frame)
%VALIDATEFRAME  Enforce the Mission Simulator frame schema's provenance
%   rule (MISSION_SIMULATOR_UI_SPEC.md Section 8/Section 6): any object
%   with a 'value' key MUST also have a 'provenance' key, wherever that
%   wrapped {value, unit, provenance} pattern appears in the frame, at any
%   nesting depth. "A number without provenance fails schema validation
%   and does not render" (Section 6) -- this function IS that gate.
%
%   [valid, errors] = missionsim.validateFrame(frame)
%       frame  : a decoded frame (struct/struct-array/cell, from
%                jsondecode) OR a raw JSON char/string -- either is
%                accepted, this function decodes strings itself.
%       valid  : true if no violations found anywhere in the frame.
%       errors : cellstr of JSONPath-style locations of each violation,
%                e.g. {'$.synth.phantoms[0].range: has "value" but no
%                "provenance"'} -- empty when valid.
%
%   Only checks the {value: ..., provenance: ...} wrapped-object pattern
%   itself; fields the spec's own Section 8 example leaves as plain,
%   unwrapped numbers (hits, misses, score, ageFrames, ...) are not
%   required to be wrapped -- this validates completeness of the pattern
%   where used, not "every number must be wrapped" (Section 8's own
%   example schema doesn't do that either).

    if ischar(frame) || isstring(frame)
        frame = jsondecode(char(frame));
    end
    errors = localWalk(frame, '$', {});
    valid = isempty(errors);
end

% ------------------------------------------------------------------------
function errors = localWalk(node, path, errors)
    if isstruct(node)
        if isscalar(node)
            fn = fieldnames(node);
            if ismember('value', fn) && ~ismember('provenance', fn)
                errors{end+1} = sprintf('%s: has "value" but no "provenance"', path); %#ok<AGROW>
            end
            for i = 1:numel(fn)
                errors = localWalk(node.(fn{i}), sprintf('%s.%s', path, fn{i}), errors);
            end
        else
            for i = 1:numel(node)
                errors = localWalk(node(i), sprintf('%s[%d]', path, i-1), errors);
            end
        end
    elseif iscell(node)
        for i = 1:numel(node)
            errors = localWalk(node{i}, sprintf('%s[%d]', path, i-1), errors);
        end
    end
    % numeric / char / string / logical / empty: base case, nothing to walk
end
