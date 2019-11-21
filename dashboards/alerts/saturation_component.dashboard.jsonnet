local saturationAlerts = import 'alerts/saturation_alerts.libsonnet';
local grafana = import 'grafonnet/grafana.libsonnet';
local saturationDetail = import 'saturation_detail.libsonnet';
local seriesOverrides = import 'series_overrides.libsonnet';
local templates = import 'templates.libsonnet';
local text = grafana.text;

local helpPanel = text.new(
  title='Help',
  mode='markdown',
  content=|||
    For further details, select the `Saturation Detail` menu from the links menu at the top of this dashboard,
    then select the detail dashboard for this resource saturation metric.
  |||
);

saturationAlerts.saturationDashboard(
  dashboardTitle='Saturation Component Alert',
  component='$component',
  panel=saturationDetail.saturationPanel(
    title='$component Saturation',
    description='Saturation is a measure of what ratio of a finite resource is currently being utilized. Lower is better.',
    component='$component',
    linewidth=2,
    query=|||
      max(
        max_over_time(
          gitlab_component_saturation:ratio{environment="$environment", type="$type", stage="$stage", component="$component"}[$__interval]
        )
      ) by (component)
    |||,
    legendFormat='{{ component }} component'
  )
        .addSeriesOverride(seriesOverrides.goldenMetric('/ component/')),
  helpPanel=helpPanel
)
.addTemplate(templates.saturationComponent)
