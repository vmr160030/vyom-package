% Protocol for testing homogeneity of display using flashing squares
classdef FlashMapperOpt < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 500                  % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        gridWidth = 2000                 % Width of mapping grid (microns). Must be larger than stixelSize
        stixelSize = 500                 % Stixel edge size (microns)
        intensity = 1.0                  % Intensity (0 - 1)
        colorChannel = 0                  % Color channel (0 for achromatic, 1 for red, 2 for green, 3 for blue)
        backgroundIntensity = 0      % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfAverages = uint16(144)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        stixelSizePix
        gridWidthPix
        positions
        position
        numChecks
        color
        optometer
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            initialGain = 10^-2;
            obj.optometer = edu.washington.riekelab.gamma.OptometerUDT350(initialGain);

            % Show optometer reading
            % obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice('Optometer'));
            obj.showFigure('edu.washington.riekelab.vyom.figures.FlashMapperOptFigure', ...
                obj.rig.getDevice('Optometer'), obj.optometer, ...
                3.37,...%obj.rig.getConfigurationSetting('micronsPerPixel'), ...
                obj.canvasSize,...
                'preTime', obj.preTime, ...
                'stimTime', obj.stimTime, ...
                'tailTime', obj.tailTime, ...
                'stixelSize', obj.stixelSize, ...
                'gridWidth', obj.gridWidth);
            
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.gridWidthPix = obj.rig.getDevice('Stage').um2pix(obj.gridWidth);

            % Assert grid width > stixel size
            assert(obj.gridWidthPix > obj.stixelSizePix, 'Grid width must be greater than or equal to stixel size.');

            % Get the number of checkers
            edgeChecks = ceil(obj.gridWidthPix / obj.stixelSizePix);
            obj.numChecks = edgeChecks^2;
            [x,y] = meshgrid(linspace(-obj.stixelSizePix*edgeChecks/2+obj.stixelSizePix/2,obj.stixelSizePix*edgeChecks/2-obj.stixelSizePix/2,edgeChecks));
            obj.positions = [x(:), y(:)];
            disp(['Total number of positions: ' num2str(size(obj.positions,1))]);
            
            % Online analysis figures
            
            
            % if ~strcmp(obj.onlineAnalysis, 'none')
            %     obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
            %         obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
            %         'sweepColor',[0,0,0],...
            %         'groupBy',{'frameRate'});
                
            %     obj.showFigure('manookinlab.figures.FlashMapperFigure', ...
            %         obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
            %         'preTime',obj.preTime,...
            %         'stimTime',obj.stimTime,...
            %         'stixelSize',obj.stixelSize,...
            %         'gridWidth',obj.gridWidth);
            % end
            
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % spot = stage.builtin.stimuli.Rectangle();
            spot = stage.builtin.stimuli.Ellipse();
            % spot.size = obj.stixelSizePix*ones(1,2);
            spot.radiusX = obj.stixelSizePix/2;
            spot.radiusY = obj.stixelSizePix/2;
            spot.position = obj.canvasSize/2 + obj.position;
            spot.orientation = 0;
            spot.color = obj.color;
            
            % Add the stimulus to the presentation.
            p.addStimulus(spot);
            
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

            % Check colorChannel input
            if obj.colorChannel == 0
                flashColor = 'white';
                obj.color = obj.intensity;
            elseif obj.colorChannel == 1
                flashColor = 'red';
                obj.color = [obj.intensity,0,0];
            elseif obj.colorChannel == 2
                flashColor = 'green';
                obj.color = [0,obj.intensity,0];
            elseif obj.colorChannel == 3
                flashColor = 'blue';
                obj.color = [0,0,obj.intensity];
            else
                error('Invalid color channel value. Must be 0 (achromatic), 1 (red), 2 (green), or 3 (blue).');
            end
            obj.position = obj.positions(mod(obj.numEpochsCompleted,length(obj.positions))+1,:);
            
            epoch.addParameter('intensity', obj.intensity);
            epoch.addParameter('numChecks',obj.numChecks);
            epoch.addParameter('position', obj.position);
            epoch.addParameter('flashColor', flashColor);
            disp(['Epoch ' num2str(obj.numEpochsCompleted+1) ': ' flashColor ' at position (' num2str(obj.position(1)) ', ' num2str(obj.position(2)) ')']);
            disp(['    Intensity: ' num2str(obj.intensity)]);
            disp(['    Color: '     num2str(obj.color)]);
            epoch.addResponse(obj.rig.getDevice('Optometer'));
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end
