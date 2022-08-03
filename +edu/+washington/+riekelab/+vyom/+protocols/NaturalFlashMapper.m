classdef NaturalFlashMapper < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 500                  % Stimulus duration (ms)
        tailTime = 500                  % Stimulus trailing duration (ms)
        gridWidth = 300                 % Width of mapping grid (microns)
        stixelSize = 50                 % Stixel edge size (microns)
        contrast = 1.0                  % Contrast (0 - 1)
        chromaticClass = 'achromatic'   % Chromatic type
        backgroundIntensity = 0.15       % Background light intensity (0-1)
        backgroundIntensityRange = 0.05  % Keep images w/in this range of background intensity
        onlineAnalysis = 'extracellular' % Online analysis type.
        numberOfAverages = 5            % Number of runs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        chromaticClassType = symphonyui.core.PropertyType('char','row',{'achromatic', 'BY', 'RG'})
        stixelSizePix
        gridWidthPix
        intensity
        stimContrast
        positions
        position
        numChecks
        selectedImgFilename
        selectedImgIndex
        path
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.gridWidthPix = obj.rig.getDevice('Stage').um2pix(obj.gridWidth);
            
            monitor_size = obj.rig.getDevice('Stage').getCanvasSize();     

            % Load natural images
            obj.path = 'C:\Users\Fred\Documents\vyom-package\+edu\+washington\+riekelab\+vyom\+Doves\+Images\';            
            ls_imgs = dir(obj.path);            
            avg_intensity = zeros(length(ls_imgs), 1);
            obj.selectedImgFilename = cell(length(ls_imgs), 1);

            for idx=1:size(ls_imgs, 1)
                filename = ls_imgs(idx).name;
                if contains(filename, '.iml')
                    picture = edu.washington.riekelab.vyom.utils.read_vanhat_foranalysis(strcat(obj.path, filename));
                    cropped_pic = picture(1:monitor_size(1), 1:monitor_size(2));
                    avg_intensity(idx) = mean(cropped_pic(:))/255; % 8bit to 0-1 intensity range
                    obj.selectedImgFilename{idx, 1} = filename;
                end
            end

            img_index = avg_intensity<(obj.backgroundIntensity + obj.backgroundIntensityRange) & ...
                avg_intensity>(obj.backgroundIntensity - obj.backgroundIntensityRange);
            obj.selectedImgFilename=obj.selectedImgFilename(img_index);
            obj.selectedImgIndex=1;

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
            monitor_size = obj.rig.getDevice('Stage').getCanvasSize();
            
            filename = obj.selectedImgFilename{obj.selectedImgIndex};
            picture = edu.washington.riekelab.vyom.utils.read_vanhat_foranalysis(strcat(obj.path, filename));
            cropped_pic = picture(1:monitor_size(1), 1:monitor_size(2));

            % Prep to display image
            scene = stage.builtin.stimuli.Image(uint8(cropped_pic));
            scene.size = [canvasSize(1),canvasSize(2)];
            scene.position = canvasSize/2;
            
            p.addStimulus(scene);
            
            barVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barVisible);
            
%             rect = stage.builtin.stimuli.Rectangle();
%             rect.size = obj.stixelSizePix*ones(1,2);
%             rect.position = obj.canvasSize/2 + obj.position;
%             rect.orientation = 0;
%             rect.color = obj.backgroundIntensity;
            
            % Add the stimulus to the presentation.
%             p.addStimulus(rect);
            
%             barVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
%                 @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
%             p.addController(barVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

            obj.position = obj.positions(mod(floor(obj.numEpochsCompleted/2),length(obj.positions))+1,:);
            
            epoch.addParameter('numChecks',obj.numChecks);
            epoch.addParameter('position', obj.position);
            epoch.addParameter('imageID', obj.selectedImgFilename{obj.selectedImgIndex});

            obj.selectedImgIndex = mod(obj.selectedImgIndex, obj.numberOfAverages) + 1;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < (length(obj.selectedImgFilename) .* obj.numberOfAverages);
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < (length(obj.selectedImgFilename) .* obj.numberOfAverages);
        end
    end
    
end
