function [rdMap, rangeAxis, dopAxis] = rangeDoppler(rxCube, wav, C)
%RANGEDOPPLER  Coherent slow-time (Doppler) integration over a range-pulse cube.
%
%   [rdMap, rangeAxis, dopAxis] = radar.rangeDoppler(RXCUBE, WAV, C)
%       rxCube    : [fastTime x numPulses] complex. Each column is one
%                   pulse's fast-time samples (already range-compressed by
%                   radar.pulseCompress -- Stage 1's job); columns are
%                   stacked across slow time (pulse-to-pulse).
%       wav       : transmit waveform (phased.* object); only its PRF is
%                   read, to scale the Doppler axis to Hz.
%       C         : physics.Constants(); only C.range_per_sample is read,
%                   to scale fast-time rows to metres.
%
%       rdMap     : [fastTime x numPulses] real, non-negative power map
%                   (rows = range, cols = Doppler)
%       rangeAxis : [fastTime x 1] metres
%       dopAxis   : [numPulses x 1] Hz, zero-centred
%
%   INDEPENDENT radar block (CLAUDE.md Rule 2). Ref: POA Part 4 Stage 2.
%
%   ponytail: rangeDoppler does not re-run fast-time matched filtering --
%   that already happened in radar.pulseCompress per pulse. Re-applying it
%   here on a synthetic single-cell target would smear it across the
%   matched-filter length instead of leaving it on its true range cell.
%   Revisit if a caller ever hands rangeDoppler truly raw (uncompressed)
%   fast-time ADC samples.

    [fastTime, numPulses] = size(rxCube);

    Y = fftshift(fft(rxCube, numPulses, 2), 2);
    rdMap = abs(Y).^2;

    rangeAxis = (0:fastTime-1)' * C.range_per_sample;

    k = (0:numPulses-1)' - floor(numPulses/2);
    dopAxis = (k / numPulses) * wav.PRF;
end
