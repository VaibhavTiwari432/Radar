%% FMCW Raw IF Data -> Range-Doppler Map (Sample Reconstruction Code)
% -------------------------------------------------------------------------
% This script reconstructs a range-Doppler (RD) map from the provided sample
% raw FMCW IF dataset using a standard two-stage FFT processing chain.
%
% Expected variables inside 'FMCW_RawData.mat':
%   Data      : complex raw IF samples [Cfg.N*Cfg.FrmMeasSiz x NumRxChannels]
%   Cfg       : struct including N and FrmMeasSiz (and waveform parameters)
%   Win2D     : 2D window for range FFT (size: (Cfg.N-1) x Cfg.FrmMeasSiz)
%   ScaWin    : range-window scaling factor (sum of window coefficients)
%   WinVel2D  : Doppler window replicated across range bins (size: numRangeBins x Cfg.FrmMeasSiz)
%   ScaWinVel : Doppler-window scaling factor (sum of window coefficients)
%   RMinIdx, RMaxIdx : range bin indices for cropping
%   vRangeExt : range axis for cropped bins
%   vVel      : velocity axis
%
% Notes:
%   - RD magnitude is relative (not absolutely calibrated power/RCS).
%   - This script is provided as an illustrative example for reproducibility.
% -------------------------------------------------------------------------

clear; close all; clc;

%% 1) User settings
dataDir = fullfile(pwd, "Data");
matFile = fullfile(dataDir, "FMCW_RawData.mat");

ChnSel  = 1;     % Rx channel index (1-based)
NFFT    = 4096;  % FFT size used for both range and Doppler (change if needed)

%% 2) Load sample raw data + processing parameters
S = load(matFile);

% Basic checks (fail early with clear messages)
reqVars = ["Data","Cfg","Win2D","ScaWin","WinVel2D","ScaWinVel","RMinIdx","RMaxIdx","vRangeExt","vVel"];
for k = 1:numel(reqVars)
    assert(isfield(S, reqVars(k)), "Missing variable '%s' in the MAT file.", reqVars(k));
end

Data      = S.Data;
Cfg       = S.Cfg;
Win2D     = S.Win2D;
ScaWin    = S.ScaWin;
WinVel2D  = S.WinVel2D;
ScaWinVel = S.ScaWinVel;
RMinIdx   = S.RMinIdx;
RMaxIdx   = S.RMaxIdx;
vRangeExt = S.vRangeExt;
vVel      = S.vVel;

assert(ChnSel >= 1 && ChnSel <= size(Data,2), "ChnSel is out of range.");

%% 3) Reshape: [fast-time x slow-time]
x = Data(:, ChnSel);
assert(numel(x) >= Cfg.N*Cfg.FrmMeasSiz, "Not enough samples for reshape.");
MeasChn = reshape(x(1:Cfg.N*Cfg.FrmMeasSiz), Cfg.N, Cfg.FrmMeasSiz);

%% 4) 1st FFT: Range FFT (fast-time)
RP   = fft(MeasChn(2:end, :) .* Win2D, NFFT, 1) / ScaWin;
RPExt = RP(RMinIdx:RMaxIdx, :);

%% 5) 2nd FFT: Doppler FFT (slow-time) + centering
RD = fft(RPExt .* WinVel2D, NFFT, 2) / ScaWinVel;
RD = fftshift(RD, 2);
RD_dB = 20*log10(abs(RD) + eps);

%% 6) Visualization
figure('Name', 'Reconstructed Range-Doppler Map', 'Color', 'w');
imagesc(vVel, vRangeExt, RD_dB);
axis xy;
colormap('jet'); colorbar;
xlabel('Velocity [m/s]');
ylabel('Range [m]');
clim([-20 10]);
title('Range-Doppler Map (Reconstructed from Sample Raw Data)');


