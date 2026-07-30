%% Fusion Method 1: Crop Fusion (CW + FMCW + RF -> 224x224)
% -------------------------------------------------------------------------
% Purpose:
%   Generate a single fused image by vertically crop three sensor images.
%
% Fusion Rule (fixed):
%   1) Resize each sensor image to match a 224x224 final output
%      - CW   ->  75 x 224
%      - FMCW ->  74 x 224
%      - RF   ->  75 x 224
%   2) Stack vertically in the following order:
%      [CW; FMCW; RF] -> 224 x 224
%
% Input:
%   - cw_img   : CW micro-Doppler (or processed CW image)
%   - fmcw_img : FMCW range-Doppler (or processed FMCW image)
%   - rf_img   : RF spectrum/PSD (or processed RF image)
%
% Output:
%   - fused_img: fused 224x224 image (same channel format as inputs)
%
% Notes:
%   - Inputs can be RGB or grayscale. If grayscale, they will be converted to RGB.
%   - This function does NOT loop over distances or indices; it processes one triplet.
% -------------------------------------------------------------------------

clear; close all; clc;

%% Example usage (one sample)
% Replace these with your own image file paths.
cw_path   = 'PUT_CW_IMAGE_PATH_HERE.png';
fmcw_path = 'PUT_FMCW_IMAGE_PATH_HERE.png';
rf_path   = 'PUT_RF_IMAGE_PATH_HERE.png';

% Output path (optional)
out_path  = 'PUT_FUSION_OUTPUT_PATH_HERE.png';

% Read images
cw_img   = imread(cw_path);
fmcw_img = imread(fmcw_path);
rf_img   = imread(rf_path);

% Create fused image
fused_img = fuse_vertical_stack(cw_img, fmcw_img, rf_img);

% Save (optional)
imwrite(fused_img, out_path);

% Display (optional)
figure; imshow(fused_img);
title('Fused Image (CW + FMCW + RF)');

%% ------------------------------------------------------------------------
function fused_img = fuse_vertical_stack(cw_img, fmcw_img, rf_img)
% fuse_vertical_stack
%   Creates a fused 224x224 image by resizing and vertical stacking.

% ---- Ensure 3-channel RGB (convert grayscale -> RGB) ----
cw_img   = ensure_rgb(cw_img);
fmcw_img = ensure_rgb(fmcw_img);
rf_img   = ensure_rgb(rf_img);

% ---- Resize (original algorithm sizes) ----
cw_resized   = imresize(cw_img,   [75 224]);
fmcw_resized = imresize(fmcw_img, [74 224]);
rf_resized   = imresize(rf_img,   [75 224]);

% ---- Vertical stacking: [CW; FMCW; RF] ----
fused_img = [cw_resized; fmcw_resized; rf_resized];

% Safety check (should be 224x224x3)
% assert(size(fused_img,1)==224 && size(fused_img,2)==224, 'Unexpected fused image size.');

end

function img_rgb = ensure_rgb(img)
% ensure_rgb
%   Converts grayscale image to RGB by channel replication.
if ndims(img) == 2
    img_rgb = repmat(img, [1 1 3]);
else
    img_rgb = img;
end
end
