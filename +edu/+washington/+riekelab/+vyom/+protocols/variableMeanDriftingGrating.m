classdef variableMeanDriftingGrating < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    properties
        amp    % Output amplifier
        preTime=0
        tailTime=0
        stimTime = 60000                 % Stimulus duration (ms)
        spatialContrast = 0.9            % Center grating contrast (0-1)
        orientation = 0                 % Center orientation (deg)
        barWidths = [40 150]             % Center bar width (pix)
        apertureDiameter = 300           % Surround radius (pix)
        temporalFrequency = 4.0         % Grating temporal frequency (Hz)
        spatialClass = 'sinewave'       % Grating spatial type
        meanIntensities = [0.05 0.5]       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfEpochs = uint16(30)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        phaseShift
        currentBarWidth
        currentMeanIntensity
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
               obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
%             obj.showFigure('edu.washington.riekelab.chris.figures.MeanResponseFigure',...
%                 obj.rig.getDevice(obj.amp), 'recordingType',obj.onlineAnalysis);
% %             %%%%%%%%% need a new online analysis figure
%             obj.showFigure('edu.washington.riekelab.chris.figures.varMeanDriftGratingFigure',...
%                 obj.rig.getDevice(obj.amp),'barWidths',obj.barWidths,'meanIntensities',obj.meanIntensities, ...
%                 'onlineAnalysis',obj.onlineAnalysis,'coloredBy',obj.currentMeanIntensity);
        end
        
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.stimTime) * 1e-3);
            p.setBackgroundColor(0);
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            currentBarWidthPix =  obj.rig.getDevice('Stage').um2pix(obj.currentBarWidth);

            % Create the center grating.
            switch obj.spatialClass
                case 'sinewave'
                    grate = stage.builtin.stimuli.Grating('sine');
                otherwise % Square-wave grating
                    grate = stage.builtin.stimuli.Grating('square');
            end
            grate.orientation = obj.orientation;
            grate.size = apertureDiameterPix*ones(1,2);
            grate.position = canvasSize/2;
            grate.spatialFreq = 1/(2*currentBarWidthPix); %convert from bar width to spatial freq
            grate.contrast = obj.spatialContrast;
            grate.color = 2*obj.currentMeanIntensity;
            zeroCrossings = 0:(grate.spatialFreq^-1):grate.size(1);
            offsets = zeroCrossings-grate.size(1)/2; %difference between each zero crossing and center of texture, pixels
            [shiftPix, ~] = min(offsets); % min(offsets(offsets>0)); %positive shift in pixels
            phaseShift_rad = (shiftPix/(grate.spatialFreq^-1))*(2*pi); %phaseshift in radians
            obj.phaseShift = 360*(phaseShift_rad)/(2*pi); %phaseshift in degrees
            grate.phase = obj.phaseShift; % keep contrast reversing boundary in center
            % Add the grating.
            p.addStimulus(grate);
       
            %--------------------------------------------------------------
            % Control the grating phase.
            grateController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                @(state)setDriftingGrating(obj, state.time));
            p.addController(grateController);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state) state.time < obj.stimTime* 1e-3);
            p.addController(grateVisible);
            
            % add aperture
            if obj.apertureDiameter>0
                aperture=stage.builtin.stimuli.Rectangle();
                aperture.position=canvasSize/2;
                aperture.size=[apertureDiameterPix apertureDiameterPix];
                mask=stage.core.Mask.createCircularAperture(1,1024);
                aperture.setMask(mask);
                p.addStimulus(aperture);
                aperture.color=obj.currentMeanIntensity;
            end
            % Set the drifting grating.
            function phase = setDriftingGrating(obj, time)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end
                phase = phase*180/pi + obj.phaseShift;
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = obj.stimTime/1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            meanLumIndex = numel(obj.meanIntensities)-rem(obj.numEpochsPrepared,length(obj.meanIntensities));
            barWidthIndex=  numel(obj.barWidths)-rem(((obj.numEpochsCompleted-mod(obj.numEpochsCompleted, ...
                length(obj.barWidths)))/numel(obj.barWidths)+1),numel(obj.barWidths));
            obj.currentBarWidth=obj.barWidths(barWidthIndex);
            obj.currentMeanIntensity=obj.meanIntensities(meanLumIndex);
            epoch.addParameter('currentMeanIntensity', obj.currentMeanIntensity);
            epoch.addParameter('currentBarWdith', obj.currentBarWidth);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfEpochs;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfEpochs;
        end
    end
end