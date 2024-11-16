local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';
local row = g.panel.row;

{
  titleRowWithPanels(title, panels, collapse, startRow)::
    assert std.isArray(panels) : 'layout.titleRowWithPanels: panels needs to be an array';

    row.new(title)
    + row.withPanels(panels)
    + row.withCollapsed(collapse)
    + row.withGridPos(startRow),

  grid(panels, cols=2, rowHeight=10, startRow=0)::
    assert std.isArray(panels) : 'layout.grid: panels needs to be an array';

    local panelWidth = 24 / cols;
    g.util.grid.makeGrid(panels, panelWidth, rowHeight, startRow),

}
