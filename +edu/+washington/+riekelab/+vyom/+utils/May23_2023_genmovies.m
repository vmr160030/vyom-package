%%
stimulusIndices = [2 6 12 18 24 30 40 50];

pkgDir = '/Users/riekelabbackup/Desktop/Vyom/stim_packages/manookin-package/resources';
currentStimSet = 'dovesFEMstims20160826.mat';
im = load([pkgDir,'/',currentStimSet]);

%%
saveDir = '/Users/riekelabbackup/Desktop/Vyom/stim_packages/vyom-package/+edu/+washington/+riekelab/+vyom/+Doves/+PixBlurImages/';
blurSizes = [10 20 30 50 80 100];                  % Blur size (microns)
pixSizes = [10 20 30 50 80 100]; % Pixellation size (microns)

for idx_s=1:length(stimulusIndices)
stimulusIndex = stimulusIndices(idx_s);
imageName = im.FEMdata(stimulusIndex).ImageName;
            
% Load the image.
fileId = fopen([pkgDir,'/doves/images/', imageName],'rb','ieee-be');
img = fread(fileId, [1536 1024], 'uint16');
fclose(fileId);

img = double(img');
img = (img./max(img(:))); %rescale s.t. brightest point is maximum monitor level
backgroundIntensity = mean(img(:));%set the mean to the mean over the image
img = img.*255; %rescale s.t. brightest point is maximum monitor level
imageMatrix = uint8(img);
imshow(imageMatrix);



for i=1:length(pixSizes)
    pixSize = pixSizes(i);
    pixImageMatrix = pixellateImage(imageMatrix, pixSize);
    save([saveDir, imageName, '_pix_', num2str(pixSize), '.mat'], 'pixImageMatrix');
end

for i=1:length(blurSizes)
    blurSize = blurSizes(i);
    blurImageMatrix = blurImage(imageMatrix, blurSize);
    save([saveDir, imageName, '_blur_', num2str(blurSize), '.mat'], 'blurImageMatrix');
end
end
%%
pixImageMatrix = load([saveDir, imageName, '_pix_', num2str(pixSize), '.mat']).pixImageMatrix;
imshow(pixImageMatrix);

%%
function img = pixellateImage(img, pixSizeMicrons)
    % Convert pixSize from microns to VH pixels.
    pixSizeArcmin = pixSizeMicrons / 3.3;
    
    % Pixellate the image.
    originalDims = size(img);
    downscaledDims = round(originalDims / pixSizeArcmin);

    img = imresize(img, downscaledDims, 'nearest');
    img = imresize(img, originalDims, 'nearest');
end

function img = blurImage(img, blurSizeMicrons)
    % Convert blurSize from microns to pixels.
    blurSizeArcmin = blurSizeMicrons / 3.3;
    
    % Blur the image.
    img = imgaussfilt(img, blurSizeArcmin);
end