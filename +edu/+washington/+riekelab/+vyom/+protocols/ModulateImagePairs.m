classdef ModulateImagePairs < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                         % Output amplifier
        preTime     = 250           % Pre time in ms
        flashTime   = 250           % Time to flash each image in ms
        gapTime     = 0           % Gap between images in ms
        tailTime    = 250           % Tail time in ms
        repeatsPerEpoch = 240        % Number of images to flash on each epoch
        n_pairs = 10 % Number of image pairs
        fileFolder    = 'metamers' % Folder containing the images
        prefix = 'Fix_OnP_metamer'
        % backgroundIntensity = 0.45; % 0 - 1 (corresponds to image intensities in folder)
        % randomize = true;           % Whether to randomize the order of images shown
        onlineAnalysis = 'none'     % Type of online analysis
        n_repeats = 3;
    end

    properties (Dependent)
        stimTime
        n_images
        numberOfAverages
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'}) 
        sequence
        imagePaths
        s1
        s2
        backgroundImage
        directory
        totalRuns
        image_name
        folderList
        fullImagePaths
        validImageExtensions = {'.png','.jpg','.jpeg','.tif','.tiff'}
        flashFrames
        gapFrames
        pairIndex
        image_dir
        backgroundIntensity
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            if ~obj.isMeaRig
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            end
            
            % Calcualate the number of flash and gap frames.
            obj.flashFrames = round(obj.flashTime * 1e-3 * 60);
            obj.gapFrames = round(obj.gapTime * 1e-3 * 60);
            
            % General directory
            try
                parent_dir = obj.rig.getDevice('Stage').getConfigurationSetting('local_image_directory');
                if isempty(image_dir)
                    parent_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
                end
            catch
                parent_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
            end
            
            % Set the image directory
            obj.image_dir = fullfile(parent_dir, obj.fileFolder);

            % Sequence will be 1:n_pairs, repeated n_repeats times
            obj.sequence = 1:obj.n_pairs;
            obj.sequence = repmat(obj.sequence, 1, obj.n_repeats);

            % Assert length of sequence = numberOfAverages
            assert(length(obj.sequence) == obj.numberOfAverages, 'Length of sequence does not match number of averages');

            disp(['Number of images: ', num2str(obj.n_images)]);
            disp(['Number of image pairs: ', num2str(obj.n_pairs)]);
            disp(['Number of epochs: ', num2str(obj.numberOfAverages)]);
        end

        
        function p = createPresentation(obj)
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display image
            scene = stage.builtin.stimuli.Image(obj.s1);
            scene.size = [size(obj.s1,2),size(obj.s1,1)]; % Retain aspect ratio.
            scene.position = canvasSize/2;
            
            % Use linear interpolation when scaling the image
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);

            % Only allow image to be visible during specific time
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);

            % Control which image is visible.
            preF = floor(obj.preTime*1e-3 * 60);
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)setImage(obj, state.frame - preF));
            % Add the controller.
            p.addController(imgValue);

            % setImage to alternate between s1 and s2 every flashFrames+gapFrames
            function s = setImage(obj, frame)
                flash_index = floor(frame / (obj.flashFrames + obj.gapFrames));
                if mod(flash_index, 2) == 0
                    s = obj.s1;
                else
                    s = obj.s2;
                end
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Remove the Amp responses if it's an MEA rig.
            if obj.isMeaRig
                amps = obj.rig.getDevices('Amp');
                for ii = 1:numel(amps)
                    if epoch.hasResponse(amps{ii})
                        epoch.removeResponse(amps{ii});
                    end
                    if epoch.hasStimulus(amps{ii})
                        epoch.removeStimulus(amps{ii});
                    end
                end
            end
            
            obj.pairIndex = obj.sequence(obj.numEpochsCompleted+1);
            
            % Get s1 and s2 paths by {obj.image_dir}/{obj.prefix}_{idx}_s1.png
            s1_path = fullfile(obj.image_dir, sprintf('%s_%d_s1.png', obj.prefix, obj.pairIndex));
            s2_path = fullfile(obj.image_dir, sprintf('%s_%d_s2.png', obj.prefix, obj.pairIndex));

            % Load s1 and s2 images
            s1 = imread(s1_path);
            obj.s1 = uint8(s1);

            s2 = imread(s2_path);
            obj.s2 = uint8(s2);

            % Create the background image from mean of s1 and s2
            obj.backgroundIntensity = mean([s1(:); s2(:)]);
            obj.backgroundImage = ones(size(s1))*obj.backgroundIntensity;
            obj.backgroundImage = uint8(obj.backgroundImage*255);
            
            epoch.addParameter('folder', obj.fileFolder);
            epoch.addParameter('prefix', obj.prefix);
            epoch.addParameter('pairIndex', obj.pairIndex);
            epoch.addParameter('flashFrames', obj.flashFrames);
            epoch.addParameter('gapFrames', obj.gapFrames);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
        end

        function stimTime = get.stimTime(obj)
            stimTime = obj.repeatsPerEpoch * (obj.flashTime + obj.gapTime);
        end

        function n_images = get.n_images(obj)
            n_images = obj.n_pairs * 2; % Each pair has two images
        end

        function numberOfAverages = get.numberOfAverages(obj)
            % Set number of averages = n_pairs * n_repeats
            numberOfAverages = obj.n_pairs * obj.n_repeats;
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
            end
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
