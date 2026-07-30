clear; close all;

%% --- User Parameters (Single Sample Version) ---
Model = "Matrice 30";     % Target name (e.g., Inspire 2, Mavic 2 Pro, Phantom 4 Pro, Matrice 30, Corner Reflector)
distance = 6;            % Measurement distance (e.g., 2, 4, ..., 30)
File_index = 120;          % File repetition index

%% --- File Path Setup (Same Format as FMCW) ---

% Locate current script path
currentFilePath = mfilename('fullpath');
[currentFolder, ~, ~] = fileparts(currentFilePath);
datasetRoot = fullfile(currentFolder, '..', '..', 'Dataset');

% Compose file path
filename = sprintf('%s_%dm_%03d.mat', Model, distance, File_index);
filepath = fullfile(datasetRoot, 'RF Receiver', sprintf('%dm', distance), Model, 'Raw File', filename);

% Check file existence
if ~isfile(filepath)
    error('File not found: %s', filepath);
end

% Load complex I/Q data from RF receiver
load(filepath);  % variable: data

%% --- Welch PSD Computation ---

%% --- Welch PSD Computation ---

% Parameters
fs = 4096;                    % Sampling rate (Hz)
windowLength = 256;
overlapLength = 120;
nfft = 1024;

% Compute power spectral density (baseband, centered)
[pxx, f_base] = pwelch(data, hanning(windowLength), overlapLength, nfft, fs, 'centered');
PdB_Hz = 10 * log10(pxx);

%% --- Frequency Axis Shift (Center = 2.4 GHz, BW = 60 MHz) ---

center_freq = 2.4e9;          % 2.4 GHz
bandwidth   = 60e6;           % 60 MHz
f = linspace(center_freq - bandwidth/2, center_freq + bandwidth/2, length(f_base));

%% --- Plotting the PSD ---
fig = figure('Visible', 'on');
plot(f/1e9, PdB_Hz, 'k', 'LineWidth', 2);   % GHz 단위로 표시
ylim([-100, -30]);                          
xlim([(center_freq-bandwidth/2)/1e9 (center_freq+bandwidth/2)/1e9]);  
xlabel('Frequency (GHz)');
ylabel('Power (dB/Hz)');
title(sprintf('RF PSD: %s at %dm', Model, distance));
grid on;
set(gca, 'FontSize', 12);



%% --- Optional: Save Image for CNN Training ---
% Uncomment to enable image export
% frame = getframe(gca);
% rf_img = imresize(frame.cdata, [227, 227]);
% save_dir = fullfile(datasetRoot, 'RF Receiver Images', Model, sprintf('%dm', distance));
% if ~exist(save_dir, 'dir')
%     mkdir(save_dir);
% end
% save_name = sprintf('%s_%dm_%03d.png', Model, distance, File_index);
% save_path = fullfile(save_dir, save_name);
% imwrite(rf_img, save_path);
% fprintf('Saved PSD image: %s\n', save_path);
