%% Fusion Method 2: RGB Channel-Based Image Fusion
% -------------------------------------------------------------------------
% Purpose:
%   Generate a single fused RGB image by assigning each sensor modality
%   to one color channel:
%
%       R channel <- CW image
%       G channel <- FMCW image
%       B channel <- RF image
%
% Output:
%   - fused_img: 224 x 224 x 3 RGB image
%
% Notes:
%   - Input images may be RGB or grayscale.
%   - All inputs are resized to 224 x 224.
%   - This script processes ONE sample (no loops by design).
% -------------------------------------------------------------------------

clear; close all; clc;
disp('Fusion Method 2 (RGB Channel Fusion)');

%% Example input image paths (user-defined)
cw_path   = 'PUT_CW_IMAGE_PATH_HERE.png';
fmcw_path = 'PUT_FMCW_IMAGE_PATH_HERE.png';
rf_path   = 'PUT_RF_IMAGE_PATH_HERE.png';

%% Output path (optional)
out_path  = 'PUT_FUSED_IMAGE_OUTPUT_PATH_HERE.png';

%% Read images
cw_img   = imread(cw_path);
fmcw_img = imread(fmcw_path);
rf_img   = imread(rf_path);

%% Create fused image
fused_img = fuse_rgb_channels(cw_img, fmcw_img, rf_img);

%% Save and display (optional)
imwrite(fused_img, out_path);

figure;
imshow(fused_img);
title('Fused Image (CW → R, FMCW → G, RF → B)');

%% ------------------------------------------------------------------------
function fused_img = fuse_rgb_channels(cw_img, fmcw_img, rf_img)
% fuse_rgb_channels
%   Creates a fused RGB image by mapping each modality to one channel.

TARGET_SIZE = [224 224];

% ---- Convert to grayscale if needed ----
cw_gray   = to_grayscale(cw_img);
fmcw_gray = to_grayscale(fmcw_img);
rf_gray   = to_grayscale(rf_img);

% ---- Resize all inputs to 224 x 224 ----
cw_resized   = imresize(cw_gray,   TARGET_SIZE);
fmcw_resized = imresize(fmcw_gray, TARGET_SIZE);
rf_resized   = imresize(rf_gray,   TARGET_SIZE);

% ---- RGB channel fusion ----
% R <- CW, G <- FMCW, B <- RF
fused_img = cat(3, cw_resized, fmcw_resized, rf_resized);

end

function gray_img = to_grayscale(img)
% to_grayscale
%   Converts RGB image to grayscale if required.
if ndims(img) == 3
    gray_img = rgb2gray(img);
else
    gray_img = img;
end
end
