local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';

local commonAnnotations = import 'grafonnet-dashboarding/grafana/common_annotations.libsonnet';
local commonVariables = import 'grafonnet-dashboarding/grafana/common_variables.libsonnet';

local refreshIntervals = g.dashboard.timepicker.withRefreshIntervals(['5m', '10m', '15m', '30m']);

/* Validates each tag on a dashboard */
local validateTag(tag) =
  if !std.isString(tag) then error 'dashboard tags must be strings, got %s' % [tag]
  else if tag == '' then error 'dashboard tag cannot be empty'
  else if std.length(tag) > 50 then error 'dashboard tag cannot exceed 50 characters in length: %s' % [tag]
  else tag;

local validateTags(tags) =
  [
    validateTag(tag)
    for tag in tags
  ];


function(
  title,
  tags,
  editable=false,
  time_from='now-6h/m',
  time_to='now/m',
  graphTooltip='shared_crosshair',
  description=null,
  includeStandardEnvironmentAnnotations=true,
  includeEnvironmentTemplate=true,
  uid=null,
  defaultDatasource=null,
)
  local annotations = if includeStandardEnvironmentAnnotations then
    commonAnnotations.standardEnvironmentAnnotations
  else [];

  local tooltip = if graphTooltip == 'shared_crosshair' then
    g.dashboard.graphTooltip.withSharedCrosshair()
  else
    g.dashboard.graphTooltip.withSharedTooltip();

  local variables = [commonVariables.ds(defaultDatasource)]
                    + if includeEnvironmentTemplate then [commonVariables.environment] else [];

  local dashboard =
    g.dashboard.new(title)
    + g.dashboard.withDescription(description)
    + g.dashboard.withTags(validateTags(tags))
    + g.dashboard.withEditable(editable)
    + g.dashboard.time.withFrom(time_from)
    + g.dashboard.time.withTo(time_to)
    + g.dashboard.withTimezone('utc')
    + g.dashboard.withRefresh('')
    + refreshIntervals
    + tooltip
    + g.dashboard.withAnnotations(annotations)
    + g.dashboard.withVariables(variables)
    + if uid != null then g.dashboard.withUid(uid) else {};

  dashboard {
    addPanels(panels)::
      assert std.isArray(panels) : 'dashboard.addPanels: panels needs to be an array';

      self
      + g.dashboard.withPanelsMixin(panels),

    addAnnotationIf(condition, annotation)::
      if condition then
        self + g.dashboard.withAnnotationsMixin([annotation])
      else
        self,

    trailer()::
      self
      + g.dashboard.withPanelsMixin(
        g.util.grid.wrapPanels(
          [
            g.panel.text.new('Source')
            + g.panel.text.options.code.withLanguage('markdown')
            + g.panel.text.options.withContent(|||
              Made with ❤️ and [Grafonnet](https://github.com/grafana/grafonnet). [Contribute to this dashboard on GitLab.com](https://gitlab.com/gitlab-com/runbooks/blob/master/dashboards)
            |||),
          ],
          panelWidth=24,
          panelHeight=2,
          startY=11000
        )
      ),
  }
