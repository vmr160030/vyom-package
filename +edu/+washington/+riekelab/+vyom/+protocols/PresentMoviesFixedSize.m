% Plays movies...
% Note: Requires movies in .mp4 format.
classdef PresentMoviesFixedSize < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        stimTime    = 15000             % Stimulus duration in msec
        tailTime    = 250               % Trailing duration in msec
        fileFolder = 'balloons_v1';     % Folder containing videos
        backgroundIntensity = 0.5;      % 0 - 1 (corresponds to image intensities in folder)
        randomize = true;               % whether to randomize movies shown
        onlineAnalysis = 'none'
        numberOfAverages = uint16(5) % number of epochs to queue
        
    end
    
    properties (Dependent) 
        preTime
        
    end
    
    properties (Hidden)
        ampType
        src_size
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'}) 
        sequence
        imagePaths
        imageMatrix
        local_movie_directory
        stage_movie_directory
        totalRuns
        movie_name
        seed
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            disp('preparing run');
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));

            try
                movie_dir = obj.rig.getDevice('Stage').getConfigurationSetting('local_movie_directory');
                if isempty(movie_dir)
                    movie_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\movies\';
                end
            catch
                movie_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\movies\';
            end
            try
                stage_dir = obj.rig.getDevice('Stage').getConfigurationSetting('stage_movie_directory');
                if isempty(stage_dir)
                    stage_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\movies\';
                end
            catch
                stage_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\movies\';
            end
            obj.stage_movie_directory = strcat(stage_dir, obj.fileFolder);

            % General directory
            obj.local_movie_directory = strcat(movie_dir, obj.fileFolder); % General folder
            D = dir(obj.local_movie_directory);
            
            obj.imagePaths = cell(size(D,1),1);
            for a = 1:length(D)
                if sum(strfind(D(a).name,'.mp4')) > 0
                    obj.imagePaths{a,1} = D(a).name;
                end
            end
            obj.imagePaths = obj.imagePaths(~cellfun(@isempty, obj.imagePaths(:,1)), :);
            
            num_reps = ceil(double(obj.numberOfAverages)/size(obj.imagePaths,1));
            
            if obj.randomize
                obj.sequence = zeros(1,obj.numberOfAverages);
                seq = (1:size(obj.imagePaths,1));
                for ii = 1 : num_reps
                    seq = randperm(size(obj.imagePaths,1));
                    obj.sequence((ii-1)*length(seq)+(1:length(seq))) = seq;
                end
                obj.sequence = obj.sequence(1:obj.numberOfAverages);
            else
                obj.sequence = (1:size(obj.imagePaths,1))' * ones(1,num_reps);
                obj.sequence = obj.sequence(:);
            end
            disp('done preparing run');
        end

        
        function p = createPresentation(obj)
            disp('preparing presentation');
            % Stage presets
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            
            p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
            
            % Prep to display movie
            file = fullfile(obj.stage_movie_directory,obj.movie_name);
            %scene = stage.builtin.stimuli.Movie(file);
            scene = MoviePatternMode(file);
            scene.size = [obj.src_size(1), obj.src_size(2)];
            scene.position = canvasSize/2;
            scene.setPlaybackSpeed(PlaybackSpeed.FRAME_BY_FRAME); % Make sure playback is one frame at a time.
            
            % Use linear interpolation when scaling the image
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);

            % Only allow image to be visible during specific time
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
            disp('done preparing presentation');
        end
        
        function prepareEpoch(obj, epoch)
            disp('preparing epoch')
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            mov_name = obj.sequence(mod(obj.numEpochsCompleted,length(obj.sequence)) + 1);
            obj.movie_name = obj.imagePaths{mov_name,1};
            
            % weird hack to get mp4 array dimensions, videoReader didn't
            % work with codec error and Movie obj has private stuff.
            file = fullfile(obj.local_movie_directory,obj.movie_name);
            obj.src_size = VideoSource(file).size;
            
            epoch.addParameter('movieName',obj.imagePaths{mov_name,1});
            epoch.addParameter('folder',obj.local_movie_directory);
            if obj.randomize
                epoch.addParameter('seed',obj.seed);
            end
            disp(obj.src_size);
            disp('done preparing epoch');
        end
        
        function preTime = get.preTime(obj)
            preTime = 0;
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
