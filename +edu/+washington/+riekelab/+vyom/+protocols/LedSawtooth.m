classdef LedSawtooth < edu.washington.riekelab.protocols.RiekeLabProtocol
    properties
        led                             % Output LED
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 6000                   % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        contrasts = [0.05, 0.1, 0.2]       % Michelson Contrast (0 - 1) range. (Imax - Imin) / (Imax + Imin).
        temporalFrequencies = [0.61, 1.22, 2.44, 4.88, 9.76, 19.52, 39.04] % Temporal frequencies (Hz). 
        backgroundIntensity = 0.5       % Background light intensity (0-1). This is in normalized units that drives calibrated LED.
        numberOfRepeats = uint16(10)    % Number of repeats
        randomizeOrder = true          % Randomize the order of the contrasts
    end
    
    properties (Hidden)
        ledType
        ampType
        stixelSizePix
        intensity
        currentContrast
        currentFrequency
        numberOfAverages % Total number of epochs = repeats * length(contrasts) * length(temporalFrequencies) * 2 (for on/off)
        seqContrasts
        seqTemporalFrequencies
        seqRapidOnOff
        seqUniqueStim
        currentUniqueStim
        currentRapidOnOff
        n_contrasts
        n_temporal_frequencies
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
            [obj.led, obj.ledType] = obj.createDeviceNamesProperty('LED');
        end
        
        function prepareRun(obj)
            % compute number of averages
            obj.n_contrasts = length(obj.contrasts);
            obj.n_temporal_frequencies = length(obj.temporalFrequencies);
            obj.numberOfAverages = obj.numberOfRepeats * obj.n_contrasts * obj.n_temporal_frequencies * 2;

            % Call the base method.
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            device = obj.rig.getDevice(obj.led);
            device.background = symphonyui.core.Measurement(obj.backgroundIntensity, device.background.displayUnits);

            obj.organizeParameters();

            % Plot Amp1 figure for lightmeter calibrations
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
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
            n_unique_stim = length(obj.seqContrasts);
            obj.seqUniqueStim = 1:n_unique_stim;
            obj.seqUniqueStim = repmat(obj.seqUniqueStim, 1, obj.numberOfRepeats);
            obj.seqContrasts = repmat(obj.seqContrasts, 1, obj.numberOfRepeats);
            obj.seqTemporalFrequencies = repmat(obj.seqTemporalFrequencies, 1, obj.numberOfRepeats);
            obj.seqRapidOnOff = repmat(obj.seqRapidOnOff, 1, obj.numberOfRepeats);

            % Order sequences so that unique stimuli are all presented before repeating
            [obj.seqUniqueStim, order] = sort(obj.seqUniqueStim);
            obj.seqContrasts = obj.seqContrasts(order);
            obj.seqTemporalFrequencies = obj.seqTemporalFrequencies(order);
            obj.seqRapidOnOff = obj.seqRapidOnOff(order);


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
                obj.seqUniqueStim = obj.seqUniqueStim(order);
            end
        end

        function stim = createLedStimulus(obj)
            gen = edu.washington.riekelab.vyom.protocols.SawtoothGenerator();
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.contrast = obj.currentContrast;
            gen.temporalFrequency = obj.currentFrequency;
            gen.backgroundIntensity = obj.backgroundIntensity;
            % If rapid On, set polarity to -1.0, else 1.0.
            if obj.currentRapidOnOff
                gen.polarity = -1.0;
            else
                gen.polarity = 1.0;
            end
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.led).background.displayUnits;

            stim = gen.generate();
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            obj.currentContrast = obj.seqContrasts(obj.numEpochsPrepared);
            obj.currentFrequency = obj.seqTemporalFrequencies(obj.numEpochsPrepared);
            obj.currentRapidOnOff = obj.seqRapidOnOff(obj.numEpochsPrepared);
            obj.currentUniqueStim = obj.seqUniqueStim(obj.numEpochsPrepared);
            
            epoch.addStimulus(obj.rig.getDevice(obj.led), obj.createLedStimulus());
            epoch.addResponse(obj.rig.getDevice(obj.amp));

            epoch.addParameter('currentContrast', obj.currentContrast);
            epoch.addParameter('currentFrequency', obj.currentFrequency);
            epoch.addParameter('currentRapidOnOff', obj.currentRapidOnOff);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('currentUniqueStim', obj.currentUniqueStim);

            % Display current params
            disp(['Epoch ', num2str(obj.numEpochsPrepared), ' of ', num2str(obj.numberOfAverages)]);
            disp(['Stimulus contrast: ', num2str(obj.currentContrast)]);
            disp(['Temporal frequency: ', num2str(obj.currentFrequency)]);
            disp(['Rapid On/Off: ', num2str(obj.currentRapidOnOff)]);
            disp(['Unique Stim: ', num2str(obj.currentUniqueStim)]);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end
