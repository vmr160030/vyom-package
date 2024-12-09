classdef CircleGapStimulus < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 1000                  % Pre-stimulus time (ms)
        stimTime = 80                   % Stimulus duration (ms)
        tailTime = 1000                 % Post-stimulus time (ms)
        circleRadiusUm = 400            % Circle radius (microns)
        strokeWidthUm = 100             % Stroke width (microns)
        spatialGapsUm = [0, 200]        % Spatial gap sizes (microns)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        numberOfRepeats = uint16(10)    % Number of repeats
        randomizeOrder = true           % Randomize the order of the gaps
    end
    
    properties (Hidden)
        ampType
        circleRadiusPix
        strokeWidthPix
        currentGap
        currentContrast
        numberOfAverages % Total number of epochs = repeats * length(spatialGaps) * 2 (for on/off)
        seqSpatialGaps
        seqContrasts
        n_spatial_gaps
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            obj.n_spatial_gaps = length(obj.spatialGapsUm);
            obj.numberOfAverages = obj.numberOfRepeats * obj.n_spatial_gaps * 2;
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            obj.circleRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.circleRadiusUm);
            obj.strokeWidthPix = obj.rig.getDevice('Stage').um2pix(obj.strokeWidthUm);
            disp(['Number of averages: ', num2str(obj.numberOfAverages)]);
            obj.organizeParameters();
        end

        function organizeParameters(obj)
            if obj.randomizeOrder
                obj.seqSpatialGaps = obj.spatialGapsUm(randperm(obj.n_spatial_gaps));
            else
                obj.seqSpatialGaps = obj.spatialGapsUm;
            end
            % Repeat twice for on/off
            obj.seqContrasts = [1, 0];
            obj.seqContrasts = repmat(obj.seqContrasts, 1, obj.n_spatial_gaps);
            obj.seqSpatialGaps = repmat(obj.seqSpatialGaps, 1, 2);            
            
            obj.seqSpatialGaps = repmat(obj.seqSpatialGaps, 1, obj.numberOfRepeats);
            obj.seqContrasts = repmat(obj.seqContrasts, 1, obj.numberOfRepeats);
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(0.5);
            
            % Create the circle stimulus using Image
            circle = stage.builtin.stimuli.Image();
            circle.size = [obj.circleRadiusPix * 2, obj.circleRadiusPix * 2];
            circle.position = [obj.canvasSize(1)/2, obj.canvasSize(2)/2];
            
            % Add the circle stimulus to the presentation
            p.addStimulus(circle);
            
            % Create a PropertyController for the imageMatrix
            imageController = stage.builtin.controllers.PropertyController(circle, 'imageMatrix', ...
                @(state)setFrames(obj, state.time - obj.preTime * 1e-3));
            p.addController(imageController);
            
            % Create controllers for the stimuli visibility
            circleVisible = stage.builtin.controllers.PropertyController(circle, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(circleVisible);
            function imageMatrix = setFrames(obj, time)
                % Create a hollow circle with a gap
                outerRadius = obj.circleRadiusPix;
                innerRadius = outerRadius - obj.strokeWidthPix;
                gapSizePix = obj.rig.getDevice('Stage').um2pix(obj.currentGap);
                
                % Compute the angle corresponding to the gap size
                circumference = 2 * pi * outerRadius;
                gapAngle = (gapSizePix / circumference) * 2 * pi;
                halfGapAngle = gapAngle / 2;
                
                [X, Y] = meshgrid(1:2*outerRadius, 1:2*outerRadius);
                X = X - outerRadius;
                Y = Y - outerRadius;
                outerCircle = sqrt(X.^2 + Y.^2) <= outerRadius;
                innerCircle = sqrt(X.^2 + Y.^2) <= innerRadius;
                hollowCircle = outerCircle & ~innerCircle;
                
                % Create the gap centered on the right edge of the circle
                gapMask = atan2(Y, X) > -halfGapAngle & atan2(Y, X) < halfGapAngle;
                hollowCircle(gapMask) = 0;
                
                % Convert to image matrix
                imageMatrix = obj.backgroundIntensity * ones(2*outerRadius, 2*outerRadius); % Background intensity
                imageMatrix(hollowCircle) = obj.currentContrast*obj.backgroundIntensity + obj.backgroundIntensity; % Circle intensity

                % Convert to uint8
                imageMatrix = uint8(255*imageMatrix);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.currentGap = obj.seqSpatialGaps(obj.numEpochsCompleted+1);
            obj.currentContrast = obj.seqContrasts(obj.numEpochsCompleted+1);
            epoch.addParameter('currentGap', obj.currentGap);
            epoch.addParameter('currentContrast', obj.currentContrast);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        

    end
end