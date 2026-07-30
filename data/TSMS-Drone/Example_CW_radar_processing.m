clear all;
clc;
close all;

%% Load Raw file (.mat)

% Identify the current script file path
currentFilePath = mfilename('fullpath');
[currentFolder, ~, ~] = fileparts(currentFilePath);

% Define the path to the Dataset folder relative to the current script
datasetRoot = fullfile(currentFolder, '..', '..', 'Dataset');

% Set parameters
distance = 2;              % Measurement distance (e.g., 2, 4, ..., 30 meters)
Model = "Inspire 2";       % Target name (e.g., Inspire 2, Mavic 2 Pro, Phantom 4 Pro, Matrice 30, Corner Reflector)
File_index = 1;            % Repetition index (e.g., 1 to 500)

% Compose the file name (e.g., Inspire 2_4m_002.mat)
filename = sprintf('%s_%dm_%03d.mat', Model, distance, File_index);

% Construct the full path to the target .mat file
filepath = fullfile(datasetRoot, 'CW Radar', sprintf('%dm', distance), Model, 'Raw File', filename);

% Load the dataset
load(filepath);


%% Signal Processing (CW Radar)
% Step 1: Down-sample the received signal
% 'rawSignal' is the complex I/Q vector loaded from .mat file
rawSignal = data;  % 'data' is the variable loaded from the .mat file
downsampledSignal = resample(rawSignal, 1, 16, 20);  % Downsample by a factor of 16 with filter order 20

% Step 2: Apply FFT to transform into frequency domain
fftResult = fft(downsampledSignal(:,1));           % 1D FFT on the first column (I/Q signal)
fftShifted = fftshift(fftResult);                  % Shift zero-frequency component to the center
magnitudeSpectrum = abs(fftShifted);               % Take magnitude of FFT result

% Step 3: Define frequency axis
samplingRate = 4096;                               % Final sampling rate after downsampling (Hz)
fftFrameSize = 1024;                               % Number of points used in FFT
frequencyResolution = samplingRate / fftFrameSize; % Frequency bin spacing (Hz)
frequencyAxis = -samplingRate/2 : frequencyResolution : samplingRate/2 - frequencyResolution;

%% --- Post-processing the magnitude spectrum ---

% Prevent very small values (for better log scale plotting)
magnitudeSpectrum(magnitudeSpectrum < 0.2) = 0.2;

% Amplify mid-range values (enhance contrast for detection)
magnitudeSpectrum(magnitudeSpectrum > 0.3) = magnitudeSpectrum(magnitudeSpectrum > 0.3) * 2;

% Limit extreme outliers
magnitudeSpectrum(magnitudeSpectrum > 100) = 10;

% Remove strong DC spike (center frequency component)
meanVal = mean(magnitudeSpectrum);                     % Compute average magnitude
maxIdx = find(magnitudeSpectrum == 10);                % Find index of saturated peak (DC)
dcIndices = maxIdx - 7 : maxIdx + 7;                   % Select ±7 points around the DC
dcIndices = dcIndices(dcIndices >= 1 & dcIndices <= length(magnitudeSpectrum)); % Boundary check
magnitudeSpectrum(dcIndices) = meanVal;                % Replace DC region with average

%% --- Visualization (plot generation) ---

% Create invisible figure for saving or further use
fig = figure('Visible','on');

% Plot using logarithmic scale (semilog-y)
semilogy(frequencyAxis, magnitudeSpectrum, 'k', 'LineWidth', 2);

% Set axis range
xlim([512 1536]);       % Frequency range
ylim([0.1 60]);         % Magnitude range in log scale

% Customize axis appearance (hide ticks and labels)
ax = gca;
set(ax, 'xtick', [], 'ytick', []);
set(ax, 'XColor', 'none', 'YColor', 'none');
set(ax, 'Color', 'w');
ax.Units = 'pixels';    % Set axis unit in pixels for consistent figure export

