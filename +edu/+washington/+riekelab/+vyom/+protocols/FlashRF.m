classdef FlashRF < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        RFmatfile = ''
        preTime = 2000                  % Stimulus leading duration (ms)
        flashTime = 50                  %
        preFlashTime = 700              %
        postFlashTime = 700
        tailTime = 500                  % Stimulus trailing duration (ms)
        gridWidth = 300                 % Width of mapping grid (microns)
        spotSizes = [0.2, 0.5, 1.0, 2.0]                % Spot sizes in fractions of RF SD
        chromaticClass = 'achromatic'   % Chromatic type
        noiseStixelSize = 60
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        spotIntensities = [0.0, 1.0]    % Spot intensities
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfRepeats = uint16(2)  % Number of repeats
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic', 'BY', 'RG'})
        gridWidthPix
        idxCell=1
        idxSpotSize=1
        idxIntensity=1
        spotSize
        intensity
        RFs
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
            obj.gridWidthPix = obj.rig.getDevice('Stage').um2pix(obj.gridWidth);
            obj.RFs = load(obj.RFmatfile, 'hull_parameters');

            % Convert RF centers and sigmas to microns then pixels
            obj.RFs.hull_parameters(:, 1:4) = obj.rig.getDevice('Stage').um2pix(obj.RFs.hull_parameters(:, 1:4)*obj.noiseStixelSize);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            disp('at start of presentation');

            spot = stage.builtin.stimuli.Ellipse(4096); % Ellipse with 4096 edges
            spot.position = obj.hull_parameters(obj.idxCell, 1:2);
            spot.radiusX = obj.hull_parameters(obj.idxCell, 3) * obj.spotSize;
            spot.radiusY = obj.hull_parameters(obj.idxCell, 4) * obj.spotSize;
            spot.color = obj.intensity;
            spot.orientation = obj.hull_parameters(obj.idxCell, 5);

            p.addStimulus(spot);
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
            @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
              
              % Cycle through Spot sizes and intensities
              obj.spotSize = obj.spotSizes(obj.idxSpotSize);
              
              % Cycle through test contrasts 10 times for adaptation before
              % switching to next pedestal flash contrast
              if mod(obj.numEpochsCompleted+1,length(obj.spotSizes)*5)==0
                 % After each cycle of test contrasts                            
                 obj.idxFlashContrast = mod(obj.idxFlashContrast, length(flashContrasts))+1;
              end
              
              
              
            obj.intensity = obj.stimContrast*obj.backgroundIntensity+obj.backgroundIntensity;
            obj.stimFlashIntensity = obj.stimFlashContrast*obj.backgroundIntensity+obj.backgroundIntensity;
            obj.testIntensity = obj.testStimContrast*obj.backgroundIntensity+obj.backgroundIntensity;
            if obj.stimContrast > 0
                flashColor = 'white';
            else
                flashColor = 'black';
            end
            
            epoch.addParameter('testSquareIdx',obj.testSquareIdx);
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
