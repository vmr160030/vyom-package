classdef noiseBackgroundMultiFlashMEA < manookinlab.protocols.ManookinLabStageProtocol
    properties
        preTime = 1000   % ms
        stimTime = 100000  % ms
        tailTime = 1000  % ms
        
        % Checkerboard background
        checkerSize = 30  % um
        backgroundMeanIntensity = 0.3  % 0-1
        backgroundContrast = [0 0.03 0.06 0.09 0.12]  % contrast for checkerboard noise
        
        % Flash parameters
        flashDuration = 50  % ms
        interFlashInterval = 1000  % ms (1 second between flashes)
        flashContrast = [-0.05 0.05]  % contrast for full-field flash
        
        numberOfAverages = uint16(1)  % number of epochs per contrast (typically 1 for long epochs)
        amp
    end
    
    properties(Hidden)
        ampType
        backgroundContrastType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        flashContrastType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        
        currentBackgroundContrast
        currentFlashContrast
        currentFlashIntensity  % computed from contrast
        stimSequence  % combinations of background and flash contrasts
        
        % Geometry
        checkerSizePix
        numXCheckers
        numYCheckers
        
        % Random seed and noise pattern
        seed
        noiseStream
        noisePattern
        
        % Flash timing (calculated from stimTime and interval)
        numberOfFlashes
        flashTimes  % start times of each flash in ms
    end
    
    methods
        function didSetRig(obj)
            didSetRig@manookinlab.protocols.ManookinLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            % Calculate number of flashes based on stimTime and interval
            obj.numberOfFlashes = floor(obj.stimTime / obj.interFlashInterval);
            
            % Generate flash times
            obj.flashTimes = (0:(obj.numberOfFlashes-1)) * obj.interFlashInterval;
            
            % Create stimulus sequence: all combinations of background and flash contrasts
            obj.stimSequence = [];
            for bc = 1:length(obj.backgroundContrast)
                for fc = 1:length(obj.flashContrast)
                    obj.stimSequence = [obj.stimSequence; ...
                        obj.backgroundContrast(bc), obj.flashContrast(fc)];
                end
            end
 
        end
        
        
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundMeanIntensity);
            
            % Create checkerboard background image
            checkerboardImage = obj.createCheckerboardNoise();
           
            % Display checkerboard as image stimulus
            checker = stage.builtin.stimuli.Image(checkerboardImage);
            checker.size = [obj.numXCheckers, obj.numYCheckers] * obj.checkerSizePix;
            checker.position = obj.canvasSize/2;
            checker.setMinFunction(GL.NEAREST);
            checker.setMagFunction(GL.NEAREST);
            p.addStimulus(checker);
            
            % Checkerboard visible during entire stim time
            checkerVisible = stage.builtin.controllers.PropertyController(checker, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(checkerVisible);
            
            % Add full-field flash rectangle
            flashRect = stage.builtin.stimuli.Rectangle();
            flashRect.position = obj.canvasSize/2;
            flashRect.size = obj.canvasSize;
            flashRect.color = obj.currentFlashIntensity;
            p.addStimulus(flashRect);
            
            % Control flash visibility with timing function
            flashVisible = stage.builtin.controllers.PropertyController(flashRect, 'visible', ...
                @(state)isFlashOn(obj, state.time));
            p.addController(flashVisible);

            function visible = isFlashOn(obj, time)
                % Check if current time is within any flash period
                visible = false;
                timeMs = time * 1e3;  % convert to ms
                
                % Only check during stim time
                if timeMs >= obj.preTime && timeMs < (obj.preTime + obj.stimTime)
                    relativeTime = timeMs - obj.preTime;
                    
                    % Check each flash window
                    for i = 1:length(obj.flashTimes)
                        flashStart = obj.flashTimes(i);
                        flashEnd = flashStart + obj.flashDuration;
                        
                        if relativeTime >= flashStart && relativeTime < flashEnd
                            visible = true;
                            break;
                        end
                    end
                end
                
            end
           
            
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
                
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
%             % Remove Amp responses on MEA rigs
%             if obj.isMeaRig
%                 amps = obj.rig.getDevices('Amp');
%                 for ii = 1:numel(amps)
%                     if epoch.hasResponse(amps{ii})
%                         epoch.removeResponse(amps{ii});
%                     end
%                     if epoch.hasStimulus(amps{ii})
%                         epoch.removeStimulus(amps{ii});
%                     end
%                 end
%             end

            % Determine current background contrast and flash contrast
            stimIndex = mod(obj.numEpochsCompleted, size(obj.stimSequence, 1)) + 1;
            obj.currentBackgroundContrast = obj.stimSequence(stimIndex, 1);
            obj.currentFlashContrast = obj.stimSequence(stimIndex, 2);
            
            % Compute flash intensity from contrast
            obj.currentFlashIntensity = obj.backgroundMeanIntensity * (1 + obj.currentFlashContrast);
           
            % Calculate geometry
            um2pix = obj.rig.getDevice('Stage').um2pix(1);
            obj.checkerSizePix = max(1, round(obj.checkerSize * um2pix));
            obj.numXCheckers = ceil(obj.canvasSize(1) / obj.checkerSizePix) + 1;
            obj.numYCheckers = ceil(obj.canvasSize(2) / obj.checkerSizePix) + 1;
            
            % Generate random seed and noise pattern for this epoch
            obj.seed = RandStream.shuffleSeed;
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            
            % Generate binary noise pattern {-1, +1}
            obj.noisePattern = 2 * (obj.noiseStream.rand(obj.numYCheckers, obj.numXCheckers) > 0.5) - 1;
            
            epoch.addParameter('currentBackgroundContrast', obj.currentBackgroundContrast);
            epoch.addParameter('currentFlashContrast', obj.currentFlashContrast);
            epoch.addParameter('currentFlashIntensity', obj.currentFlashIntensity);
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('checkerSize', obj.checkerSize);
            epoch.addParameter('numXCheckers', obj.numXCheckers);
            epoch.addParameter('numYCheckers', obj.numYCheckers);
            epoch.addParameter('numberOfFlashes', obj.numberOfFlashes);
            epoch.addParameter('flashDuration', obj.flashDuration);
            epoch.addParameter('interFlashInterval', obj.interFlashInterval);
            epoch.addParameter('flashTimes', obj.flashTimes);
           

        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages * size(obj.stimSequence, 1);
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages * size(obj.stimSequence, 1);
        end
    end
end