classdef PulsedPedestal < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 100                  % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        gridWidth = 300                 % Width of mapping grid (microns)
        stixelSize = 250                % Stixel edge size (microns)
        separationSize = 14             % Separation between squares 
        contrasts = [-0.3527   -0.1083    0.1362    0.3806    0.6250]                  % Contrast (0 - 1)
        %contrastDiffs = 1.6              % Differential contrast of test square
        chromaticClass = 'achromatic'   % Chromatic type
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfAverages = uint16(144)  % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic', 'BY', 'RG'})
        stixelSizePix
        gridWidthPix
        separationSizePix
        idxContrast=1
        contrast
        intensity
        testIntensity
        stimContrast        
        testStimContrast
        positions
        position
        numChecks
        testSquareIdx
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.separationSizePix = obj.rig.getDevice('Stage').um2pix(obj.separationSize);
            obj.gridWidthPix = obj.rig.getDevice('Stage').um2pix(obj.gridWidth);

            % Get the number of checkers
            edgeChecks = ceil(obj.gridWidthPix / obj.stixelSizePix);
            obj.numChecks = edgeChecks^2;
            [x,y] = meshgrid(linspace(-obj.stixelSizePix*edgeChecks/2+obj.stixelSizePix/2,obj.stixelSizePix*edgeChecks/2-obj.stixelSizePix/2,edgeChecks));
            obj.positions = [x(:), y(:)];
            
            % Online analysis figures
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',[0,0,0],...
                    'groupBy',{'frameRate'});
                
                obj.showFigure('manookinlab.figures.FlashMapperFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime',obj.preTime,...
                    'stimTime',obj.stimTime,...
                    'stixelSize',obj.stixelSize,...
                    'gridWidth',obj.gridWidth);
            end
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            idx_square = 1;

            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.stixelSizePix*ones(1,2);
            rect.position = obj.canvasSize/2 + obj.separationSizePix*[1 1];
            rect.orientation = 0;
            if idx_square==obj.testSquareIdx
                rect.color = obj.testIntensity;
            else
                rect.color = obj.intensity;
            end
            idx_square = idx_square+1;
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
            @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
            
            
            % Add 4 rectangles
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.stixelSizePix*ones(1,2);
            rect.position = obj.canvasSize/2 + obj.separationSizePix*[-1 1]...
                + [-obj.stixelSizePix 0];
            rect.orientation = 0;
            if idx_square==obj.testSquareIdx
                rect.color = obj.testIntensity;
            else
                rect.color = obj.intensity;
            end
            idx_square = idx_square+1;
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
            @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.stixelSizePix*ones(1,2);
            rect.position = obj.canvasSize/2 + obj.separationSizePix*[1 -1]...
                + [0 -obj.stixelSizePix];
            rect.orientation = 0;
            if idx_square==obj.testSquareIdx
                rect.color = obj.testIntensity;
            else
                rect.color = obj.intensity;
            end
            idx_square = idx_square+1;
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
            @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.stixelSizePix*ones(1,2);
            rect.position = obj.canvasSize/2 + obj.separationSizePix*[-1 -1]...
                + [-obj.stixelSizePix -obj.stixelSizePix];
            rect.orientation = 0;
            if idx_square==obj.testSquareIdx
                rect.color = obj.testIntensity;
            else
                rect.color = obj.intensity;
            end
            % Add the stimulus to the presentation.
            p.addStimulus(rect);
            barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
            @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
              %obj.stimContrast = randsample(obj.contrasts, 1);
              %tol = 0.0001;
              %testContrasts = obj.contrasts(abs(obj.contrasts-obj.stimContrast)>tol);
              %obj.testStimContrast = randsample(testContrasts, 1);
              
              % Cycle through contrasts and test square contrasts
              obj.stimContrast = obj.contrasts(obj.idxContrast);
              tol = 0.0001;
              testContrasts = obj.contrasts(abs(obj.contrasts-obj.stimContrast)>tol);
              obj.testStimContrast = testContrasts(mod(obj.numEpochsCompleted,length(testContrasts))+1);
              if mod(obj.numEpochsCompleted,length(testContrasts))==1
                 obj.idxContrast = mod(obj.idxContrast+1, length(obj.contrasts))+1;
              end
              
%             if mod(obj.numEpochsCompleted,2) == 0
%                 obj.stimContrast = obj.contrast;
%             else
%                 obj.stimContrast = -obj.contrast;
%             end
            
            % Check the chromatic class
%             if strcmp(obj.chromaticClass, 'BY') % blue-yellow
%                 if obj.stimContrast > 0
%                     flashColor = 'blue';
%                     obj.intensity = [0,0,obj.contrast]*obj.backgroundIntensity + obj.backgroundIntensity;
%                 else
%                     flashColor = 'yellow';
%                     obj.intensity = [obj.contrast*ones(1,2),0]*obj.backgroundIntensity + obj.backgroundIntensity;
%                 end
%             elseif strcmp(obj.chromaticClass, 'RG') % red-green
%                 if obj.stimContrast > 0
%                     flashColor = 'red';
%                     obj.intensity = [obj.contrast,0,0]*obj.backgroundIntensity + obj.backgroundIntensity;
%                 else
%                     flashColor = 'green';
%                     obj.intensity = [0,obj.contrast,0]*obj.backgroundIntensity + obj.backgroundIntensity;
%                 end
%             else
            obj.intensity = obj.stimContrast*obj.backgroundIntensity+obj.backgroundIntensity;
            obj.testIntensity = obj.testStimContrast*obj.backgroundIntensity+obj.backgroundIntensity;
            if obj.stimContrast > 0
                flashColor = 'white';
            else
                flashColor = 'black';
            end
            %end
            
            obj.position = obj.positions(mod(floor(obj.numEpochsCompleted/2),length(obj.positions))+1,:);
            % Choose square with different intensity
            obj.testSquareIdx = randi(4);
            
            epoch.addParameter('testSquareIdx',obj.testSquareIdx);
            epoch.addParameter('numChecks',obj.numChecks);
            epoch.addParameter('position', obj.position);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('stimContrast', obj.stimContrast);
            epoch.addParameter('testStimContrast', obj.testStimContrast);
            epoch.addParameter('flashColor', flashColor);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end
