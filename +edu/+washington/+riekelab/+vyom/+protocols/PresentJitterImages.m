% MEA: Flashes images at several jittered locations.
classdef PresentJitterImages < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp % Output amplifier
        preTime     = 250 % in ms
        flashTime   = 250 % Time to flash each image in ms
        gapTime = 250 % Gap between images in ms
        tailTime    = 250 % in ms
        fileFolder = 'flashImages'; % Folder containing images
        imagesPerEpoch = 10; % Number of images to flash on each epoch
        
        %background is set for each image to image mean
        %backgroundIntensity = 0.5; % 0 - 1 (corresponds to image intensities in folder)
        randomize = true; % whether to randomize images shown

        % Jitter parameters
        jitterSpacing = 20; % Spacing of jittered images (microns)
        numJitter = 5; % Number of displaced images to show in X and Y
        onlyJitterX = false; % Only jitter in X direction

        onlineAnalysis = 'none'
        numberOfReps = uint16(5) % Number of repetitions at each displaced location.
    end

    properties (Dependent)
        stimTime
    end
    
    properties (Hidden)
        ampType
        numberOfImages
        numberOfAverages % number of epochs. numberOfReps * numJitter^2
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'}) 
        sequence
        imagePaths
        imageMatrix
        directory
        totalRuns
        image_name
        seed

        jitterSpacingPix
        seqJitterX
        seqJitterY
        jitterX
        jitterY
        backgroundIntensity
        backgroundImageMatrix
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function organizeSequence(obj)
            % General directory
            obj.directory = strcat('C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\',obj.fileFolder); % General folder
            D = dir(obj.directory);
            
            obj.imagePaths = cell(size(D,1),1);
            for a = 1:length(D)
                if sum(strfind(D(a).name,'.png')) > 0
                    obj.imagePaths{a,1} = D(a).name;
                end
            end

            obj.imagePaths = obj.imagePaths(~cellfun(@isempty, obj.imagePaths(:,1)), :);
            obj.numberOfImages = size(obj.imagePaths,1);
            % Assert number of images equal to imagesPerEpoch
            assert(obj.numberOfImages == obj.imagesPerEpoch, 'Number of images in folder does not match imagesPerEpoch');

            % Order of images
            if obj.randomize
                obj.sequence = randperm(obj.numberOfImages);
            else
                obj.sequence = 1:obj.numberOfImages;
            end
            
            % Load the images.
            obj.imageMatrix = cell(1, obj.imagesPerEpoch);
            obj.backgroundImageMatrix = cell(1, obj.imagesPerEpoch);
            for ii = 1 : obj.numberOfImages
                img_idx = obj.sequence(ii);
                imgName = obj.imagePaths{img_idx, 1};
                
                % Load the image.
                myImage = imread(fullfile(obj.directory, imgName));
                obj.imageMatrix{ii} = uint8(myImage);
                obj.image_name = [obj.image_name, imgName];
                if ii < obj.imagesPerEpoch
                    obj.image_name = [obj.image_name,'_'];
                end

                % Create the background image.
                img_bg = mean(mean(myImage))/255;
                obj.backgroundImageMatrix{ii} = ones(size(myImage))*img_bg;
                obj.backgroundImageMatrix{ii} = uint8(obj.backgroundImageMatrix{ii}*255);
            end

            
            % Compute number of averages
            if obj.onlyJitterX
                jitter_combinations = obj.numJitter;
            else
                jitter_combinations = obj.numJitter^2;
            end
            obj.numberOfAverages = uint16(obj.numberOfReps * jitter_combinations);
            disp(['Number of epochs:',num2str(obj.numberOfAverages)]);
            
            % Create sequence of X and Y jitters
            obj.seqJitterX = zeros(uint16(jitter_combinations),1);
            obj.seqJitterY = zeros(uint16(jitter_combinations),1);
            if obj.onlyJitterX
                obj.seqJitterY = zeros(uint16(jitter_combinations),1);
                count = 1;
                for x = 1:obj.numJitter
                    obj.seqJitterX(count) = (x-1)*obj.jitterSpacingPix;
                    count = count + 1;
                end
            else
                count = 1;
                for x = 1:obj.numJitter
                    for y = 1:obj.numJitter
                        obj.seqJitterX(count) = (x-1)*obj.jitterSpacingPix;
                        obj.seqJitterY(count) = (y-1)*obj.jitterSpacingPix;
                        count = count + 1;
                    end
                end
            end

            % Repeat seqJitter for numberOfReps to match numberOfAverages size
            obj.seqJitterX = repmat(obj.seqJitterX,obj.numberOfReps,1);
            obj.seqJitterY = repmat(obj.seqJitterY,obj.numberOfReps,1);
        end

        function prepareRun(obj)
            % Needs to be before call to parent to compute numberOfAverages
            obj.jitterSpacingPix = obj.rig.getDevice('Stage').um2pix(obj.jitterSpacing);
            disp(['Jitter spacing microns: ',num2str(obj.jitterSpacing)]);
            disp(['Jitter spacing in pixels: ',num2str(obj.jitterSpacingPix)]);
            obj.organizeSequence();

            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            disp('prepared run')
        end
        
        function p = createPresentation(obj)
            disp('creating presentation')
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display image
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = [canvasSize(1),canvasSize(2)];
            scene.position = canvasSize/2  + [obj.jitterX, obj.jitterY];
            
            % Use linear interpolation when scaling the image
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);

            % Only allow image to be visible during specific time
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
            
            % Control which image is visible.
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)setImage(obj, state.time - obj.preTime*1e-3));
            % Add the controller.
            p.addController(imgValue);

            function s = setImage(obj, time)
                img_index = floor( time / ((obj.flashTime+obj.gapTime)*1e-3) ) + 1;
                if img_index < 1 || img_index > obj.imagesPerEpoch
                    s = obj.backgroundImageMatrix{1};
                elseif (time >= ((obj.flashTime+obj.gapTime)*1e-3)*(img_index-1)) && (time <= (((obj.flashTime+obj.gapTime)*1e-3)*(img_index-1)+obj.flashTime*1e-3))
                    s = obj.imageMatrix{img_index};
                else
                    s = obj.backgroundImageMatrix{img_index};
                end
            end

            disp('created presentation');
        end
        
        function prepareEpoch(obj, epoch)
            disp('preparing epoch')
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

            % Get current jitter values
            obj.jitterX = obj.seqJitterX(mod(obj.numEpochsCompleted,length(obj.seqJitterX)) + 1);
            obj.jitterY = obj.seqJitterY(mod(obj.numEpochsCompleted,length(obj.seqJitterY)) + 1);
            
            % Set background intensity to first image mean
            obj.backgroundIntensity = double(obj.backgroundImageMatrix{1}(1,1))/255;

            % Add parameters to epoch
            epoch.addParameter('imageName', obj.image_name);
            epoch.addParameter('folder',obj.directory);
            epoch.addParameter('jitterX',obj.jitterX);
            epoch.addParameter('jitterY',obj.jitterY);
            epoch.addParameter('jitterSpacing',obj.jitterSpacing);
            epoch.addParameter('jitterSpacingPix', obj.jitterSpacingPix);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            
            % Display parameters
            disp(['Epoch ', num2str(obj.numEpochsCompleted), ' of ', num2str(obj.numberOfAverages)]);
            disp(['Jitter X: ', num2str(obj.jitterX)]);
            disp(['Jitter Y: ', num2str(obj.jitterY)]);
            disp(['Image Name: ', obj.image_name]);
            disp(['Background Intensity: ', num2str(obj.backgroundIntensity)]);
            
%             if obj.randomize
%                 epoch.addParameter('seed',obj.seed);
%             end
        end

        function stimTime = get.stimTime(obj)
            stimTime = obj.imagesPerEpoch * (obj.flashTime + obj.gapTime);
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
