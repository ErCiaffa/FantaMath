classdef FantaGraph
    methods(Static)
        function drawScatter(ax, viewModel, opts)
            if nargin < 3
                opts = struct();
            end
            scatter(ax, viewModel.x, viewModel.y, 24, viewModel.c, 'filled');
            grid(ax, 'on');
            xlabel(ax, viewModel.xLabel);
            ylabel(ax, viewModel.yLabel);
            if isfield(opts, 'title')
                title(ax, opts.title);
            end
        end

        function drawHist(ax, viewModel, opts)
            if nargin < 3
                opts = struct();
            end
            histogram(ax, viewModel.values, 'FaceColor', [0.2 0.5 0.8]);
            grid(ax, 'on');
            xlabel(ax, viewModel.xLabel);
            ylabel(ax, 'Conteggio');
            if isfield(opts, 'title')
                title(ax, opts.title);
            end
        end

        function drawHeatmap(ax, viewModel, opts)
            if nargin < 3
                opts = struct();
            end
            imagesc(ax, viewModel.matrix);
            axis(ax, 'tight');
            colormap(ax, 'turbo');
            colorbar(ax);
            if isfield(viewModel, 'xTick')
                ax.XTick = viewModel.xTick;
                ax.XTickLabel = viewModel.xTickLabel;
            end
            if isfield(viewModel, 'yTick')
                ax.YTick = viewModel.yTick;
                ax.YTickLabel = viewModel.yTickLabel;
            end
            if isfield(opts, 'title')
                title(ax, opts.title);
            end
        end
    end
end
