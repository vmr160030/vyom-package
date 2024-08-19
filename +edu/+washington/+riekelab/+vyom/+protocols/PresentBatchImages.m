% Loads images for MEA
classdef PresentBatchImages < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp % Output amplifier
        preTime     = 250 % in ms
        stimTime    = 250 % in ms
        tailTime    = 250 % in ms
        fileFolder = 'flashImages'; % Folder in freedland-package containing videos
        backgroundIntensity = 0.5; % 0 - 1 (corresponds to image intensities in folder)
        randomize = true; % whether to randomize movies shown
        % Additional parameters
        onlineAnalysis = 'none'
        numberOfAverages = uint16(6) % number of epochs to queue
        numberOfBatches = uint16(2) % number of images to batch
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'}) 
        sequence
        imagePaths
        imageMatrix
        directory
        totalRuns
        image_name
        seed
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)

            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
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
            
            num_reps = ceil(double(obj.numberOfAverages)/size(obj.imagePaths,1));
            
            if obj.randomize
                obj.sequence = zeros(1,obj.numberOfAverages);
                seq = (1:size(obj.imagePaths,1));
                for ii = 1 : num_reps
                    seq = randperm(size(obj.imagePaths,1));
                    obj.sequence((ii-1)*length(seq)+(1:length(seq))) = seq;
                end
                obj.sequence = obj.sequence(1:obj.numberOfAverages);
            else
                obj.sequence = (1:size(obj.imagePaths,1))' * ones(1,num_reps);
                obj.sequence = obj.sequence(:);
            end
            
        end

        
        function p = createPresentation(obj)
            
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            
            
            % Rotate image
            specificImage = imread(fullfile(obj.directory, obj.image_name));
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display image
            scene = stage.builtin.stimuli.Image(uint8(specificImage));
            scene.size = [canvasSize(1),canvasSize(2)];
            scene.position = canvasSize/2;
            
            % Use linear interpolation when scaling the image
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);

            % Only allow image to be visible during specific time
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            
            
            epoch.addParameter('imageName',obj.imagePaths{img_name,1});
            epoch.addParameter('folder',obj.directory);
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
