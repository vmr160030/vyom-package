classdef NaturalPhaseNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 100                   % Stimulus leading duration (ms)
        stimTime = 100                 % Stimulus duration (ms)
        tailTime = 100                  % Stimulus trailing duration (ms)
        stimNameFile = 'C:\Users\Public\Documents\GitRepos\Symphony2\vyom-package\+edu\+washington\+riekelab\+vyom\+Doves\+PhaseNoiseImages\pn_June6_2023.csv' % csv of stimulus filenames
        noiseIndices = [0 1 2 3 4] % Phase noise amplitude index (0:4)
        maskDiameter = 0                % Mask diameter in pixels
        apertureDiameter = 2000         % Aperture diameter in pixels.
        freezeFEMs = false
        onlineAnalysis = 'extracellular' % Type of online analysis
        numberOfRepeats = uint16(10)   % Number of flashes for each image
        modImgDir = 'C:\Users\Public\Documents\GitRepos\Symphony2\vyom-package\+edu\+washington\+riekelab\+vyom\+Doves\+PhaseNoiseImages\'  % Directory of modified image .mat files
    end
    
    properties (Hidden)
        numImages
        numNoiseAmps
        numVariants
        numberOfAverages % Number of epochs
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        imgData
        imageMatrix
        backgroundIntensity
        imageName
        imageNames
        magnificationFactor
        currentStimSet
        stimCsv
        stimListIndex
        noiseIndex
        pkgDir
        im
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            % Get the magnification factor. Exps were done with each pixel
            % = 1 arcmin == 1/60 degree; 200 um/degree...
            obj.magnificationFactor = round(1/60*200/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'));
            
            % Load stimulus info csv
            obj.stimCsv = readtable(obj.stimNameFile);
            obj.imageNames = unique(obj.stimCsv.img_name);
            obj.numImages = length(obj.imageNames);
            disp(['Num images ', num2str(obj.numImages)]);
            obj.numNoiseAmps = length(obj.noiseIndices);
            obj.numVariants = obj.numNoiseAmps + 1;
            disp(obj.numVariants);
            obj.numberOfAverages = obj.numberOfRepeats * obj.numVariants * obj.numImages;
            
            % Prepare run superclass later as needs numberOfAverages set
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            % Set noise and stimulus indices.
            obj.noiseIndex = -2;
            obj.stimListIndex = 1;
            obj.getImageData();

            disp('Prepared run');
        end
        
        function getImageData(obj)
            % Get the image name.
            obj.imageName = obj.imageNames(obj.stimListIndex);
            filepath = char(strcat(obj.modImgDir, obj.imageName, '.mat'));
            disp(filepath);
            obj.imgData = load(filepath);
            
        end
        
        function getImageVersion(obj)
            % Load the image if noise index is 0.
            if obj.noiseIndex == -1
                obj.imageMatrix = obj.imgData.base;
            end

            % If noiseIndex>0, load the noise image.
            if obj.noiseIndex >= 0
                obj.imageMatrix = obj.imgData.(['noise_', num2str(obj.noiseIndex)]);
            end    
            
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            %canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create your scene.
            scene = stage.builtin.stimuli.Image(obj.imageMatrix);
            scene.size = [size(obj.imageMatrix,2) size(obj.imageMatrix,1)]*obj.magnificationFactor;
            %scene.size = canvasSize;
            p0 = obj.canvasSize/2;
            scene.position = p0;
            
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);
            
            % Add the stimulus to the presentation.
            p.addStimulus(scene);            

            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
            
            %--------------------------------------------------------------
            % Size is 0 to 1
            sz = (obj.apertureDiameter)/min(obj.canvasSize);
            % Create the outer mask.
            if sz < 1
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = obj.canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = obj.canvasSize;
                [x,y] = meshgrid(linspace(-obj.canvasSize(1)/2,obj.canvasSize(1)/2,obj.canvasSize(1)), ...
                    linspace(-obj.canvasSize(2)/2,obj.canvasSize(2)/2,obj.canvasSize(2)));
                distanceMatrix = sqrt(x.^2 + y.^2);
                circle = uint8((distanceMatrix >= obj.apertureDiameter/2) * 255);
                mask = stage.core.Mask(circle);
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            
            if (obj.maskDiameter > 0) % Create mask
                mask = stage.builtin.stimuli.Ellipse();
                mask.position = obj.canvasSize/2;
                mask.color = obj.backgroundIntensity;
                mask.radiusX = obj.maskDiameter/2;
                mask.radiusY = obj.maskDiameter/2;
                p.addStimulus(mask); %add mask
            end
            disp('created presentation');
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            % Increment noise index till end of noiseAmps
            obj.noiseIndex = obj.noiseIndex + 1;
            if obj.noiseIndex <= obj.numNoiseAmps
                obj.getImageVersion();
            end
            
            % At end of noiseAmps, increment stimIndex
            if obj.noiseIndex > obj.numNoiseAmps
                obj.noiseIndex = -1;
                obj.stimListIndex = obj.stimListIndex + 1;
                if obj.stimListIndex > obj.numImages
                   obj.stimListIndex = 1; 
                end

                % Set the current stimulus
                obj.getImageData();
                obj.getImageVersion();
            end
            
            %imshow(obj.imageMatrix);
            
            % Save the parameters.
            epoch.addParameter('stimListIndex', obj.stimListIndex);
            epoch.addParameter('imageName', obj.imageName);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            epoch.addParameter('stimNameFile',obj.stimNameFile);
            epoch.addParameter('noiseIndex', obj.noiseIndex);
            disp('Prepared epoch');
            
            % Display stim and noise indices
            disp(['Stimulus index: ' num2str(obj.stimListIndex)]);            
            disp(obj.imageName);
            disp(['Noise index: ' num2str(obj.noiseIndex)]);
        end
        
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end