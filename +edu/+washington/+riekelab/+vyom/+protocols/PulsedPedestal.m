classdef PulsedPedestal < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Stimulus leading duration (ms)
        stimTime = 50                   % Stimulus duration (ms) 16, 33, 66, 133 ms in Pokorny (1997)
        tailTime = 500                  % Stimulus trailing duration (ms)
        stixelSize = 750                % Stixel edge size (microns) 1-degree in Pokorny (1997)
        separationSize = 42             % Separation between squares 3.25arcmin ~= 0.054 degrees in Pokorny (1997)
        contrasts = [-0.6 -0.4 -0.2 0.2 0.4 0.6]                  % Contrast (0 - 1) ranges computed from those used in Pokorny (1997)
        contrastDiffs = [-0.3 -0.2 -0.1 -0.05 0.05 0.1 0.2 0.3]             % Differential contrast of test square
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        numberOfRepeats = uint16(10)     % Number of repeats
    end
    
    properties (Hidden)
        ampType
        stixelSizePix
        separationSizePix
        intensity
        testIntensity
        stimContrast        
        testStimContrast
        contrastDiff
        testSquareIdx
        numberOfAverages % Total number of epochs = repeats * length(contrasts) * length(contrastDiffs) * 4
        seqBaseContrasts
        seqContrastDiffs
        seqTestContrasts
        seqTestSquareIdxs
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
            obj.organizeParameters();
        end

        function organizeParameters(obj)
            n_base_contrasts = length(obj.contrasts);
            n_contrast_diffs = length(obj.contrastDiffs);
            obj.numberOfAverages = obj.numberOfRepeats * n_base_contrasts * n_contrast_diffs * 4;

            % Create a sequence of base contrasts, where ever value in contrasts is repeated 4 * n_contrast_diffs times
            obj.seqBaseContrasts = [];
            for i = 1:n_base_contrasts
                obj.seqBaseContrasts = [obj.seqBaseContrasts, repmat(obj.contrasts(i), 1, 4*n_contrast_diffs)];
            end

            % Create a sequence of contrast differences, where each value in contrastDiffs is repeated 4 times
            obj.seqContrastDiffs = [];
            for i = 1:n_contrast_diffs
                obj.seqContrastDiffs = [obj.seqContrastDiffs, repmat(obj.contrastDiffs(i), 1, 4)];
            end
            % now repeat the sequence of contrast differences n_base_contrasts times
            obj.seqContrastDiffs = repmat(obj.seqContrastDiffs, 1, n_base_contrasts);

            % Create a sequence of test contrasts, converting the contrast differences to actual contrasts
            obj.seqTestContrasts = obj.seqBaseContrasts + obj.seqContrastDiffs;

            % Create a sequence of test square indices, where each value in [1, 2, 3, 4] is repeated n_base_contrasts * n_contrast_diffs times
            obj.seqTestSquareIdxs = repmat([1, 2, 3, 4], 1, n_base_contrasts * n_contrast_diffs);

            % Check that sequence lengths match the number of epochs
            assert(length(obj.seqBaseContrasts) == obj.numberOfAverages, 'Number of epochs does not match sequence length');
            assert(length(obj.seqContrastDiffs) == obj.numberOfAverages, 'Number of epochs does not match sequence length');
            assert(length(obj.seqTestContrasts) == obj.numberOfAverages, 'Number of epochs does not match sequence length');
            assert(length(obj.seqTestSquareIdxs) == obj.numberOfAverages, 'Number of epochs does not match sequence length');
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            % Position of the square centers. [x, y] separationSizePix away from the canvas center.
            % Order is top-left, top-right, bottom-left, bottom-right.
            arr_pos = [[1 1];[-1 1]; [1 -1]; [-1 -1]];
            arr_delta_pos = [[0 0];[-1 0]; [0 -1]; [-1 -1]]*obj.stixelSizePix;
            
            for idx_square=1:4
                rect = stage.builtin.stimuli.Rectangle();
                rect.size = obj.stixelSizePix*ones(1,2);
                rect.position = obj.canvasSize/2 + ...
                    obj.separationSizePix*arr_pos(idx_square, :) + ...
                    arr_delta_pos(idx_square, :) + ...
                    obj.stixelSizePix*0.5*[1 1];
                rect.orientation = 0;

                if idx_square==obj.testSquareIdx                    
                    rect.color = obj.testIntensity;
                else
                    rect.color = obj.intensity;
                end
                p.addStimulus(rect);
                rectVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(rectVisible);
           end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            obj.stimContrast = obj.seqBaseContrasts(obj.numEpochsCompleted+1);
            obj.testStimContrast = obj.seqTestContrasts(obj.numEpochsCompleted+1);
            obj.intensity = obj.stimContrast*obj.backgroundIntensity+obj.backgroundIntensity;
            obj.testIntensity = obj.testStimContrast*obj.backgroundIntensity+obj.backgroundIntensity;
            obj.testSquareIdx = obj.seqTestSquareIdxs(obj.numEpochsCompleted+1);
            obj.contrastDiff = obj.seqContrastDiffs(obj.numEpochsCompleted+1);
            
            epoch.addParameter('stimContrast', obj.stimContrast);
            epoch.addParameter('testStimContrast', obj.testStimContrast);
            epoch.addParameter('testSquareIdx',obj.testSquareIdx);
            epoch.addParameter('intensity', obj.intensity);
            epoch.addParameter('testIntensity', obj.testIntensity);
            epoch.addParameter('contrastDiff', obj.contrastDiff);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
    
end
