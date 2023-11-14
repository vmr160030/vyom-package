classdef CuttlefishBar < manookinlab.protocols.ManookinLabStageProtocol %Built from ContrastResponseGrating
    properties
        amp                             % Output amplifier
        preTime = 250                   % Grating leading duration (ms)
        stimTime = 6000                 % Grating duration (ms)
        tailTime = 250                  % Grating trailing duration (ms)
        contrast = 1.0 % Grating contrast (0-1)
        gratingOrientation = 0.0               % Grating orientation (deg)
        gratingBarWidth = 300                  % Grating bar width (um)
        temporalFrequency = 4.0         % Temporal frequency (Hz)
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        apertureRadius = 0              % Aperture radius in pixels.
        apertureClass = 'spot'          % Spot or annulus?       
        spatialClass = 'sinewave'     % Spatial type (sinewave or squarewave)
        temporalClass = 'drifting'      % Temporal type (drifting or reversing)      
        chromaticClass = 'achromatic'   % Chromatic type
        numberOfAverages = uint16(12)   % Number of epochs

        % barOrientation = 0              % Bar orientation (deg). For now always 0.
        barSize = 400                   % Bar size (um). Only in x-direction
        barSpeed = 1000                 % Bar speed (um/sec)
    end
    
    properties (Hidden)
        ampType
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'drifting', 'reversing'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red-green isoluminant','red-green isochromatic','S-iso','M-iso','L-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        contrastsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        rawImage
        spatialPhaseRad % The spatial phase in radians.
        spatialFreq % The current spatial frequency for the epoch
        backgroundMeans
        gratingBarWidthPix
        barSizePix
        barSizeDownPix
        barSpeedPix
        barSpeedDownPix
        barInitOffsetPix
        barInitOffsetDownPix
        downsamp
        downSampDim
    end
    
    % Analysis properties
    properties (Hidden)
        xaxis
        F1Amp
        repsPerX
        coneContrasts 
    end
    
    properties (Hidden, Transient)
        analysisFigure
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            % Set downsampling factor
            obj.downsamp = 4;
            
            % Calculate the spatial phase in radians.
            obj.spatialPhaseRad = obj.spatialPhase / 180 * pi;
            
            % Get the bar width in pixels
            obj.gratingBarWidthPix = obj.rig.getDevice('Stage').um2pix(obj.gratingBarWidth);
            obj.barSizePix = obj.rig.getDevice('Stage').um2pix(obj.barSize);
            obj.barSpeedPix = obj.rig.getDevice('Stage').um2pix(obj.barSpeed);

            % Get bar width in downsampled space
            obj.barSizeDownPix = round(obj.barSizePix/obj.downsamp);
            obj.barSpeedDownPix = round(obj.barSpeedPix/obj.downsamp);

            % Set bar initial offset
            obj.barInitOffsetPix = min(obj.canvasSize/2);
            obj.barInitOffsetDownPix = round(obj.barInitOffsetPix/obj.downsamp);
            disp('barSizeDownPix, barSpeedDownPix, barInitOffsetDownPix');
            disp([obj.barSizeDownPix, obj.barSpeedDownPix, obj.barInitOffsetDownPix]);

            % Set bar orientation. Hardcoded to 0 for now, moving to the right in x.
            % obj.barOrientation = 0;
            % obj.barOrientationRads = obj.barOrientation / 180 * pi;
            
            % Calculate the spatial frequency.
            obj.spatialFreq = min(obj.canvasSize)/(2*obj.gratingBarWidthPix);
            
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
            
            % Set up the raw image.
            obj.setRawImage();
            disp('Prepared run. Canvas Size:');
            disp(obj.canvasSize);
        end
        
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundMeans); % Set background intensity
            disp('set background');
            
            % Create the grating.
            grate = stage.builtin.stimuli.Image(uint8(0 * obj.rawImage));
            grate.position = obj.canvasSize / 2;
            grate.size = obj.canvasSize(1)*ones(1,2); % Scale by canvas width
            grate.orientation = obj.gratingOrientation;
            disp('Created grating');
            
            % Set the minifying and magnifying functions.
            grate.setMinFunction(GL.NEAREST);
            grate.setMagFunction(GL.NEAREST);
            
            % Add the grating.
            p.addStimulus(grate);
            disp('added grating');
            
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

                %% Calculate moving bar position
                % Inc keeps track of right edge of bar
                inc = time * obj.barSpeedDownPix + obj.barSizeDownPix - obj.barInitOffsetDownPix;
                inc = round(inc);
                disp(inc);

                % When inc exceeds 0, mask g with a rectangle of size barSizeDownPix with right edge at inc
                if inc > 0 
                    maskEnd = round(inc);
                    maskStart = round(inc) - obj.barSizeDownPix;

                    % If maskStart is negative, set it to 0
                    if maskStart < 0
                        maskStart = 0;
                    end

                    % If maskEnd is greater than downSampDim, set it to downSampDim
                    if maskEnd > obj.downSampDim
                        maskEnd = obj.downSampDim;
                    end

                    % Set g to 0 between maskStart and maskEnd
                    disp([maskStart, maskEnd]);
                    if maskStart ~= maskEnd
                    g(:,maskStart:maskEnd,:) = 0;
                    disp(g(:,maskStart:maskEnd,:));
                    end

                end


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
            disp('created presentation');
        end
        
        function setRawImage(obj)
            % This is a downsampled, 1D vector that will be base-input to cosine grating.
            sz = obj.canvasSize(1);
            x = linspace(-sz/2, sz/2, sz/obj.downsamp);
            obj.downSampDim = length(x);
            
            % Center the stimulus.
            rotRads=0; % hardcoded for now
            x = x + obj.centerOffset(1)*cos(rotRads);
            
            x = x / min(obj.canvasSize) * 2 * pi;
            
            % Calculate the raw grating image.
            img = x * obj.spatialFreq;
            obj.rawImage = img(1,:);
            
            if ~strcmp(obj.stageClass, 'LightCrafter')
                obj.rawImage = repmat(obj.rawImage, [1 1 3]);
            end
            disp('Set Raw Image of size:');
            disp(size(obj.rawImage));
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('backgroundMeans',obj.backgroundMeans);
            
            % Save out the cone/rod contrasts.
            epoch.addParameter('lContrast', obj.coneContrasts(1));
            epoch.addParameter('mContrast', obj.coneContrasts(2));
            epoch.addParameter('sContrast', obj.coneContrasts(3));
            epoch.addParameter('rodContrast', obj.coneContrasts(4));
            disp('Prepared epoch');
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        
    end
end


