function lightAxes(ax)
%LIGHTAXES  Force an axes to a light, print-safe style.
%
%   MATLAB R2025a applies a figure THEME that can render exported graphics
%   on a dark surface even when the figure's Color is set to white. A
%   diagnostic figure that flips appearance with the user's IDE theme is not
%   reproducible, and the palette these plots use was validated against a
%   LIGHT surface (dataviz validator, surface #fcfcfb) -- on a dark surface
%   the contrast checks it passed no longer apply.
%
%   So the surface is pinned here rather than inherited. Grid and axis lines
%   stay recessive; text is near-black, never the series colour.

    ax.Color = 'w';
    ax.XColor = [0.20 0.20 0.20];
    ax.YColor = [0.20 0.20 0.20];
    ax.GridColor = [0.15 0.15 0.15];
    ax.GridAlpha = 0.12;
    ax.Box = 'off';
    ax.Layer = 'top';
    ax.TickDir = 'out';
    ax.FontSize = 9;
    ax.Title.Color = [0.10 0.10 0.10];
    ax.XLabel.Color = [0.25 0.25 0.25];
    ax.YLabel.Color = [0.25 0.25 0.25];
end
