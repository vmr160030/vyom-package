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
        xvals
        yvals
        peakMinusBaseline
        edgeChecks
        positionList
    end

    methods
        function obj = FlashMapperOptFigure(device, varargin)
            ip = inputParser();
            ip.addParameter('preTime', 0.0, @(x)isfloat(x));
            ip.addParameter('stimTime', 0.0, @(x)isfloat(x));
            ip.addParameter('tailTime', 0.0, @(x)isfloat(x));
            ip.addParameter('stixelSize', 50.0, @(x)isfloat(x));
            ip.addParameter('gridWidth', 300.0, @(x)isfloat(x));
            ip.parse(varargin{:});

            obj.device = device;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.tailTime = ip.Results.tailTime;
            obj.stixelSize = ip.Results.stixelSize;
            obj.gridWidth = ip.Results.gridWidth;

            % Meshgrid for positions
            obj.edgeChecks = ceil(obj.gridWidth / obj.stixelSize);
            [obj.xvals, obj.yvals] = meshgrid( ...
                linspace(-obj.stixelSize*obj.edgeChecks/2+obj.stixelSize/2, ...
                         obj.stixelSize*obj.edgeChecks/2-obj.stixelSize/2, ...
                         obj.edgeChecks));
            obj.positions = [obj.xvals(:), obj.yvals(:)];
            obj.positionList = {};
            obj.traces = {};
            obj.peakMinusBaseline = nan(obj.edgeChecks, obj.edgeChecks);

            obj.createUi();
        end

        function createUi(obj)
            % 2x1 grid: top for traces, bottom for heatmap
            obj.axesHandles(1) = subplot(2,1,1, ...
                'Parent', obj.figureHandle, ...
                'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'));
            hold(obj.axesHandles(1), 'on');
            title(obj.axesHandles(1), 'Optometer traces by position');
            xlabel(obj.axesHandles(1), 'Time (s)');
            ylabel(obj.axesHandles(1), 'Optometer (mV)');

            obj.axesHandles(2) = subplot(2,1,2, ...
                'Parent', obj.figureHandle, ...
                'FontUnits', get(obj.figureHandle, 'DefaultUicontrolFontUnits'), ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'));
            obj.heatmapHandle = imagesc('XData', unique(obj.xvals), 'YData', unique(obj.yvals), ...
                'CData', obj.peakMinusBaseline, 'Parent', obj.axesHandles(2));
            axis(obj.axesHandles(2), 'image');
            colorbar(obj.axesHandles(2));
            title(obj.axesHandles(2), 'Peak - Baseline Heatmap');
            xlabel(obj.axesHandles(2), 'X Position (\mum)');
            ylabel(obj.axesHandles(2), 'Y Position (\mum)');
        end

        function clear(obj)
            cla(obj.axesHandles(1));
            cla(obj.axesHandles(2));
            obj.traces = {};
            obj.positionList = {};
            obj.peakMinusBaseline(:) = nan;
            set(obj.heatmapHandle, 'CData', obj.peakMinusBaseline);
        end

        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                return;
            end

            response = epoch.getResponse(obj.device);
            [quantities, units] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;

            % Get position
            if isKey(epoch.parameters, 'position')
                pos = epoch.parameters('position');
            else
                pos = [nan nan];
            end

            % Store trace and position
            obj.traces{end+1} = quantities;
            obj.positionList{end+1} = pos;

            % Plot all traces, color by position
            cla(obj.axesHandles(1));
            colors = lines(numel(obj.traces));
            t = (0:numel(quantities)-1)/sampleRate;
            legendEntries = {};
            for k = 1:numel(obj.traces)
                trace = obj.traces{k};
                posk = obj.positionList{k};
                plot(obj.axesHandles(1), t, trace, 'Color', colors(k,:), 'LineWidth', 1.2);
                legendEntries{end+1} = sprintf('(%g, %g)', posk(1), posk(2));
            end
            legend(obj.axesHandles(1), legendEntries, 'Interpreter', 'none', 'Location', 'eastoutside');

            % Calculate peak-baseline for this epoch
            prePts = round(obj.preTime / 1e3 * sampleRate);
            stimPts = round(obj.stimTime / 1e3 * sampleRate);
            baseline = mean(quantities(1:prePts));
            stimStart = prePts + 1;
            stimEnd = prePts + stimPts;
            if stimEnd > numel(quantities)
                stimEnd = numel(quantities);
            end
            peak = max(quantities(stimStart:stimEnd));
            pkbl = peak - baseline;

            % Find grid index for this position
            [~, idx] = min(sum((obj.positions - pos).^2, 2));
            [row, col] = ind2sub(size(obj.xvals), idx);
            obj.peakMinusBaseline(row, col) = pkbl;

            % Update heatmap
            set(obj.heatmapHandle, 'CData', obj.peakMinusBaseline);
            drawnow;
        end
    end
end