classdef ContrastResponseGratingGrid < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Grating leading duration (ms)
        stimTime = 5000                 % Grating duration (ms)
        tailTime = 250                  % Grating trailing duration (ms)
        contrasts = [0.05 0.15 0.45 1.00] % Grating contrast (0-1)
        orientation = 0.0               % Grating orientation (deg)
        barWidths = [20 40 80 160]      % Grating bar width (um)
        temporalFrequencies = [1 3 9 27 81]        % Temporal frequency (Hz)
        barWidthContrasts = [2 3 4 4]   % Number of top contrasts for each bar width
        temporalFrequencyContrasts = [4 4 4 2 1] % Number of top contrasts for each temporal frequency
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        apertureRadius = 0              % Aperture radius in pixels.
        apertureClass = 'spot'          % Spot or annulus?       
        spatialClass = 'squarewave'     % Spatial type (sinewave or squarewave)
        temporalClass = 'drifting'      % Temporal type (drifting or reversing)      
        chromaticClass = 'achromatic'   % Chromatic type
        numberOfRepeats = uint16(2)   % Number of repeats.
    end
    
    properties (Hidden)
        numberOfAverages % Number of epochs
        ampType
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'drifting', 'reversing'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red-green isoluminant','red-green isochromatic','S-iso','M-iso','L-iso'})
        contrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        rawImage
        spatialPhaseRad % The spatial phase in radians.
        contrast
        barWidth
        temporalFrequency
        spatialFreq % The current spatial frequency for the epoch
        backgroundMeans
        barWidthPix
        seqBW % Sequence of bar widths
        seqTF % Sequence of temporal frequencies
        seqC % Sequence of contrasts
    end
    
    % Analysis properties
    properties (Hidden)
        coneContrasts 
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            % Generate the sequences of parameters.
            [obj.seqBW, obj.seqTF, obj.seqC] = obj.generateCombinations();
            obj.seqBW = repmat(obj.seqBW, obj.numberOfRepeats, 1);
            obj.seqTF = repmat(obj.seqTF, obj.numberOfRepeats, 1);
            obj.seqC = repmat(obj.seqC, obj.numberOfRepeats, 1);
            obj.numberOfAverages = length(obj.seqBW);
            disp(['Number of epochs: ', num2str(obj.numberOfAverages)]);

            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));

            % Calculate the spatial phase in radians.
            obj.spatialPhaseRad = obj.spatialPhase / 180 * pi;
            
            % Set the LED weights.
            if strcmp(obj.stageClass,'LightCrafter')
                obj.backgroundMeans = obj.backgroundIntensity*ones(1,3);
                obj.colorWeights = ones(1,3);
            else
                if strcmp(obj.chromaticClass, 'achromatic')
                    obj.backgroundMeans = obj.backgroundIntensity*ones(1,3);
                    obj.colorWeights = ones(1,3);
                else
                    [obj.backgroundMeans, ~, obj.colorWeights] = getMaxContrast(obj.quantalCatch, obj.chromaticClass);
                end
            end
            
            % Calculate the cone contrasts.
            obj.coneContrasts = coneContrast((obj.backgroundMeans(:)*ones(1,size(obj.quantalCatch,2))).*obj.quantalCatch, ...
                obj.colorWeights, 'michaelson');

            disp(['Prepared run with ', num2str(obj.numberOfAverages), ' epochs']);
        end

        function [seqBW, seqTF, seqC] = generateCombinations(obj)
            seqBW = [];
            seqTF = [];
            seqC = [];
            for bwIdx = 1:length(obj.barWidths)
                for tfIdx = 1:length(obj.temporalFrequencies)
                    bw = obj.barWidths(bwIdx);
                    tf = obj.temporalFrequencies(tfIdx);
                    numContrasts = min(obj.barWidthContrasts(bwIdx), obj.temporalFrequencyContrasts(tfIdx));
                    selected_c = obj.contrasts(end-numContrasts+1:end);
                    for c = selected_c
                        seqBW = [seqBW; bw];
                        seqTF = [seqTF; tf];
                        seqC = [seqC; c];
                    end
                end
            end
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundMeans); % Set background intensity
            
            % Create the grating.
            grate = stage.builtin.stimuli.Image(uint8(0 * obj.rawImage));
            grate.position = obj.canvasSize / 2;
            grate.size = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2))*ones(1,2);
            grate.orientation = obj.orientation;
            
            % Set the minifying and magnifying functions.
            grate.setMinFunction(GL.NEAREST);
            grate.setMagFunction(GL.NEAREST);
            
            % Add the grating.
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
            
            %--------------------------------------------------------------
            % Generate the grating.
            if strcmp(obj.temporalClass, 'drifting')
                imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setDriftingGrating(obj, state.time - obj.preTime * 1e-3));
            else
                imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setReversingGrating(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(imgController);
            
            % Set the drifting grating.
            function g = setDriftingGrating(obj, time)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end
                
                g = cos(obj.spatialPhaseRad + phase + obj.rawImage);
                
                if strcmp(obj.spatialClass, 'squarewave')
                    g = sign(g);
                end
                
                g = obj.contrast * g;
                
                % Deal with chromatic gratings.
                if ~strcmp(obj.stageClass,'LightCrafter')
                    for m = 1 : 3
                        g(:,:,m) = obj.backgroundMeans(m) * obj.colorWeights(m) * g(:,:,m) + obj.backgroundMeans(m);
                    end
                    g = uint8(255*(g));
                else
                    g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
                end
            end
            
            % Set the reversing grating
            function g = setReversingGrating(obj, time)
                if time >= 0
                    phase = round(0.5 * sin(time * 2 * pi * obj.temporalFrequency) + 0.5) * pi;
                else
                    phase = 0;
                end
                
                g = cos(obj.spatialPhaseRad + phase + obj.rawImage);
                
                if strcmp(obj.spatialClass, 'squarewave')
                    g = sign(g);
                end
                
                g = obj.contrast * g;
                
                % Deal with chromatic gratings.
                if ~strcmp(obj.chromaticClass, 'achromatic')
                    for m = 1 : 3
                        g(:,:,m) = obj.colorWeights(m) * g(:,:,m);
                    end
                end
                g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
            end

            if obj.apertureRadius > 0
                if strcmpi(obj.apertureClass, 'spot')
                    aperture = stage.builtin.stimuli.Rectangle();
                    aperture.position = obj.canvasSize/2 + obj.centerOffset;
                    aperture.color = obj.backgroundIntensity;
                    aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
                    mask = stage.core.Mask.createCircularAperture(obj.apertureRadius*2/max(obj.canvasSize), 1024);
                    aperture.setMask(mask);
                    p.addStimulus(aperture);
                else
                    mask = stage.builtin.stimuli.Ellipse();
                    mask.color = obj.backgroundIntensity;
                    mask.radiusX = obj.apertureRadius;
                    mask.radiusY = obj.apertureRadius;
                    mask.position = obj.canvasSize / 2 + obj.centerOffset;
                    p.addStimulus(mask);
                end
            end
        end
        
        function setRawImage(obj)
            downsamp = 3;
            sz = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2));
            [x,y] = meshgrid(...
                linspace(-sz/2, sz/2, sz/downsamp), ...
                linspace(-sz/2, sz/2, sz/downsamp));
            
            % Calculate the orientation in radians.
            rotRads = obj.orientation / 180 * pi;
            
            % Center the stimulus.
            x = x + obj.centerOffset(1)*cos(rotRads);
            y = y + obj.centerOffset(2)*sin(rotRads);
            
            x = x / min(obj.canvasSize) * 2 * pi;
            y = y / min(obj.canvasSize) * 2 * pi;
            
            % Calculate the raw grating image.
            img = (cos(0)*x + sin(0) * y) * obj.spatialFreq;
            obj.rawImage = img(1,:);
