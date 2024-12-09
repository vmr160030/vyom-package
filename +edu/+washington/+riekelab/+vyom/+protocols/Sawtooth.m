classdef Sawtooth < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 6000                   % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        stixelSizeUm = 1000               % Stixel edge size (microns)
        contrasts = [0.05, 0.1, 0.2]       % Michelson Contrast (0 - 1) range. (Imax - Imin) / (Imax + Imin).
        temporalFrequencies = [0.61, 1.22, 2.44, 4.88, 9.76] % Temporal frequencies (Hz). REMEMBER TO AVOID ALIASING BY REMAINING BELOW REFRESHRATE/2.
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        numberOfRepeats = uint16(10)    % Number of repeats
        randomizeOrder = true          % Randomize the order of the contrasts
    end
    
    properties (Hidden)
        ampType
        stixelSizePix
        intensity
        currentContrast
        currentFrequency
        numberOfAverages % Total number of epochs = repeats * length(contrasts) * length(temporalFrequencies) * 2 (for on/off)
        seqContrasts
        seqTemporalFrequencies
        seqRapidOnOff
        currentRapidOnOff
        n_contrasts
        n_temporal_frequencies
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            obj.n_contrasts = length(obj.contrasts);
            obj.n_temporal_frequencies = length(obj.temporalFrequencies);
            obj.numberOfAverages = obj.numberOfRepeats * obj.n_contrasts * obj.n_temporal_frequencies * 2;
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSizeUm);
            disp(['Number of averages: ', num2str(obj.numberOfAverages)]);
            disp(['Stixel size (um): ', num2str(obj.stixelSizeUm)]);
            disp(['Stixel size (pix): ', num2str(obj.stixelSizePix)]);
            obj.organizeParameters();
        end

        function organizeParameters(obj)
            % Create a sequence of contrasts, where each contrast set is repeated n_temporal_frequencies times
            obj.seqContrasts = repmat(obj.contrasts, 1, obj.n_temporal_frequencies);

            % Create a sequence of temporal frequencies, where each value in temporalFrequencies is repeated n_contrasts times
            obj.seqTemporalFrequencies = [];
            for i = 1:obj.n_temporal_frequencies
                obj.seqTemporalFrequencies = [obj.seqTemporalFrequencies, obj.temporalFrequencies(i)*ones(1, obj.n_contrasts)];
            end

            % Repeat twice, and create a sequence of on/off
            obj.seqContrasts = repmat(obj.seqContrasts, 1, 2);
            obj.seqTemporalFrequencies = repmat(obj.seqTemporalFrequencies, 1, 2);
            obj.seqRapidOnOff = [true(1, length(obj.seqContrasts)/2), false(1, length(obj.seqContrasts)/2)];

            % Repeat each by the number of repeats
            obj.seqContrasts = repmat(obj.seqContrasts, 1, obj.numberOfRepeats);
            obj.seqTemporalFrequencies = repmat(obj.seqTemporalFrequencies, 1, obj.numberOfRepeats);
            obj.seqRapidOnOff = repmat(obj.seqRapidOnOff, 1, obj.numberOfRepeats);

            % Check that sequence lengths match the number of epochs
            assert(length(obj.seqContrasts) == obj.numberOfAverages, 'Number of epochs does not match contrast sequence length');
            assert(length(obj.seqTemporalFrequencies) == obj.numberOfAverages, 'Number of epochs does not match tfreq sequence length');
            assert(length(obj.seqRapidOnOff) == obj.numberOfAverages, 'Number of epochs does not match on/off sequence length');

            if obj.randomizeOrder
                % Randomize the order of the contrasts
                order = randperm(obj.numberOfAverages);
                obj.seqContrasts = obj.seqContrasts(order);
                obj.seqTemporalFrequencies = obj.seqTemporalFrequencies(order);
                obj.seqRapidOnOff = obj.seqRapidOnOff(order);
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.stixelSizePix*ones(1,2);
            rect.position = obj.canvasSize/2;
            rect.orientation = 0;
            p.addStimulus(rect);
            rectVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(rectVisible);

            % Intensity controller
            rectIntensity = stage.builtin.controllers.PropertyController(rect, 'color',...
                @(state)getIntensity(obj, state.time - obj.preTime*1e-3));
            p.addController(rectIntensity);

            function i = getIntensity(obj, time)
                if time >= 0 && time <= obj.stimTime*1e-3
                    % Compute sawtooth wave bw -1 and 1, in rapid off mode
                    intensity = 2 * (time * obj.currentFrequency - floor(time * obj.currentFrequency + 0.5));

                    % If currently Rapid On, invert the sawtooth wave
                    if obj.currentRapidOnOff
                        intensity = intensity * -1.0;
                    end

                    % Amplitude is Michelson contrast * background intensity
                    amplitude = obj.currentContrast * obj.backgroundIntensity;

                    % Intensity is background intensity + amplitude * sawtooth wave
                    i = obj.backgroundIntensity + amplitude * intensity;
                else
                    i = obj.backgroundIntensity;
                end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            obj.currentContrast = obj.seqContrasts(obj.numEpochsCompleted+1);
            obj.currentFrequency = obj.seqTemporalFrequencies(obj.numEpochsCompleted+1);
            obj.currentRapidOnOff = obj.seqRapidOnOff(obj.numEpochsCompleted+1);
            
            epoch.addParameter('currentContrast', obj.currentContrast);
            epoch.addParameter('currentFrequency', obj.currentFrequency);
            epoch.addParameter('currentRapidOnOff', obj.currentRapidOnOff);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);

            % Display current params
            disp(['Epoch ', num2str(obj.numEpochsCompleted+1), ' of ', num2str(obj.numberOfAverages)]);
            disp(['Stimulus contrast: ', num2str(obj.currentContrast)]);
            disp(['Temporal frequency: ', num2str(obj.currentFrequency)]);
            disp(['Rapid On/Off: ', num2str(obj.currentRapidOnOff)]);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end
