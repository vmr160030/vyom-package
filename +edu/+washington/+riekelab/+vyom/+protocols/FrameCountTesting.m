classdef FrameCountTesting < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                         % Output amplifier
        preTime     = 250           % Pre time in ms
        stimTime    = 1000           % Stimulus time in ms
        tailTime    = 250           % Tail time in ms
        backgroundIntensity = 0.5; % 0 - 1 (corresponds to image intensities in folder)
        c1 = 1;
        c2 = 0;
        onlineAnalysis = 'none'     % Type of online analysis
        numberOfAverages = 3;
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'}) 
        backgroundImage
        directory
        preFrames
        stimFrames
        tailFrames
        pairIndex
        image_dir
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            if ~obj.isMeaRig
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            end

            % Calculate the number of pre, stim, and tail frames.
            obj.preFrames = round(obj.preTime * 1e-3 * 60);
            obj.stimFrames = round(obj.stimTime * 1e-3 * 60);
            obj.tailFrames = round(obj.tailTime * 1e-3 * 60);

            disp(['preFrames: ', num2str(obj.preFrames)]);
            disp(['stimFrames: ', num2str(obj.stimFrames)]);
            disp(['tailFrames: ', num2str(obj.tailFrames)]);
        end

        
        function p = createPresentation(obj)
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display image
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = canvasSize;
            rect.position = canvasSize/2;
            rect.orientation = 0;

            % Only allow rectangle to be visible after frame index >= preFrames and < (preFrames + stimFrames)
            p.addStimulus(rect);
            rectVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.frame >= obj.preFrames && state.frame < (obj.preFrames + obj.stimFrames));
            p.addController(rectVisible);

            % Control intensity.
            rectColor = stage.builtin.controllers.PropertyController(rect, ...
                'color', @(state)setColor(obj, state.frame-obj.preFrames));
            % Add the controller.
            p.addController(rectColor);

            % setColor to alternate between c1 and c2 every frame
            function c = setColor(obj, frame)
                if mod(frame, 2) == 0
                    c = obj.c1;
                else
                    c = obj.c2;
                end
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Remove the Amp responses if it's an MEA rig.
            if obj.isMeaRig
                amps = obj.rig.getDevices('Amp');
                for ii = 1:numel(amps)
                    if epoch.hasResponse(amps{ii})
                        epoch.removeResponse(amps{ii});
                    end
                    if epoch.hasStimulus(amps{ii})
                        epoch.removeStimulus(amps{ii});
                    end
                end
            end

            epoch.addParameter('preFrames', obj.preFrames);
            epoch.addParameter('stimFrames', obj.stimFrames);
            epoch.addParameter('tailFrames', obj.tailFrames);
            epoch.addParameter('c1', obj.c1);
            epoch.addParameter('c2', obj.c2);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
            end
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
