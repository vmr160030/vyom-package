classdef CircleSpatialGap < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 1000                  % Pre-stimulus time (ms)
        stimTime = 106                   % Stimulus duration (ms)
        tailTime = 500                 % Post-stimulus time (ms)
        circleRadiusUm = 150            % Circle radius (microns)
        strokeWidthUm = 50             % Stroke width (microns)
        spatialGapsUm = [0, 50, 200]        % Spatial gap sizes (microns)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        numberOfRepeats = uint16(10)    % Number of repeats
        randomizeOrder = true           % Randomize the order of the gaps
    end
    
    properties (Hidden)
        ampType
        circleRadiusPix
        boundingBoxPix
        strokeWidthPix
        currentGapUm
        currentGapPix
        currentGapAngle
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
            % Bounding box will be 2x the diameter of the circle
            obj.boundingBoxPix = 2*2*obj.circleRadiusPix;
            obj.strokeWidthPix = obj.rig.getDevice('Stage').um2pix(obj.strokeWidthUm);

            disp(['Circle radius: ', num2str(obj.circleRadiusUm), ' um']);
            disp(['Stroke width: ', num2str(obj.strokeWidthUm), ' um']);
            disp(['Circle radius in pixels: ', num2str(obj.circleRadiusPix), ' pixels']);
            disp(['Stroke width in pixels: ', num2str(obj.strokeWidthPix), ' pixels']);
            disp(['Bounding box: ', num2str(obj.boundingBoxPix), ' pixels']);
            disp(['Number of averages: ', num2str(obj.numberOfAverages)]);
            obj.organizeParameters();
        end

        function organizeParameters(obj)
            if obj.randomizeOrder
                obj.seqSpatialGaps = obj.spatialGapsUm(randperm(obj.n_spatial_gaps));
            else
                obj.seqSpatialGaps = obj.spatialGapsUm;
            end
            
            obj.seqContrasts = ones(1, obj.n_spatial_gaps); % Increment
            obj.seqContrasts = [obj.seqContrasts, -1*ones(1, obj.n_spatial_gaps)]; % Decrement
            
            % Repeat twice for on/off
            obj.seqSpatialGaps = repmat(obj.seqSpatialGaps, 1, 2);            
            
            obj.seqSpatialGaps = repmat(obj.seqSpatialGaps, 1, obj.numberOfRepeats);
            obj.seqContrasts = repmat(obj.seqContrasts, 1, obj.numberOfRepeats);
        end

        function imageMatrix = computeImage(obj)
            % Create a hollow circle with a gap
            outerRadius = obj.circleRadiusPix;
            innerRadius = outerRadius - obj.strokeWidthPix;
            
            [X, Y] = meshgrid(1:2*outerRadius, 1:2*outerRadius);
            X = X - outerRadius;
            Y = Y - outerRadius;
            outerCircle = sqrt(X.^2 + Y.^2) <= outerRadius;
            innerCircle = sqrt(X.^2 + Y.^2) <= innerRadius;
            hollowCircle = outerCircle & ~innerCircle;
            
            % Create the gap centered on the right edge of the circle
            halfGapAngle = obj.currentGapAngle / 2;
            th = atan2(Y, X); % map to [-pi, pi]
            % Shift mapping to [0, 2pi]
            th = th + pi;
            
            gapMask = th < halfGapAngle | th > (2*pi - halfGapAngle);
            hollowCircle(gapMask) = 0;
            
            % Convert to image matrix
            imageMatrix = obj.backgroundIntensity * ones(2*outerRadius, 2*outerRadius); % Background intensity
            imageMatrix(hollowCircle) = obj.currentContrast*obj.backgroundIntensity + obj.backgroundIntensity; % Circle intensity

            % Convert to uint8
            imageMatrix = uint8(255*imageMatrix);
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            % Define center positions of 4 images
            positions = [obj.canvasSize(1)/2 - obj.boundingBoxPix/2, obj.canvasSize(2)/2 - obj.boundingBoxPix/2; ...
                         obj.canvasSize(1)/2 - obj.boundingBoxPix/2, obj.canvasSize(2)/2 + obj.boundingBoxPix/2;...
                         obj.canvasSize(1)/2 + obj.boundingBoxPix/2, obj.canvasSize(2)/2 - obj.boundingBoxPix/2; ...
                         obj.canvasSize(1)/2 + obj.boundingBoxPix/2, obj.canvasSize(2)/2 + obj.boundingBoxPix/2];

            % Create 2 circle stimulus using Image
            for k = 1:4
                image = stage.builtin.stimuli.Image(obj.computeImage());
                image.size = [obj.circleRadiusPix * 2, obj.circleRadiusPix * 2];
                image.position = positions(k, :);
            
                % Add the circle stimulus to the presentation
                p.addStimulus(image);
                
                % Create controllers for the stimuli visibility
                imageVisible = stage.builtin.controllers.PropertyController(image, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(imageVisible);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            obj.currentGapUm = obj.seqSpatialGaps(obj.numEpochsCompleted+1);
            obj.currentContrast = obj.seqContrasts(obj.numEpochsCompleted+1);

            % Compute the angle corresponding to the gap size
            obj.currentGapPix = obj.rig.getDevice('Stage').um2pix(obj.currentGapUm);
            circumferencePix = 2 * pi * obj.circleRadiusPix;
            obj.currentGapAngle = (obj.currentGapPix / circumferencePix) * 2 * pi;
            epoch.addParameter('currentGapUm', obj.currentGapUm);
            epoch.addParameter('currentGapPix', obj.currentGapPix);
            epoch.addParameter('currentContrast', obj.currentContrast);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('circleRadiusPix', obj.circleRadiusPix);
            epoch.addParameter('strokeWidthPix', obj.strokeWidthPix);
            epoch.addParameter('currentGapAngle', obj.currentGapAngle);
            % display all current params
            disp(['Epoch ', num2str(obj.numEpochsCompleted+1), ' of ', num2str(obj.numberOfAverages)]);
            disp(['Current gap: ', num2str(obj.currentGapUm)]);
            disp(['Current gap angle: ', num2str(obj.currentGapAngle), ' radians']);
            disp(['Current gap angle: ', num2str(rad2deg(obj.currentGapAngle)), ' degrees']);
            disp(['Current contrast: ', num2str(obj.currentContrast)]);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        

    end
end