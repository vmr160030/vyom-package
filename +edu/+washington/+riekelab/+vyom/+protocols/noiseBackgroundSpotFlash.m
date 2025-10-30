classdef noiseBackgroundSpotFlash < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    properties
        preTime = 1000   % ms
        stimTime = 2000  % ms
        tailTime = 1000  % ms
        
        % Checkerboard background
        checkerSize = 30  % um
        backgroundMeanIntensity = 0.1  % 0-1
        backgroundContrast = [0 0.04 0.06 0.08 0.12]  % contrast for checkerboard noise
        onlineAnalysis = 'extracellular'
        % Flashed spot
        spotDiameter = 300  % um
        spotIntensity = [0.15]  % 0-1, intensity values for flashed spot
        
        numberOfAverages = uint16(3)  % number of epochs to queue
        amp
    end
    
    properties(Hidden)
        ampType
        backgroundContrastType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        spotIntensityType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})

        currentBackgroundContrast
        currentSpotIntensity
        stimSequence
        
        % Geometry
        checkerSizePix
        numXCheckers
        numYCheckers
        
        % Random seed and noise pattern
        seed
        noiseStream
        noisePattern
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            % Create stimulus sequence combining all parameters
            obj.stimSequence = [];
            for bc = 1:length(obj.backgroundContrast)
                for si = 1:length(obj.spotIntensity)
                    obj.stimSequence = [obj.stimSequence; ...
                        obj.backgroundContrast(bc), obj.spotIntensity(si)];
                end
            end
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.chris.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            if length(obj.stimSequence) > 1
                colors = edu.washington.riekelab.turner.utils.pmkmp(length(obj.stimSequence),'CubicYF');
            else
                colors = [0 0 0];
            end
            
            obj.showFigure('edu.washington.riekelab.chris.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'currentBackgroundContrast'},...
                'sweepColor',colors);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            % Determine current stimulus parameters
            stimIndex = mod(obj.numEpochsCompleted, size(obj.stimSequence, 1)) + 1;
            obj.currentBackgroundContrast = obj.stimSequence(stimIndex, 1);
            obj.currentSpotIntensity = obj.stimSequence(stimIndex, 2);
            
            % Calculate geometry
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            um2pix = obj.rig.getDevice('Stage').um2pix(1);
            obj.checkerSizePix = max(1, round(obj.checkerSize * um2pix));
            obj.numXCheckers = ceil(canvasSize(1) / obj.checkerSizePix) + 1;
            obj.numYCheckers = ceil(canvasSize(2) / obj.checkerSizePix) + 1;
            
            % Generate random seed and noise pattern for this epoch
            obj.seed = RandStream.shuffleSeed;
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Generate binary noise pattern {-1, +1}
            obj.noisePattern = 2 * (obj.noiseStream.rand(obj.numYCheckers, obj.numXCheckers) > 0.5) - 1;
            
            epoch.addParameter('currentBackgroundContrast', obj.currentBackgroundContrast);
            epoch.addParameter('currentSpotIntensity', obj.currentSpotIntensity);
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('checkerSize', obj.checkerSize);
            epoch.addParameter('numXCheckers', obj.numXCheckers);
            epoch.addParameter('numYCheckers', obj.numYCheckers);
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundMeanIntensity);
            
            spotDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.spotDiameter);
            
            % Create checkerboard background image
            checkerboardImage = obj.createCheckerboardNoise();
            
            % Display checkerboard as image stimulus
            checker = stage.builtin.stimuli.Image(checkerboardImage);
            checker.size = [obj.numXCheckers, obj.numYCheckers] * obj.checkerSizePix;
            checker.position = canvasSize/2;
            checker.setMinFunction(GL.NEAREST);
            checker.setMagFunction(GL.NEAREST);
            p.addStimulus(checker);
            
            % Checkerboard visible during entire presentation
            % (or you could limit it to stimTime if desired)
            
            % Add flashed spot on top
            spot = stage.builtin.stimuli.Ellipse();
            spot.position = canvasSize/2;
            spot.radiusX = spotDiameterPix/2;
            spot.radiusY = spotDiameterPix/2;
            spot.color = obj.currentSpotIntensity;
            p.addStimulus(spot);
            
            % Spot visible only during stimTime
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
        end
        
        function checkerboardImage = createCheckerboardNoise(obj)
            % Create checkerboard with contrast modulation around mean
            
            % Safe amplitude so mean ± A stays in [0,1]
            A = obj.currentBackgroundContrast * min(obj.backgroundMeanIntensity, 1 - obj.backgroundMeanIntensity);
            
            % Apply contrast to noise pattern
            checkerboard = obj.backgroundMeanIntensity + A * obj.noisePattern;
            
            % Check for out of range values and warn
            if max(checkerboard(:)) > 1 || min(checkerboard(:)) < 0
                warning('Checkerboard intensity out of range: max = %.3f, min = %.3f', ...
                    max(checkerboard(:)), min(checkerboard(:)));
            end
            
            % Convert to uint8
            checkerboardImage = uint8(checkerboard * 255);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages * size(obj.stimSequence, 1);
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages * size(obj.stimSequence, 1);
        end
    end
end