%             obj.rawImage = (cos(rotRads) * x + sin(rotRads) * y) * obj.spatialFreq;
            
            if ~strcmp(obj.stageClass, 'LightCrafter')
                obj.rawImage = repmat(obj.rawImage, [1 1 3]);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

            % Get the current combination of parameters.
            idx = mod(obj.numEpochsCompleted, obj.numberOfAverages) + 1;
            obj.barWidth = obj.seqBW(idx);
            obj.temporalFrequency = obj.seqTF(idx);
            obj.contrast = obj.seqC(idx);

            % Get the bar width in pixels
            obj.barWidthPix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);

            % Calculate the spatial frequency.
            obj.spatialFreq = min(obj.canvasSize)/(2*obj.barWidthPix);

            % Set up the raw image.
            obj.setRawImage();

            % Add the parameters to the epoch.
            epoch.addParameter('barWidth', obj.barWidth);
            epoch.addParameter('barWidthPix', obj.barWidthPix);
            epoch.addParameter('spatialFreq', obj.spatialFreq);
            epoch.addParameter('temporalFrequency', obj.temporalFrequency);
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('backgroundMeans', obj.backgroundMeans);

            % Display the current parameters.
            disp(['Epoch ', num2str(obj.numEpochsCompleted + 1), ...
                ': bar width = ', num2str(obj.barWidth), ...
                ', temporal frequency = ', num2str(obj.temporalFrequency), ...
                ', contrast = ', num2str(obj.contrast)]);

            % Add the spatial frequency to the epoch.
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('backgroundMeans',obj.backgroundMeans);

            
            
            % Save out the cone/rod contrasts.
            epoch.addParameter('lContrast', obj.coneContrasts(1));
            epoch.addParameter('mContrast', obj.coneContrasts(2));
            epoch.addParameter('sContrast', obj.coneContrasts(3));
            epoch.addParameter('rodContrast', obj.coneContrasts(4));
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        
    end
end


