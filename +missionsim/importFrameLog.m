function frameLog = importFrameLog(filepath)
%IMPORTFRAMELOG  Step 10's re-import half: reads back a JSON file written
%   by missionsim.exportFrameLog into the SAME {1 x numFrames} cell-of-
%   structs shape missionsim.buildFrameLog produces, so a re-imported log
%   is a drop-in replacement anywhere the original was used (e.g.
%   app.loadFrame(frameLog{k})).
%
%   frameLog = missionsim.importFrameLog(filepath)
%
%   Every frame is re-validated on the way back in too -- a round trip
%   through JSON must not silently drop a provenance tag.
    raw = fileread(filepath);
    decoded = jsondecode(raw);   % a JSON array of objects -> a MATLAB struct ARRAY

    n = numel(decoded);
    frameLog = cell(1, n);
    for k = 1:n
        [valid, errors] = missionsim.validateFrame(decoded(k));
        if ~valid
            error('missionsim:importFrameLog:invalidFrame', ...
                'Imported frame %d fails schema validation:\n%s', k, strjoin(errors, sprintf('\n')));
        end
        frameLog{k} = decoded(k);
    end
end
