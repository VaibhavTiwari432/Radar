function exportFrameLog(frameLog, filepath)
%EXPORTFRAMELOG  Step 10: "A full run exports valid JSON; re-importing
%   reproduces identical panel state." Writes frameLog (a {1 x numFrames}
%   cell of missionsim.validateFrame-valid structs, e.g.
%   missionsim.buildFrameLog's own output) as a JSON array to filepath.
%
%   missionsim.exportFrameLog(frameLog, filepath)
%
%   Every frame is re-validated here, not just trusted from its origin --
%   an export that silently wrote an invalid frame would defeat the whole
%   point of Section 6's provenance gate.
    for k = 1:numel(frameLog)
        [valid, errors] = missionsim.validateFrame(frameLog{k});
        if ~valid
            error('missionsim:exportFrameLog:invalidFrame', ...
                'Refusing to export: frame %d fails schema validation:\n%s', ...
                k, strjoin(errors, sprintf('\n')));
        end
    end

    % jsonencode on a cell array produces a JSON array of objects (one per
    % frame) -- exactly the shape missionsim.importFrameLog expects back.
    json = jsonencode(frameLog);
    fid = fopen(filepath, 'w');
    if fid < 0
        error('missionsim:exportFrameLog:cannotOpen', 'Could not open "%s" for writing.', filepath);
    end
    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, json, 'char');
end
