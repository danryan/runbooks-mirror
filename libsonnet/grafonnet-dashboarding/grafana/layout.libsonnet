local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';
local row = g.panel.row;

{
  titleRowWithPanels(title, panels, collapse=false, startRow=0)::
    assert std.isArray(panels) : 'layout.titleRowWithPanels: panels needs to be an array';

    local rowWithPanels =
      row.new(title)
      + row.withPanels(panels)
      + row.withCollapsed(collapse)
      + row.withGridPos(startRow);
    // TODO: don't duplicate this, but it's nicer to work with for now
    self.grid([rowWithPanels, rowWithPanels], cols=std.length(panels)),


  grid(panels, cols=2, rowHeight=10, startRow=0)::
    assert cols < 24 : 'layout.grid: max 24 columns in a grid, given %s' % [cols];

    local panelWidth = 24 / cols;
    g.util.grid.makeGrid(panels, panelWidth=panelWidth, panelHeight=rowHeight, startY=startRow),

}
