% MEA: Flashes images at several jittered locations.
classdef PresentJitterImages < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp % Output amplifier
        preTime     = 250 % in ms
        stimTime    = 250 % in ms
        tailTime    = 250 % in ms
        fileFolder = 'flashImages'; % Folder containing images
        %backgroundIntensity = 0.5; % 0 - 1 (corresponds to image intensities in folder)
        %randomize = true; % whether to randomize images shown

        % Jitter parameters
        jitterSpacing = 50; % Spacing of jittered images (microns)
        numJitter = 5; % Number of displaced images to show in X and Y
        % Additional parameters
        onlineAnalysis = 'none'
        numberOfReps = uint16(5) % Number of repetitions at each displaced location.
    end
    
    properties (Hidden)
        ampType
        numberOfImages
        numberOfRepsPerImage % This will be numJitter^2 * numberOfReps
        numberOfAverages % number of epochs. numberOfReps * numJitter^2 * numberOfImages
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
        seqBgs
        backgroundIntensity
        
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
            obj.seqBgs = zeros(obj.numberOfImages,1);
            for a = 1:obj.numberOfImages
                img_name = obj.imagePaths{a,1};
                obj.seqBgs(a) = mean(imread(fullfile(obj.directory,img_name)), 'all');
            end

            obj.numberOfRepsPerImage = uint16(obj.numberOfReps * obj.numJitter^2);
            obj.numberOfAverages = uint16(obj.numberOfRepsPerImage * size(obj.imagePaths,1));
            disp(['Number of epochs:',num2str(obj.numberOfAverages)]);

            % Create sequence of X and Y jitters
            obj.seqJitterX = zeros(uint16(obj.numJitter^2),1);
            obj.seqJitterY = zeros(uint16(obj.numJitter^2),1);
            count = 1;
            for x = 1:obj.numJitter
                for y = 1:obj.numJitter
                    obj.seqJitterX(count) = (x-1)*obj.jitterSpacingPix;
                    obj.seqJitterY(count) = (y-1)*obj.jitterSpacingPix;
                    count = count + 1;
                end
            end

            % Repeat seqJitter for numberOfReps and numberOfImages to match numberOfAverages size
            obj.seqJitterX = repelem(obj.seqJitterX,obj.numberOfImages);
            obj.seqJitterX = repmat(obj.seqJitterX,obj.numberOfReps,1);
            obj.seqJitterY = repelem(obj.seqJitterY,obj.numberOfImages);
            obj.seqJitterY = repmat(obj.seqJitterY,obj.numberOfReps,1);

            % Create sequence of images to run through. This doesn't work LOL.
            % if obj.randomize
            %     obj.sequence = zeros(1,obj.numberOfAverages);
            %     for ii = 1 : obj.numberOfRepsPerImage
            %         seq = randperm(size(obj.imagePaths,1));
            %         obj.sequence((ii-1)*length(seq)+(1:length(seq))) = seq;
            %     end
            %     obj.sequence = obj.sequence(1:obj.numberOfAverages);
            % else
            obj.sequence =  (1:obj.numberOfImages)' * ones(1, obj.numberOfRepsPerImage);
            obj.sequence = obj.sequence(:);
            % end

        end

        function prepareRun(obj)
            % Needs to be before call to parent to compute numberOfAverages
            obj.jitterSpacingPix = obj.rig.getDevice('Stage').um2pix(obj.jitterSpacing);
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
            
            % Load image
            specificImage = imread(fullfile(obj.directory, obj.image_name));
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display image
            scene = stage.builtin.stimuli.Image(uint8(specificImage));
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
            disp('created presentation');
        end
        
        function prepareEpoch(obj, epoch)
            disp('preparing epoch')
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            img_idx = obj.sequence(mod(obj.numEpochsCompleted,length(obj.sequence)) + 1);
            obj.image_name = obj.imagePaths{img_idx,1};
            obj.jitterX = obj.seqJitterX(mod(obj.numEpochsCompleted,length(obj.seqJitterX)) + 1);
            obj.jitterY = obj.seqJitterY(mod(obj.numEpochsCompleted,length(obj.seqJitterY)) + 1);
            obj.backgroundIntensity = obj.seqBgs(img_idx);


            % Add parameters to epoch
            epoch.addParameter('imageName', obj.image_name);
            epoch.addParameter('folder',obj.directory);
            epoch.addParameter('jitterX',obj.jitterX);
            epoch.addParameter('jitterY',obj.jitterY);
            epoch.addParameter('jitterSpacing',obj.jitterSpacing);
            epoch.addParameter('jitterSpacingPix', obj.jitterSpacingPix);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            disp(obj.image_name)
            disp(obj.jitterX)
            disp(obj.jitterY)

            
            if obj.randomize
                epoch.addParameter('seed',obj.seed);
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
