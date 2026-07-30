%% TSMS-Drone (Example) CNN Training Script: GoogLeNet (MATLAB)
% -------------------------------------------------------------------------
% Purpose:
%   Train a GoogLeNet-based image classifier using dataset images exported
%   from radar/RF preprocessing (e.g., FMCW RD map images, CW MDS images, RF imgages, Fusion imagesetc.).
%
% Requirements:
%   - MATLAB Deep Learning Toolbox
%   - GoogLeNet support package (Deep Learning Toolbox Model for GoogLeNet)
%
% Dataset Folder Structure (REQUIRED):
%   The imageDatastore uses folder names as labels.
%   Please organize your dataset as:
%
%   <DATASET_ROOT>/
%       Class_1/   (e.g., Inspire2)
%           Inspire 2_001.png
%           Inspire 2_002.png
%           ...
%       Class_2/   (e.g., Mavic2Pro)
%           ...
%       Class_3/
%           ...
%       Class_4/
%           ...
%
% Notes:
%   - All classes should contain image files (png/jpg/bmp, etc.).
%   - You may place subfolders under each class folder; set IncludeSubfolders=true.
% -------------------------------------------------------------------------

clear; close all; clc;

%% (1) USER SETTINGS: Dataset path and experiment name
% Set your dataset root folder (see folder structure above)
DATASET_ROOT = 'PUT_YOUR_DATASET_PATH_HERE';

% Output model file name (.mat)
MODEL_NAME = 'GoogLeNet_5class_FMCW_example';

%% (2) USER SETTINGS: Data split ratio
% Train/Validation split ratio (per label)
% Example: 0.8 means 80% training, 20% validation
TRAIN_RATIO = 0.82;

%% (3) Load image dataset (labels from folder names)
fprintf('Loading image dataset...\n');

imds = imageDatastore(fullfile(DATASET_ROOT), ...
    'IncludeSubfolders', true, ...
    'LabelSource', 'foldernames');

% Check class distribution
labelCount = countEachLabel(imds);
disp(labelCount);

numClasses = height(labelCount);

%% (4) Split dataset into training/validation
% NOTE: splitEachLabel performs stratified splitting (per class).
[imdsTrainingSet, imdsValidationSet] = splitEachLabel(imds, TRAIN_RATIO);

fprintf('Training images: %d\n', numel(imdsTrainingSet.Files));
fprintf('Validation images: %d\n', numel(imdsValidationSet.Files));

%% (5) Define network: GoogLeNet (no pretrained weights)
% IMPORTANT:
%   - This script follows the original code logic: googlenet("Weights","none")
%   - If you want transfer learning, change to googlenet("Weights","imagenet")
net = googlenet("Weights","imagenet");
fprintf("Starting GoogLeNet training...\n");

%% (6) Input size and datastores
% GoogLeNet input is typically 224x224x3 (MATLAB uses 224 for GoogLeNet)
INPUT_LAYER_SIZE = [224 224];

Resized_Training_Image   = augmentedImageDatastore(INPUT_LAYER_SIZE, imdsTrainingSet);
Resized_Validation_Image = augmentedImageDatastore(INPUT_LAYER_SIZE, imdsValidationSet);

%% (7) Replace final layers for N-class classification
% The layer indices (142, 144) are consistent with the original script.
% Depending on MATLAB version, these indices may differ.
% If an error occurs, use analyzeNetwork(net) to locate the final FC and classification layers.

Feature_Learner   = net.Layers(142);
Output_Classifier = net.Layers(144);

New_Feature_Learner = fullyConnectedLayer(numClasses, ...
    'Name', 'Drone Feature Learner', ...
    'WeightLearnRateFactor', 10, ...
    'BiasLearnRateFactor', 10);

New_Classifier_Layer = classificationLayer('Name', 'Drone Classifier');

net = replaceLayer(net, Feature_Learner.Name, New_Feature_Learner);
net = replaceLayer(net, Output_Classifier.Name, New_Classifier_Layer);

%% (8) USER SETTINGS: Training hyperparameters
MINI_BATCH_SIZE     = 64;
MAX_EPOCHS          = 100;
INITIAL_LEARN_RATE  = 1e-3;

% Validation frequency (keep same logic as the original script)
Validation_Frequency = floor(numel(Resized_Training_Image.Files) / MINI_BATCH_SIZE);

options = trainingOptions('sgdm', ...
    'MiniBatchSize', MINI_BATCH_SIZE, ...
    'MaxEpochs', MAX_EPOCHS, ...
    'InitialLearnRate', INITIAL_LEARN_RATE, ...
    'Shuffle', 'every-epoch', ...
    'ValidationData', Resized_Validation_Image, ...
    'ValidationFrequency', Validation_Frequency, ...
    'Verbose', true);

%% (9) Train network
net_trained = trainNetwork(Resized_Training_Image, net, options);
fprintf("GoogLeNet training finished.\n");

%% (10) Save trained model
save(MODEL_NAME, 'net_trained');
fprintf("Saved trained network to: %s.mat\n", MODEL_NAME);

