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
distance = 12;              % Measurement distance (e.g., 2, 4, ..., 30 meters)
Model = "Inspire 2";       % Target name (e.g., Inspire 2, Mavic 2 Pro, Phantom 4 Pro, Matrice 30, Corner Reflector)
File_index = 1;            % Repetition index (e.g., 1 to 500)

% Compose the file name (e.g., Inspire 2_4m_002.mat)
filename = sprintf('%s_%dm_%03d.mat', Model, distance, File_index);

% Construct the full path to the target .mat file
filepath = fullfile(datasetRoot, 'FMCW Radar', sprintf('%dm', distance), Model, 'Raw File', filename);

% Load the dataset
load(filepath);


%% Signal Processing (FMCW Radar)
%% Set parameters
% Adjust threshold values as needed.
% If the micro-Doppler pattern is not clearly visible in the range-Doppler map,
% try lowering the lower threshold or increasing the upper threshold,
% especially for longer distances where signal strength may decrease.

threshold_low = 0.5;       % Please Set the threshold properly 
threshold_high = 3;


up_constant = 1.0;         % Range crop above (m)
down_constant = 1.0;       % Range crop below (m)

%% Generate velocity axis (vVel: -5 to 5 m/s, 4096 bins)
vVel = linspace(-5, 5, 4096);  % [m/s]

%% Generate range axis (vRangeExt) based on distance
% Generate range axis (vRangeExt) based on distance
rangeBins = size(RD,1);

if distance <= 10
    vRangeExt = linspace(0, 12, rangeBins);
elseif distance > 10 && distance <= 20
    vRangeExt = linspace(10, 22, rangeBins);
elseif distance > 20
    vRangeExt = linspace(20, 32, rangeBins);
else
    error('Unsupported distance: %d', distance);
end


%% Validate and process RD
assert(exist('RD', 'var') == 1, 'RD variable not found.');
assert(size(RD,1) == length(vRangeExt), 'Mismatch in RD and range axis.');
assert(size(RD,2) == length(vVel), 'Mismatch in RD and velocity axis.');

RD_mag = abs(RD) * 1e6;  % scale for visualization
RD_mag(RD_mag < threshold_low) = 0;
RD_mag(RD_mag > threshold_high) = threshold_high;

%% Crop around target distance
crop_idx = find((vRangeExt >= (distance - up_constant)) & (vRangeExt <= (distance + down_constant)));
RD_crop = RD_mag(crop_idx, :);
vRange_crop = vRangeExt(crop_idx);

%% Plot range-Doppler Map
fig = figure('Visible','on');
imagesc(vVel, vRange_crop, RD_crop);
xlabel('Velocity (m/s)');
ylabel('Range (m)');
title(sprintf('FMCW Range-Doppler Map (%s at %dm)', Model, distance));
colormap('jet');
clim([0 threshold_high]);
colorbar;
set(gca, 'YDir', 'normal');
set(gca, 'FontSize', 12);
axis tight;

%% Optional: Save image
% save_dir = fullfile(datasetRoot, 'FMCW Radar Images', Model, sprintf('%dm', distance));
% if ~exist(save_dir, 'dir')
%     mkdir(save_dir);
% end
% save_name = sprintf('%s_%dm_%03d.png', Model, distance, File_index);
% save_path = fullfile(save_dir, save_name);
% frame = getframe(gca);
% imwrite(frame.cdata, save_path);
