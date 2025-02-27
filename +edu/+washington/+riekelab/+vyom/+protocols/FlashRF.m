classdef FlashRF < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        RFmatfile = ''                % params.mat file with receptive field fits. Needs 'hull_parameters' [numcells x 5] matrix
        selectedCellsFile = ''            % .txt file with indices of cells to flash. Indexes hull_parameters.
        preTime = 30                  % Stimulus leading duration (ms)
        flashTime = 50                  %
        str_fit_key = 'hull_parameters'    % Key for RF fit parameters in RFmatfile
        %preFlashTime = 0              %
        %postFlashTime = 0
        tailTime = 30                  % Stimulus trailing duration (ms)
        spotSizes = [0.5, 1.0, 1.5]                % Spot sizes in fractions of RF SD
        chromaticClass = 'achromatic'   % Chromatic type
        noiseGridSize = 30
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        spotIntensities = [0.0, 1.0]    % Spot intensities
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfRepeats = uint16(2)  % Number of repeats
        % Add argument for text file list of cell indices to run through
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
        numberOfAverages
        numCells
        n_spotSizes
        n_intensities
        n_spotsPerCell
        cellsToFlash
        idxSelection=1
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
            obj.RFs = load(obj.RFmatfile, obj.str_fit_key);
            if obj.selectedCellsFile
                fileID = fopen(obj.selectedCellsFile, 'r');
                obj.cellsToFlash = fscanf(fileID, '%d');
                obj.numCells = length(obj.cellsToFlash);
                disp('Flashing # cells:');
                disp(obj.numCells);
                obj.idxSelection=1;
            else
                obj.numCells = size(obj.RFs.hull_parameters, 1);
                obj.cellsToFlash = 1:obj.numCells;
                disp('Flashing # cells:');
                disp(obj.numCells);
            end
            
            
            obj.numberOfAverages = obj.numberOfRepeats * obj.numCells * length(obj.spotSizes) * length(obj.spotIntensities);
            
            obj.n_spotSizes = length(obj.spotSizes);
            obj.n_intensities = length(obj.spotIntensities);
            obj.n_spotsPerCell = obj.n_spotSizes * obj.n_intensities;
            
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            % Convert RF centers and sigmas to microns then pixels
            obj.RFs.hull_parameters(:, 1:4) = obj.rig.getDevice('Stage').um2pix(obj.RFs.hull_parameters(:, 1:4)*obj.noiseGridSize);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            %disp('at start of presentation');

            spot = stage.builtin.stimuli.Ellipse(4096); % Ellipse with 4096 edges
            spot.position = obj.RFs.hull_parameters(obj.idxCell, 1:2);
            spot.radiusX = obj.RFs.hull_parameters(obj.idxCell, 3) * obj.spotSize;
            spot.radiusY = obj.RFs.hull_parameters(obj.idxCell, 4) * obj.spotSize;
            spot.color = obj.intensity;
            spot.orientation = obj.RFs.hull_parameters(obj.idxCell, 5);

            p.addStimulus(spot);
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
            @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Increment cell index once all spots flashed
            if mod(obj.numEpochsCompleted+1,obj.n_spotsPerCell)==0                              
               obj.idxSelection = mod(obj.idxSelection, obj.numCells)+1;
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
              
            % Cycle through Spot sizes and intensities
            obj.spotSize = obj.spotSizes(obj.idxSpotSize);
            obj.intensity = obj.spotIntensities(obj.idxIntensity);
            disp(obj.idxSelection);
            disp(obj.idxCell);
            obj.idxCell = obj.cellsToFlash(obj.idxSelection)+1;
            
            
            % Increment spot size index each epoch
            obj.idxSpotSize = mod(obj.numEpochsCompleted+1, obj.n_spotSizes)+1;
            
            % Increment intensity index when all spot sizes flashed
            if mod(obj.numEpochsCompleted+1,obj.n_spotSizes)==0                              
               obj.idxIntensity = mod(obj.idxIntensity, obj.n_intensities)+1;
            end
            
            epoch.addParameter('spotSize',obj.spotSize);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('intensity', obj.intensity);
            epoch.addParameter('idxCell', obj.idxCell);
            %disp('Made it through prepare epoch')
        end
        
        function stimTime = get.stimTime(obj)
            %stimTime = obj.preFlashTime + obj.flashTime + obj.postFlashTime;
            stimTime = obj.flashTime;

        end
        
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end