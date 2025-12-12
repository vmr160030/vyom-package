classdef FlashMapperOptFigure < symphonyui.core.FigureHandler
    properties (SetAccess = private)
        device
        preTime
        stimTime
        tailTime
        stixelSize
        gridWidth
    end

    properties (Access = private)
        axesHandles
        traceHandles
        heatmapHandle
        traces
        positions
        posIdxMap
        xvals
        yvals
        heatmapVals
        edgeChecks
        legendEntries
        sampleRate
    end

    methods
        function obj = FlashMapperOptFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('preTime', 250, @isnumeric);
            ip.addParameter('stimTime', 500, @isnumeric);
            ip.addParameter('tailTime', 500, @isnumeric);
            ip.addParameter('stixelSize', 500, @isnumeric);
            ip.addParameter('gridWidth', 2000, @isnumeric);
            ip.parse(varargin{:});

            obj.device = device;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.tailTime = ip.Results.tailTime;
            obj.stixelSize = ip.Results.stixelSize;
            obj.gridWidth = ip.Results.gridWidth;

            obj.edgeChecks = ceil(obj.gridWidth / obj.stixelSize);
            [obj.xvals, obj.yvals] = meshgrid( ...
                linspace(-obj.stixelSize*obj.edgeChecks/2+obj.stixelSize/2, ...
                         obj.stixelSize*obj.edgeChecks/2-obj.stixelSize/2, ...
                         obj.edgeChecks));
            obj.positions = [obj.xvals(:), obj.yvals(:)];
            obj.posIdxMap = containers.Map('KeyType','char','ValueType','int32');
            obj.traces = {};
            obj.heatmapVals = nan(obj.edgeChecks, obj.edgeChecks);
            obj.legendEntries = {};
            obj.createUi();
        end

        function createUi(obj)
            % 2x1 grid: top for traces, bottom for heatmap
            obj.axesHandles(1) = subplot(2,1,1, 'Parent', obj.figureHandle);
            hold(obj.axesHandles(1), 'on');
            ylabel(obj.axesHandles(1), 'Response');
            title(obj.axesHandles(1), 'All traces by position');
            obj.axesHandles(2) = subplot(2,1,2, 'Parent', obj.figureHandle);
            obj.heatmapHandle = imagesc('Parent', obj.axesHandles(2), ...
                'XData', unique(obj.xvals), 'YData', unique(obj.yvals), ...
                'CData', obj.heatmapVals);
            axis(obj.axesHandles(2), 'image');
            colorbar(obj.axesHandles(2));
            xlabel(obj.axesHandles(2), 'X position (\mum)');
            ylabel(obj.axesHandles(2), 'Y position (\mum)');
            title(obj.axesHandles(2), 'Peak - baseline heatmap');
        end

        function clear(obj)
            cla(obj.axesHandles(1));
            cla(obj.axesHandles(2));
            obj.traces = {};
            obj.heatmapVals(:) = nan;
            obj.legendEntries = {};
            set(obj.heatmapHandle, 'CData', obj.heatmapVals);
        end

        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                return;
            end
            response = epoch.getResponse(obj.device);
            [data, units] = response.getData();
            obj.sampleRate = response.sampleRate.quantityInBaseUnits;

            % Get position
            pos = epoch.parameters('position');
            posKey = sprintf('%.1f,%.1f', pos(1), pos(2));
            % Find index in grid
            [~, idx] = min(sum((obj.positions - pos).^2,2));
            [row, col] = ind2sub(size(obj.xvals), idx);

            % Time vector
            nPts = numel(data);
            t = (0:nPts-1)/obj.sampleRate*1000; % ms

            % Plot trace
            color = lines(numel(obj.positions));
            if ~isKey(obj.posIdxMap, posKey)
                obj.posIdxMap(posKey) = length(obj.traces) + 1;
                obj.legendEntries{end+1} = sprintf('(%g,%g)', pos(1), pos(2));
            end
            traceIdx = obj.posIdxMap(posKey);
            h = plot(obj.axesHandles(1), t, data, 'Color', color(traceIdx,:), 'DisplayName', obj.legendEntries{traceIdx});
            obj.traces{traceIdx} = h;

            % Compute baseline and peak
            prePts = round(obj.preTime/1000 * obj.sampleRate);
            stimStart = prePts + 1;
            stimEnd = stimStart + round(obj.stimTime/1000 * obj.sampleRate) - 1;
            baseline = mean(data(1:prePts));
            peak = max(data(stimStart:stimEnd));
            obj.heatmapVals(row, col) = peak - baseline;

            % Update heatmap
            set(obj.heatmapHandle, 'CData', obj.heatmapVals);

            % Update legend
            legend(obj.axesHandles(1), obj.legendEntries, 'Interpreter', 'none', 'Location', 'bestoutside');
        end
    end
end