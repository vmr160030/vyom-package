classdef SawtoothGenerator < symphonyui.core.StimulusGenerator
    % Generates a single rectangular pulse stimulus.
    
    properties
        preTime     % Leading duration (ms)
        stimTime    % Pulse duration (ms)
        tailTime    % Trailing duration (ms)
        contrast   % Michelson Contrast (0 - 1) range. (Imax - Imin) / (Imax + Imin).
        temporalFrequency % Temporal frequency (Hz)
        backgroundIntensity        % Background light intensity (0-1). This is in normalized units that drives calibrated LED. 
        polarity   % On/Off multiplier. +1.0 is rapid off, -1.0 is rapid on.
        sampleRate  % Sample rate of generated stimulus (Hz)
        units       % Units of generated stimulus
    end
    
    methods
        
        function obj = SawtoothGenerator(map)
            if nargin < 1
                map = containers.Map();
            end
            obj@symphonyui.core.StimulusGenerator(map);
        end
        
    end
    
    methods (Access = protected)
        
        function s = generateStimulus(obj)
            import Symphony.Core.*;
            
            timeToPts = @(t)(round(t / 1e3 * obj.sampleRate));
            
            prePts = timeToPts(obj.preTime);
            stimPts = timeToPts(obj.stimTime);
            tailPts = timeToPts(obj.tailTime);

            % Amplitude is Michelson contrast * background intensity
            amplitude = obj.contrast * obj.backgroundIntensity;
            
            time = (0:stimPts-1) / obj.sampleRate;
            
            % Compute sawtooth wave bw -1 and 1
            sawtooth = 2 * (time * obj.temporalFrequency - floor(time * obj.temporalFrequency + 0.5));
            sawtooth = obj.polarity * sawtooth;
            
            % Final waveform is background + amplitude * sawtooth
            sawtooth = obj.backgroundIntensity + amplitude * sawtooth;
            
            % Set background and stimulus points.
            data = ones(1, prePts + stimPts + tailPts) * obj.backgroundIntensity;
            data(prePts + 1:prePts + stimPts) = sawtooth;
            
            parameters = obj.dictionaryFromMap(obj.propertyMap);
            %measurements = Measurement.FromArray(data, obj.units);
            %rate = Measurement(obj.sampleRate, 'Hz');
            %output = OutputData(measurements, rate);
            
            cobj = RenderedStimulus(class(obj), parameters);%, output);
            s = symphonyui.core.Stimulus(cobj);
        end
        
    end
    
end