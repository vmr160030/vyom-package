classdef SteadyPedestal < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 2000                   % Stimulus leading duration (ms)
        flashTime = 50                     % Stimulus duration (ms) 16, 33, 66, 133 ms in Pokorny (1997)
        preFlashTime = 700              %
        postFlashTime = 700
        tailTime = 500                  % Stimulus trailing duration (ms)
        gridWidth = 300                 % Width of mapping grid (microns)
        stixelSize = 750                % Stixel edge size (microns) 1-degree in Pokorny (1997)
        separationSize = 42             % Separation between squares 3.25arcmin ~= 0.054 degrees in Pokorny (1997)
        contrasts = [-0.3527   -0.1083    0.1362    0.3806    0.6250]                  % Contrast (0 - 1) ranges computed from those used in Pokorny (1997)
        chromaticClass = 'achromatic'   % Chromatic type
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfAverages = uint16(50)  % Number of epochs
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
        testSquareIdx
    end
    
    properties (Dependent)
        stimTime
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
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            disp('at start of presentation');
            

            arr_pos = [[1 1];[-1 1]; [1 -1]; [-1 -1]];
            arr_delta_pos = [[0 0];[-1 0]; [0 -1]; [-1 -1]]*obj.stixelSizePix;
           for idx_square=1:4
                if idx_square==obj.testSquareIdx
%                     barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
%                     @(state)state.time >= (obj.preTime) * 1e-3 && ...
%                     state.time < (obj.preTime + obj.preFlashTime) * 1e-3 && ...
%                     state.time >= (obj.preTime + obj.preFlashTime + obj.flashTime) * 1e-3);
%                     p.addController(barVisible);
                    
                    rect = stage.builtin.stimuli.Rectangle();
                    rect.size = obj.stixelSizePix*ones(1,2);
                    rect.position = obj.canvasSize/2 + ...
                        obj.separationSizePix*arr_pos(idx_square, :) + ...
                        arr_delta_pos(idx_square, :) + ...
                        obj.stixelSizePix*0.5*[1 1];
                    rect.orientation = 0;
                    %rect.color = obj.intensity;
                    p.addStimulus(rect);
%                     if @(state)state.time >= (obj.preTime+obj.preFlashTime) * 1e-3 && ...
%                     state.time < (obj.preTime + obj.preFlashTime + obj.flashTime) * 1e-3
%                         test_sq_intensity = obj.intensity;
%                         
%                     else
%                         test_sq_intensity = obj.testIntensity;
%                     end
                    
                    barColor = stage.builtin.controllers.PropertyController(rect, 'color', ...
                        @(state)setContrast(obj, state.time-obj.preTime*1e-3));
%                     %barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
%                     %@(state)state.time >= 0 && state.time < (obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
                    p.addController(barColor);
                    %barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                    %@(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                    %p.addController(barVisible);
                else
                    rect = stage.builtin.stimuli.Rectangle();
                    rect.size = obj.stixelSizePix*ones(1,2);
                    rect.position = obj.canvasSize/2 + ...
                        obj.separationSizePix*arr_pos(idx_square, :) + ...
                        arr_delta_pos(idx_square, :) + ...
                        obj.stixelSizePix*0.5*[1 1];
                    rect.orientation = 0;
                    rect.color = obj.intensity;
                    p.addStimulus(rect);
                    %barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                    %@(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                    %barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                    %@(state)state.time >= obj.preTime && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                    %p.addController(barVisible);
                end
           end
           
           function c = setContrast(obj, time)
                if time >= obj.preFlashTime * 1e-3 && ...
                     time < (obj.preFlashTime + obj.flashTime) * 1e-3
                    c = obj.testIntensity;
                else
                    c = obj.intensity;
                end
            end
%             disp('completed presentation')
%             keyboard;
           
            
%             if idx_square==obj.testSquareIdx
%                 rect.color = obj.testIntensity;
%             else
%                 rect.color = obj.intensity;
%             end
%             % Add the stimulus to the presentation.
%             p.addStimulus(rect);
%             barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
%             @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
%             p.addController(barVisible);
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
              % Cycle through test contrasts 10 times for adaptation before
              % switching to next pedestal contrast
              if mod(obj.numEpochsCompleted+1,length(testContrasts)*10)==0
                 obj.idxContrast = mod(obj.idxContrast, length(obj.contrasts))+1;
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
            
            %obj.position = obj.positions(mod(floor(obj.numEpochsCompleted/2),length(obj.positions))+1,:);
            % Choose square with different intensity
            obj.testSquareIdx = randi(4);
            
            epoch.addParameter('testSquareIdx',obj.testSquareIdx);
            %epoch.addParameter('numChecks',obj.numChecks);
            %epoch.addParameter('position', obj.position);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('stimContrast', obj.stimContrast);
            epoch.addParameter('testStimContrast', obj.testStimContrast);
            epoch.addParameter('flashColor', flashColor);
            disp('Made it through prepare epoch')
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.preFlashTime + obj.flashTime + obj.postFlashTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end
