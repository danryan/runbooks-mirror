local commonAnnotations = import 'common_annotations.libsonnet';
local grafana = import 'grafonnet/grafana.libsonnet';
local layout = import 'layout.libsonnet';
local platformLinks = import 'platform_links.libsonnet';
local saturationDetail = import 'saturation_detail.libsonnet';
local templates = import 'templates.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local template = grafana.template;
local graphPanel = grafana.graphPanel;
local annotation = grafana.annotation;
local basic = import 'basic.libsonnet';
local saturationResources = import './saturation-resources.libsonnet';
local serviceHealth = import './service_health.libsonnet';

local selector = { environment: '$environment', type: '$type', stage: '$stage' };

{
  saturationDashboard(
    dashboardTitle,
    component,
    panel,
    helpPanel,
    defaultType
  )::

    basic.dashboard(
      dashboardTitle,
      tags=[
        'alert-target',
        'saturationdetail',
        if component != '$component' then 'saturationdetail:' + component else 'saturationdetail:general',
      ],
    )
    .addTemplate(
      template.new(
        'type',
        '$PROMETHEUS_DS',
        'label_values(gitlab_service_ops:rate{environment="$environment"}, type)',
        current=defaultType,
        refresh='load',
        sort=1,
      )
    )
    .addTemplate(templates.stage)
    .addPanel(panel, gridPos={ x: 0, y: 0, h: 20, w: 18 })
    .addPanel(helpPanel, gridPos={ x: 18, y: 0, h: 14, w: 6 })
    .addPanel(serviceHealth.activeAlertsPanel('alert_type="symptom", type="${type}", environment="$environment"', title='Potentially User Impacting Alerts'), gridPos={ x: 18, y: 14, h: 6, w: 6 })
    + {
      links+: platformLinks.parameterizedServiceLink +
              platformLinks.services +
              platformLinks.triage +
              [
                platformLinks.dynamicLinks('Service Dashboards', 'type:$type managed', asDropdown=false, includeVars=false, keepTime=false),
                platformLinks.dynamicLinks('Saturation Detail', 'saturationdetail', asDropdown=true, includeVars=true, keepTime=true),
              ],
    },

  saturationDashboardForComponent(
    component
  )::
    local defaultType = saturationResources[component].getDefaultGrafanaType();

    self.saturationDashboard(
      dashboardTitle=component + ': Saturation Detail',
      component=component,
      panel=saturationDetail.componentSaturationPanel(component, selector),
      helpPanel=saturationDetail.componentSaturationHelpPanel(component),
      defaultType=defaultType
    ),
}
