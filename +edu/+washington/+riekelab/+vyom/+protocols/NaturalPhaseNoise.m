classdef NaturalPhaseNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 1000                 % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        stimulusIndices = [2 6 12 18 24 30 40]         % Stimulus number (1:161)
        noiseAmps = [0.05 0.1 0.2 0.3 0.4] % Phase noise amplitude (scalar)
        maskDiameter = 0                % Mask diameter in pixels
        apertureDiameter = 2000         % Aperture diameter in pixels.
        freezeFEMs = false
        onlineAnalysis = 'extracellular' % Type of online analysis
        numberOfRepeats = uint16(100)   % Number of epochs
        modImgDir = 'C:\Users\Public\Documents\GitRepos\Symphony2\vyom-package\+edu\+washington\+riekelab\+vyom\+Doves\+PhaseNoiseImages\'  % Directory of modified image .mat files
    end
    
    properties (Hidden)
        numberOfAverages % Number of epochs
        numVariants
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        imageMatrix
        backgroundIntensity
        imageName
        subjectName
        magnificationFactor
        currentStimSet
        stimulusIndex
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
            obj.numNoiseAmps = length(obj.noiseAmps);
            obj.numVariants = obj.numNoiseAmps + 1;
            disp(obj.numVariants);
            obj.numberOfAverages = obj.numberOfRepeats * obj.numVariants * length(obj.stimulusIndices);
            
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            % Get the resources directory.
            obj.pkgDir = manookinlab.Package.getResourcePath();
            
            obj.currentStimSet = 'dovesFEMstims20160826.mat';
            
            % Load the current stimulus set.
            obj.im = load([obj.pkgDir,'\',obj.currentStimSet]);
            
            % Get the image and subject names.
            if length(unique(obj.stimulusIndices)) == 1
                obj.stimulusIndex = unique(obj.stimulusIndices);
                obj.getImageSubject();
            end

            % Set noise and stimulus indices.
            obj.noiseIndex = -1;
            obj.stimulusIndex = obj.stimulusIndices(1);

            disp('Prepared run');
        end
        
        function getImageSubject(obj)
            % Get the image name.
            obj.imageName = obj.im.FEMdata(obj.stimulusIndex).ImageName;
            
            % Load the image if noise index is 0.
            if obj.noiseIndex == 0
                fileId = fopen([obj.pkgDir,'\doves\images\', obj.imageName],'rb','ieee-be');
                img = fread(fileId, [1536 1024], 'uint16');
                fclose(fileId);
                
                img = double(img');
                img = (img./max(img(:))); %rescale s.t. brightest point is maximum monitor level
                obj.backgroundIntensity = mean(img(:));%set the mean to the mean over the image
                img = img.*255; %rescale s.t. brightest point is maximum monitor level
                obj.imageMatrix = uint8(img);
            end

            % If noiseIndex>0, load the noise image.
            if obj.noiseIndex > 0
                noiseSize = obj.noiseAmps(obj.noiseIndex);
                filepath = [obj.modImgDir, obj.imageName, '_phnoise_', num2str(noiseSize), '.mat'];
                data = load(filepath);
		    obj.imageMatrix = data.pixImageMatrix;
            end    
            
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create your scene.
            scene = stage.builtin.stimuli.Image(obj.imageMatrix);
            scene.size = [size(obj.imageMatrix,2) size(obj.imageMatrix,1)]*obj.magnificationFactor;
            p0 = obj.canvasSize/2;
            scene.position = p0;
            
            scene.setMinFunction(GL.NEAREST);
            scene.setMagFunction(GL.NEAREST);
            
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
        end
        
        function prepareEpoch(obj, epoch)
            % Increment noise index till end of noiseAmps
            obj.noiseIndex = obj.noiseIndex + 1;
            if obj.noiseIndex <= obj.numNoiseAmps
                obj.getImageSubject();
            end
            
            % At end of noiseAmps, increment stimIndex
            if obj.noiseIndex > obj.numNoiseAmps
                obj.noiseIndex = 0;

                % Set the current stimulus
                obj.stimulusIndex = obj.stimulusIndices(mod(obj.numEpochsCompleted, obj.numVariants) + 2);
                obj.getImageSubject();
            end
            
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            % Save the parameters.
            epoch.addParameter('stimulusIndex', obj.stimulusIndex);
            epoch.addParameter('imageName', obj.imageName);
            epoch.addParameter('subjectName', obj.subjectName);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            epoch.addParameter('currentStimSet',obj.currentStimSet);
            epoch.addParameter('noiseIndex', obj.noiseIndex);
            if obj.noiseIndex>0
                epoch.addParameter('noiseSize', obj.noiseAmps(obj.noiseIndex));
            else
                epoch.addParameter('noiseSize', 0);
            end
            disp('Prepared epoch');
            
            % Display stim and noise indices
            disp(['Stimulus index: ' num2str(obj.stimulusIndex)]);            
            disp(obj.imageName);
            disp(['Noise index: ' num2str(obj.noiseIndex)]);
        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages) && (length(unique(obj.stimulusIndices)) == 1)
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
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