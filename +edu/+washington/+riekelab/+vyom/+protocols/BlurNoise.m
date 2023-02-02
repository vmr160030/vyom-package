classdef BlurNoise < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Noise leading duration (ms)
        stimTime = 10000                % Noise duration (ms)
        tailTime = 500                  % Noise trailing duration (ms)
        contrast = 1
        %stixelSize = 60                 % Edge length of stixel (microns)
        %stepsPerStixel = 2              % Size of underling grid
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        frameDwell = uint16(1)          % Frame dwell.
        randsPerRep = -1                % Number of random seeds between repeats
        maxWidth = 0                    % Maximum width of the stimulus in microns.
        chromaticClass = 'BY'   % Chromatic type
        onlineAnalysis = 'none'
        numberOfAverages = uint16(2)  % Number of epochs
        noiseFilterSD = 2 % pixels, should it be um?
        noiseContrast = 1;
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'binary', 'ternary', 'gaussian'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic','RGB','BY'})
        seed
        numFrames
        imageMatrix
        maxWidthPix
        noiseStream
        noiseFilterSDPix
        positionStream
        currentNoiseContrast
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end

    methods
        function didSetRig(obj)
            didSetRig@manookinlab.protocols.ManookinLabStageProtocol(obj);

            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);            
            if obj.maxWidth > 0
                obj.maxWidthPix = obj.rig.getDevice('Stage').um2pix(obj.maxWidth)*ones(1,2);
            else
                obj.maxWidthPix = obj.canvasSize; %min(obj.canvasSize);
            end
            
            obj.noiseFilterSDPix = obj.rig.getDevice('Stage').um2pix(obj.noiseFilterSD);
            % Get the number of frames.
            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
        end

 
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            obj.imageMatrix = obj.backgroundIntensity * ones(obj.maxWidthPix(2), obj.maxWidthPix(1));
            checkerboard = stage.builtin.stimuli.Image(uint8(obj.imageMatrix));
            checkerboard.position = obj.canvasSize / 2;
            checkerboard.size = obj.maxWidthPix;

            % Set the minifying and magnifying functions to form discrete
            % stixels.
            checkerboard.setMinFunction(GL.NEAREST);
            checkerboard.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(checkerboard);
            
            gridVisible = stage.builtin.controllers.PropertyController(checkerboard, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(gridVisible);
            
            % Calculate preFrames and stimFrames
            preF = floor(obj.preTime/1000 * 60);

%             if ~strcmp(obj.chromaticClass,'achromatic') && isempty(strfind(obj.rig.getDevice('Stage').name, 'LightCrafter'))
%                 if strcmp(obj.chromaticClass,'BY')
            imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
                @(state)setBYStixels(obj, state.frame - preF));
%                 else
%                     imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
%                         @(state)setRGBStixels(obj, state.frame - preF));
%                 end
%             else
%                 imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
%                     @(state)setStixels(obj, state.frame - preF));
% %                 imgController = stage.builtin.controllers.PropertyController(checkerboard, 'imageMatrix',...
% %                     @(state)setStixels(obj, state.frame - preF, stimF));
%             end
            p.addController(imgController);
            
            function s = setStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = 2*obj.backgroundIntensity * ...
                            (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels)>0.5);
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            % RGB noise
            function s = setRGBStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = 2*obj.backgroundIntensity * ...
                            (obj.noiseStream.rand(obj.numYStixels,obj.numXStixels,3)>0.5);
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
            
            % Blue-Yellow noise
            function s = setBYStixels(obj, frame)
                persistent M;
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = zeros(obj.maxWidthPix(2),obj.maxWidthPix(1),3);
%                         tmpM = 2*obj.backgroundIntensity * ...
%                             (obj.noiseStream.rand(obj.maxWidthPix(2),obj.maxWidthPix(1),2)>0.5);
%                         tmpM = imgaussfilt(tmpM, obj.noiseFilterSD);
                        tmpM = obj.noiseStream.randn(size(M));
%                         tmpM = imgaussfilt(tmpM, obj.noiseFilterSD);
                        tmpM = imgaussfilt(tmpM, obj.noiseFilterSDPix);
                        tmpM = tmpM / std(tmpM(:));
                        tmpM =  2*obj.backgroundIntensity * tmpM;
                        M(:,:,1:2) = repmat(tmpM(:,:,1),[1,1,2]);
                        M(:,:,3) = tmpM(:,:,2);
                    end
                else
                    M = obj.imageMatrix;
                end
                s = uint8(255*M);
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Deal with the seed.
            if obj.randsPerRep == 0 
                obj.seed = 1;
            elseif obj.randsPerRep < 0
                if obj.numEpochsCompleted == 0
                    obj.seed = RandStream.shuffleSeed;
                else
                    obj.seed = obj.seed + 1;
                end
            elseif obj.randsPerRep > 0 && (mod(obj.numEpochsCompleted+1,obj.randsPerRep+1) == 0)
                obj.seed = 1;
            else
                if obj.numEpochsCompleted == 0
                    obj.seed = RandStream.shuffleSeed;
                else
                    obj.seed = obj.seed + 1;
                end
            end
            
            % Seed the generator
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.positionStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('numFrames', obj.numFrames);
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
