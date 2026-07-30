function D = loadRadChar(h5file, varargin)
%LOADRADCHAR  Load the RadChar radar-signal dataset from its HDF5 file.
%
%   D = data.loadRadChar(H5FILE) reads the RadChar '/iq' and '/labels'
%   datasets and returns a struct D with:
%       D.iq        - [512 x N] complex, one column per signal record
%       D.N         - number of signals actually loaded
%       D.signal_type              - [N x 1] int (0..4)
%       D.number_of_pulses         - [N x 1]
%       D.pulse_width              - [N x 1] seconds
%       D.time_delay               - [N x 1] seconds
%       D.pulse_repetition_interval- [N x 1] seconds
%       D.signal_to_noise_ratio    - [N x 1] dB
%       D.index                    - [N x 1]
%       D.signal_type_name         - {N x 1} cellstr (decoded)
%       D.file                     - source path
%
%   D = data.loadRadChar(H5FILE,'MaxSignals',K) loads only the first K
%   records (handy for a fast smoke test on RadChar-Tiny).
%
%   Verified schema (github.com/abcxyzi/RadChar):
%       /iq     : (N,512) complex baseband, fs = 3.2 MHz
%       /labels : structured array with fields
%                 index, signal_type, number_of_pulses, pulse_width,
%                 time_delay, pulse_repetition_interval, signal_to_noise_ratio
%       signal_type: 0 coherent pulse train | 1 Barker | 2 polyphase Barker
%                    | 3 Frank | 4 LFM ;  SNR in [-20, 20] dB.
%
%   NOTE ON COMPLEX STORAGE: h5py writes numpy-complex as an HDF5 *compound*
%   type with real/imag members. Depending on writer/reader versions MATLAB
%   returns either a native complex array or a struct with fields like r/i.
%   This loader handles both. It also fixes the row-major vs column-major
%   dimension flip so IQ always comes back as [512 x N].
%
%   This function lives in +data and is INDEPENDENT of +radar/+synth
%   (CLAUDE.md Rule 2). It only reads; it never judges a signal.

    p = inputParser;
    addParameter(p, 'MaxSignals', inf, @(x) isnumeric(x) && isscalar(x) && x>0);
    parse(p, varargin{:});
    maxN = p.Results.MaxSignals;

    if nargin < 1 || isempty(h5file)
        error('data:loadRadChar:noFile', ...
            ['Provide the path to a RadChar .h5 file, e.g.\n' ...
             '   D = data.loadRadChar(''data/RadChar-Tiny.h5'');\n' ...
             'See data/README.md for how to download it from Kaggle.']);
    end
    assert(isfile(h5file), 'data:loadRadChar:missing', ...
        'File not found: %s (see data/README.md to download RadChar).', h5file);

    % ---- IQ ----
    rawiq = h5read(h5file, '/iq');
    iq = localToComplex(rawiq);          % -> complex array, some orientation
    iq = localOrientTo512(iq);           % -> [512 x N]

    % ---- labels (HDF5 compound -> MATLAB struct of columns) ----
    L = h5read(h5file, '/labels');
    L = localNormalizeLabels(L);

    N = size(iq, 2);
    if isfield(L, 'signal_type'); N = min(N, numel(L.signal_type)); end
    N = min(N, maxN);

    D.file = h5file;
    D.iq   = iq(:, 1:N);
    D.N    = N;

    flds = {'index','signal_type','number_of_pulses','pulse_width', ...
            'time_delay','pulse_repetition_interval','signal_to_noise_ratio'};
    for i = 1:numel(flds)
        f = flds{i};
        if isfield(L, f)
            v = L.(f);
            D.(f) = v(1:min(N,numel(v)));
            D.(f) = D.(f)(:);            % column
        else
            warning('data:loadRadChar:missingField', ...
                'Label field "%s" not present in %s.', f, h5file);
            D.(f) = nan(N,1);
        end
    end

    % Decode signal-type names
    C = physics.Constants();
    nameMap = containers.Map(cell2mat(C.signal_types(:,1)), C.signal_types(:,2));
    D.signal_type_name = cell(N,1);
    for i = 1:N
        key = D.signal_type(i);
        if isKey(nameMap, key); D.signal_type_name{i} = nameMap(key);
        else;                   D.signal_type_name{i} = sprintf('unknown(%g)', key);
        end
    end
end

% ------------------------------------------------------------------------
function z = localToComplex(raw)
%LOCALTOCOMPLEX  Coerce h5read output into a complex array.
    if isnumeric(raw) && ~isreal(raw)
        z = double(raw);                 % already native complex
        return;
    end
    if isstruct(raw)
        fn = fieldnames(raw);
        reIdx = find(ismember(lower(fn), {'r','real','re'}), 1);
        imIdx = find(ismember(lower(fn), {'i','imag','im'}), 1);
        assert(~isempty(reIdx) && ~isempty(imIdx), ...
            'data:loadRadChar:badComplex', ...
            'Unrecognised complex compound fields: %s', strjoin(fn, ', '));
        z = double(raw.(fn{reIdx})) + 1i*double(raw.(fn{imIdx}));
        return;
    end
    % real numeric (unexpected for IQ, but pass through)
    z = double(raw);
end

% ------------------------------------------------------------------------
function z = localOrientTo512(z)
%LOCALORIENTTO512  Return IQ as [512 x N] regardless of incoming orientation.
    if ndims(z) > 2 %#ok<ISMAT>
        z = reshape(z, size(z,1), []);   % flatten any trailing singleton dims
    end
    [a, b] = size(z);
    if a == 512
        % already [512 x N]
    elseif b == 512
        z = z.';                         % non-conjugate transpose -> [512 x N]
    else
        warning('data:loadRadChar:oddShape', ...
            ['IQ array is %dx%d; expected a 512 dimension. Leaving as-is. ' ...
             'Check the dataset variant.'], a, b);
    end
end

% ------------------------------------------------------------------------
function L = localNormalizeLabels(L)
%LOCALNORMALIZELABELS  Make every label field a numeric column vector.
    if ~isstruct(L)
        error('data:loadRadChar:badLabels', ...
            '/labels did not decode to a struct (got %s).', class(L));
    end
    fn = fieldnames(L);
    for i = 1:numel(fn)
        v = L.(fn{i});
        if isinteger(v); v = double(v); end
        if isnumeric(v); L.(fn{i}) = v(:); end
    end
end
